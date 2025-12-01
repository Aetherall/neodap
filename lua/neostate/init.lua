---@diagnostic disable: invisible
local M = {}

-- =============================================================================
-- 0. TELEMETRY & CONFIGURATION
-- =============================================================================

local Config = {
  trace = false,         -- Enable logging
  debug_context = false, -- Enable file:line introspection (expensive)
  log_fn = function(msg) print(msg) end
}

--- Configure the reactor
--- @param opts { trace: boolean, debug_context: boolean, log_fn: function }
function M.setup(opts)
  Config = vim.tbl_extend("force", Config, opts or {})
end

-- Internal: Visual indentation based on stack depth
local _stack_depth = 0
local function get_indent() return string.rep("  ", _stack_depth) end

local function is_disposable(v)
  return type(v) == "table" and type(v.dispose) == "function" and type(v.on_dispose) == "function"
end

-- Introspection: Finds the caller outside of reactor.lua
local function get_caller_info()
  if not Config.debug_context then return "" end
  -- Scan frames 3-7 to find user code
  for i = 3, 7 do
    local info = debug.getinfo(i, "Sln")
    if not info then break end
    if info.source and not info.source:match("neostate/init.lua$") then
      local src = info.source:sub(2) -- remove '@'
      local filename = src:match("^.+/(.+)$") or src
      return string.format(" @%s:%d", filename, info.currentline)
    end
  end
  return ""
end

local function trace(icon, subject, action)
  if not Config.trace then return end
  local context = get_caller_info()
  local info = string.format("%s%s %-20s %-25s %s",
    get_indent(), icon, "[" .. tostring(subject) .. "]", action or "", context)
  Config.log_fn(info)
end

-- =============================================================================
-- 1. CONTEXT ENGINE (The Stack)
-- =============================================================================

local _active_contexts = setmetatable({}, { __mode = "k" })

local function get_current_context()
  local co = coroutine.running() or "main"
  return _active_contexts[co]
end

-- =============================================================================
-- 2. DISPOSABLE TRAIT (Lifecycle)
-- =============================================================================

local Disposable = {}

--- Registers a cleanup function
function Disposable:on_dispose(fn)
  if self._disposed then
    pcall(fn); return function() end
  end
  table.insert(self._disposables, fn)
  return function()
    local idx = vim.iter(self._disposables):enumerate():find(function(_, f) return f == fn end)
    if idx then table.remove(self._disposables, idx) end
  end
end

--- Kills object and children (LIFO)
function Disposable:dispose()
  if self._disposed then return end

  trace("🔴", self._debug_name, "Disposing...")
  self._disposed = true

  vim.iter(self._disposables):rev():each(function(fn)
    local ok, err = pcall(fn)
    if not ok then
      vim.notify("[Reactor] Error disposing: " .. tostring(err), vim.log.levels.WARN)
    end
  end)
  self._disposables = {}
end

--- Runs fn with 'self' as implicit parent
function Disposable:run(fn, ...)
  local co = coroutine.running() or "main"
  local prev = _active_contexts[co]

  _active_contexts[co] = self
  _stack_depth = _stack_depth + 1

  local ok, err = pcall(fn, ...)

  _stack_depth = _stack_depth - 1
  _active_contexts[co] = prev

  if not ok then error(err) end
end

--- Binds a callback to this lifecycle (for async/network)
function Disposable:bind(fn)
  return function(...)
    return self:run(fn, ...)
  end
end

function Disposable:set_parent(new_parent)
  if self._parent_unsubscribe then
    self._parent_unsubscribe()
    self._parent_unsubscribe = nil
  end

  if new_parent then
    if type(new_parent.on_dispose) == "function" then
      trace("🔗", self._debug_name, "Attached to " .. (new_parent._debug_name or "Unknown"))
      self._parent_unsubscribe = new_parent:on_dispose(function() self:dispose() end)
    else
      error("[Reactor] Parent must be a Disposable")
    end
  else
    trace("🌱", self._debug_name, "Detached (Root)")
  end
end

--- Mixin: Applies Disposable trait to a table
function M.Disposable(target, explicit_parent, debug_name)
  target = target or {}

  target._disposed = false
  target._disposables = {}
  target._debug_name = debug_name or "Disposable"

  for k, v in pairs(Disposable) do
    target[k] = v
  end

  local parent = explicit_parent or get_current_context()
  target:set_parent(parent)

  -- Add __gc metamethod to trigger disposal when garbage collected
  -- This allows ephemeral signals to cleanup listeners automatically
  local mt = getmetatable(target) or {}
  local old_gc = mt.__gc
  mt.__gc = function(self)
    if not self._disposed then
      self:dispose()
    end
    if old_gc then old_gc(self) end
  end
  setmetatable(target, mt)

  return target
end

-- =============================================================================
-- 3. REACTIVE SIGNAL
-- =============================================================================

function M.Signal(initial_value, debug_name)
  debug_name = debug_name or "Signal"
  local self = M.Source(debug_name)

  local _current_item = nil

  function self.iter()
    if _current_item then
      return vim.iter({ _current_item })
    else
      return vim.iter({})
    end
  end

  local function wrap(val)
    if type(val) == "table" then
      if is_disposable(val) then
        -- For computed signals, always create non-owning reference wrappers
        -- because computed values come from external sources (EntityStore, etc.)
        -- For regular signals with external disposables that already have parents,
        -- also create non-owning references
        if self._is_computed or val._parent_unsubscribe then
          return M.Disposable({ _ref = val }, self, debug_name .. ":Ref")
        end
        -- Regular signal with orphan disposable - take ownership
        val:set_parent(self)
        return val
      end
      return M.Disposable(val, self, debug_name .. ":Item")
    else
      return M.Disposable({ value = val, _wrapped = true }, self, debug_name .. ":Item")
    end
  end

  function self:get()
    if not _current_item then return nil end
    if _current_item._ref then return _current_item._ref end -- Non-owning reference
    if _current_item._wrapped then return _current_item.value end
    return _current_item
  end

  function self:set(new_val)
    if self._disposed then return end
    local old_val = self:get()
    if old_val == new_val then return end

    trace("⚡", self._debug_name, string.format("%s -> %s", tostring(old_val), tostring(new_val)))

    -- Dispose old item (triggers cleanup of effects)
    if _current_item then _current_item:dispose() end

    -- Create new item
    _current_item = wrap(new_val)

    -- Emit
    self:_emit(_current_item)
  end

  -- Compatibility wrapper
  function self:use(fn)
    return self:each(function(item)
      if item._ref then return fn(item._ref) end -- Non-owning reference
      if item._wrapped then return fn(item.value) end
      return fn(item)
    end)
  end

  -- Subscribe to value changes (unwrapped)
  function self:watch(fn)
    return self:subscribe(function(item)
      if item._ref then return fn(item._ref) end -- Non-owning reference
      if item._wrapped then return fn(item.value) end
      return fn(item)
    end)
  end

  -- Release the current value WITHOUT disposing it
  -- Use this when you want to move the value elsewhere (e.g., to a stale list)
  -- Returns the unwrapped value, or nil if none
  function self:release()
    if not _current_item then return nil end
    local val = self:get()
    _current_item = nil
    return val
  end

  -- Initialize
  _current_item = wrap(initial_value)

  return self
end

-- =============================================================================
-- 3b. COMPUTED SIGNAL
-- =============================================================================

--- Creates a computed signal that derives its value from other signals
--- The computation re-runs whenever any dependency changes
--- @param fn function Computation function that returns the derived value
--- @param deps table Array of Signal dependencies to watch
--- @param debug_name string? Optional debug name
--- @return table Computed signal (read-only Signal)
function M.computed(fn, deps, debug_name)
  debug_name = debug_name or "Computed"

  -- Create a signal to hold the computed value
  -- We pass nil as initial, will compute below
  local result = M.Signal(nil, debug_name)

  -- Track if we're currently computing (prevent infinite loops)
  local computing = false

  -- Recompute function
  local function recompute()
    if computing then return end
    if result._disposed then return end

    computing = true
    local ok, value = pcall(fn)
    computing = false

    if ok then
      result:set(value)
    else
      vim.notify("[Computed] Error: " .. tostring(value), vim.log.levels.WARN)
    end
  end

  -- Mark as computed BEFORE initial recompute so wrap() creates reference wrappers
  result._is_computed = true

  -- Watch all dependencies for changes
  if deps then
    for _, dep in ipairs(deps) do
      if dep and type(dep) == "table" and dep.watch then
        local unsub = dep:watch(function()
          recompute()
        end)
        result:on_dispose(unsub)
      end
    end
  end

  -- Initial computation
  recompute()

  return result
end

-- =============================================================================
-- 4. REACTIVE SOURCE (Abstract Base)
-- =============================================================================

-- Helper: Wraps user callback in Item Context
local function execute_wrapped(fn)
  return function(item)
    local cleanup = nil
    item:run(function()
      local res = fn(item)
      if type(res) == "function" then cleanup = res end
    end)
    return cleanup
  end
end

function M.Source(debug_name)
  local self = M.Disposable({}, nil, debug_name)
  self._listeners = {}
  self._item_cleanups = {} -- [item] = { fn... }

  -- Abstract: Subclasses must implement self.iter() -> vim.iter

  -- Internal: Register cleanup for an item
  function self:_register_cleanup(item, cleanup)
    if not cleanup then return end
    if not self._item_cleanups[item] then
      self._item_cleanups[item] = {}
      -- Ensure cleanups run on dispose
      item:on_dispose(function() self:_run_cleanups(item) end)
    end
    -- Re-check after on_dispose in case item was already disposed
    -- (on_dispose runs callback immediately if item is already disposed)
    if not self._item_cleanups[item] then return end
    table.insert(self._item_cleanups[item], cleanup)
  end

  -- Internal: Run cleanups for an item
  function self:_run_cleanups(item)
    local fns = self._item_cleanups[item]
    if fns then
      self._item_cleanups[item] = nil
      for _, fn in ipairs(fns) do pcall(fn) end
    end
  end

  -- 1. SUBSCRIBE (Future Items)
  function self:subscribe(fn)
    trace("👀", self._debug_name, "subscribe registered")

    local wrapper = execute_wrapped(fn)
    table.insert(self._listeners, wrapper)

    return function() -- Unsubscribe
      local idx = vim.iter(self._listeners):enumerate():find(function(_, l) return l == wrapper end)
      if idx then table.remove(self._listeners, idx) end
    end
  end

  -- 2. EACH (Existing + Future)
  function self:each(fn)
    local wrapper = execute_wrapped(fn)
    -- Replay existing items
    if self.iter then
      self.iter():each(function(item)
        local cleanup = wrapper(item)
        self:_register_cleanup(item, cleanup)
      end)
    end
    -- Listen for new ones
    return self:subscribe(fn)
  end

  -- Protected: Notify listeners
  function self:_emit(item)
    vim.iter(self._listeners):each(function(listener)
      local cleanup = listener(item)
      self:_register_cleanup(item, cleanup)
    end)
  end

  return self
end

-- =============================================================================
-- 5. OBSERVABLE LIST (Implementation)
-- =============================================================================

function M.List(debug_name)
  debug_name = debug_name or "List"
  local self = M.Source(debug_name)
  self._items = {}
  self._removal_listeners = {}

  -- Implement Abstract Iterator
  function self.iter()
    return vim.iter(self._items)
  end

  -- Internal: Fire removal event
  function self:_fire_removal(item)
    for _, listener in ipairs(self._removal_listeners) do
      pcall(listener, item)
    end
  end

  -- Aliases for Collection semantics
  function self:on_added(fn)
    return self:subscribe(fn)
  end

  function self:on_removed(fn)
    table.insert(self._removal_listeners, fn)
    return function()
      -- Unsubscribe
      for i, listener in ipairs(self._removal_listeners) do
        if listener == fn then
          table.remove(self._removal_listeners, i)
          break
        end
      end
    end
  end

  -- 4. ACTION: ADD
  function self:add(item)
    if not is_disposable(item) then
      error("[Reactor] List.add: Item must be a Disposable/Source")
    end
    return self:adopt(item)
  end

  -- 5. ACTION: DELETE (Remove + Dispose)
  function self:delete(id_check_fn)
    for i, item in ipairs(self._items) do
      if id_check_fn(item) then
        trace("📤", self._debug_name, "Deleting Item")
        -- Run cleanups before removing from list
        self:_run_cleanups(item)
        table.remove(self._items, i)
        -- Fire removal event
        self:_fire_removal(item)
        -- Dispose after removal so cleanup callbacks see item removed
        item:dispose()
        return item
      end
    end
  end

  -- 6. ACTION: EXTRACT (Remove + Keep Alive)
  function self:extract(id_check_fn)
    for i, item in ipairs(self._items) do
      if id_check_fn(item) then
        trace("📤", self._debug_name, "Extracting Item")
        self:_run_cleanups(item)
        if item.set_parent then item:set_parent(nil) end
        table.remove(self._items, i)
        -- Fire removal event
        self:_fire_removal(item)
        return item
      end
    end
  end

  -- 7. ACTION: ADOPT (Add existing disposable)
  function self:adopt(item)
    if item.set_parent then item:set_parent(self) end
    table.insert(self._items, item)
    trace("📥", self._debug_name, "Adopted Item. Count: " .. #self._items)
    self:_emit(item)
    return item
  end

  -- 8. HELPER: CALL (Call method on each item)
  function self:call(method_name, ...)
    local args = { ... }
    for item in self.iter() do
      item[method_name](item, unpack(args))
    end
  end

  -- 9. HELPER: FOR_EACH (Execute function for each item)
  function self:for_each(fn)
    for item in self.iter() do
      fn(item)
    end
  end

  -- 9b. HELPER: SORT (Sort items in place)
  function self:sort(comparator)
    table.sort(self._items, comparator)
  end

  -- 10. HELPER: FIND (Find first item matching predicate or name)
  --- @param predicate_or_name function|string Predicate function or name string
  --- @return any? First matching item or nil
  function self:find(predicate_or_name)
    local predicate
    if type(predicate_or_name) == "string" then
      -- Search by .name property
      local name = predicate_or_name
      predicate = function(item) return item.name == name end
    else
      predicate = predicate_or_name
    end

    for item in self.iter() do
      if predicate(item) then
        return item
      end
    end
    return nil
  end

  -- 11. HELPER: LATEST (Get reactive Signal for most recently added item)
  function self:latest()
    local result = M.Signal(nil, self._debug_name .. ":latest")
    result:set_parent(self)

    -- Set initial value to the last item (most recently added)
    if #self._items > 0 then
      result:set(self._items[#self._items])
    end

    -- Update when new items are added
    local unsub_added = self:on_added(function(item)
      result:set(item)
    end)

    -- When current latest is removed, find the new latest
    local unsub_removed = self:on_removed(function(item)
      if result:get() == item then
        -- Set to new latest (last item) or nil if empty
        if #self._items > 0 then
          result:set(self._items[#self._items])
        else
          result:set(nil)
        end
      end
    end)

    result:on_dispose(unsub_added)
    result:on_dispose(unsub_removed)

    return result
  end

  return self
end

-- =============================================================================
-- 6. OBSERVABLE SET (Implementation)
-- =============================================================================

function M.Set(debug_name)
  debug_name = debug_name or "Set"
  local self = M.Source(debug_name)
  self._items = {} -- Set: [item] = true

  function self.iter()
    return vim.iter(pairs(self._items)):map(function(k) return k end)
  end

  function self:add(item)
    if not is_disposable(item) then
      error("[Reactor] Set.add: Item must be a Disposable/Source")
    end

    if item.set_parent then item:set_parent(self) end
    self._items[item] = true
    trace("📥", self._debug_name, "Added Item")
    self:_emit(item)
    return item
  end

  function self:remove(item)
    if self._items[item] then
      trace("📤", self._debug_name, "Removing Item")
      self:_run_cleanups(item)
      item:dispose()
      self._items[item] = nil
    end
  end

  return self
end

-- =============================================================================
-- 7. ROOT MOUNTER & UTILS
-- =============================================================================

--- Mounts a root disposable to a buffer lifecycle
function M.mount(bufnr, debug_name)
  debug_name = debug_name or ("Root:" .. tostring(bufnr))
  local root = M.Disposable({}, nil, debug_name)

  if bufnr and bufnr ~= 0 and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      callback = function()
        trace("❌", "BufWipeout", "Buffer " .. bufnr .. " died")
        root:dispose()
      end,
      once = true
    })
  end

  return root
end

--- Fire-and-forget async helper
function M.void(fn)
  return function(...)
    local args = { ... }
    local current_context = get_current_context()

    local co = coroutine.create(function()
      -- Set context for the coroutine
      if current_context then
        local running_co = coroutine.running()
        _active_contexts[running_co] = current_context
      end

      local ok, err = pcall(fn, unpack(args))
      if not ok then
        vim.notify("[neostate] Error in void: " .. tostring(err), vim.log.levels.ERROR)
      end
    end)

    coroutine.resume(co)
  end
end

-- =============================================================================
-- 8. PROMISE (Async/Await)
-- =============================================================================

--- Creates a new Promise
--- @param executor function(resolve, reject)? Optional executor function
--- @param debug_name string? Optional debug name
--- @return table Promise object
function M.Promise(executor, debug_name)
  debug_name = debug_name or "Promise"
  local self = M.Disposable({}, nil, debug_name)

  self._state = "pending" -- "pending" | "fulfilled" | "rejected"
  self._result = nil
  self._error = nil
  self._waiting_coroutines = {} -- List of coroutines waiting on this promise
  self._then_callbacks = {}
  self._catch_callbacks = {}

  --- Resolve the promise with a value
  function self:resolve(value)
    if self._state ~= "pending" then return end
    if self._disposed then return end

    trace("✅", self._debug_name, "Resolved: " .. tostring(value))
    self._state = "fulfilled"
    self._result = value

    -- Resume waiting coroutines
    for _, co_data in ipairs(self._waiting_coroutines) do
      local co = co_data.co
      local ok, err = coroutine.resume(co, value, nil)
      if not ok then
        vim.notify("[Promise] Error resuming coroutine: " .. tostring(err), vim.log.levels.ERROR)
      end
    end
    self._waiting_coroutines = {}

    -- Run then callbacks
    for _, cb in ipairs(self._then_callbacks) do
      local ok, err = pcall(cb, value)
      if not ok then
        vim.notify("[Promise] Error in then callback: " .. tostring(err), vim.log.levels.ERROR)
      end
    end
  end

  --- Reject the promise with an error
  --- @param err any The error to reject with
  --- @param skip_disposed_check boolean? Internal flag to skip disposed check
  function self:reject(err, skip_disposed_check)
    if self._state ~= "pending" then return end
    if not skip_disposed_check and self._disposed then return end

    trace("❌", self._debug_name, "Rejected: " .. tostring(err))
    self._state = "rejected"
    self._error = err

    -- Resume waiting coroutines
    for _, co_data in ipairs(self._waiting_coroutines) do
      local co = co_data.co
      local ok, resume_err = coroutine.resume(co, nil, err)
      if not ok then
        vim.notify("[Promise] Error resuming coroutine: " .. tostring(resume_err), vim.log.levels.ERROR)
      end
    end
    self._waiting_coroutines = {}

    -- Run catch callbacks
    for _, cb in ipairs(self._catch_callbacks) do
      local ok, cb_err = pcall(cb, err)
      if not ok then
        vim.notify("[Promise] Error in catch callback: " .. tostring(cb_err), vim.log.levels.ERROR)
      end
    end
  end

  --- Add a then callback
  --- @param fn function(value)
  --- @return table self for chaining
  function self:then_do(fn)
    if self._disposed then return self end

    if self._state == "fulfilled" then
      local ok, err = pcall(fn, self._result)
      if not ok then
        vim.notify("[Promise] Error in then callback: " .. tostring(err), vim.log.levels.ERROR)
      end
    elseif self._state == "pending" then
      table.insert(self._then_callbacks, fn)
    end
    return self
  end

  --- Add a catch callback
  --- @param fn function(error)
  --- @return table self for chaining
  function self:catch_do(fn)
    if self._disposed then return self end

    if self._state == "rejected" then
      local ok, err = pcall(fn, self._error)
      if not ok then
        vim.notify("[Promise] Error in catch callback: " .. tostring(err), vim.log.levels.ERROR)
      end
    elseif self._state == "pending" then
      table.insert(self._catch_callbacks, fn)
    end
    return self
  end

  --- Check if promise is settled (fulfilled or rejected)
  function self:is_settled()
    return self._state ~= "pending"
  end

  --- Check if promise is pending
  function self:is_pending()
    return self._state == "pending"
  end

  -- Execute the executor function
  if executor and type(executor) == "function" then
    local ok, err = pcall(function()
      executor(
        function(val) self:resolve(val) end,
        function(e) self:reject(e) end
      )
    end)
    if not ok then
      self:reject(err)
    end
  end

  -- Cleanup waiting coroutines on dispose
  self:on_dispose(function()
    if self._state == "pending" then
      self:reject("Promise disposed before settling", true)
    end
  end)

  return self
end

--- Await a promise (must be called from within a coroutine)
--- If the value is not a promise, it is returned immediately
--- @param promise_or_value any The promise to await, or a regular value
--- @return any result The resolved value
function M.await(promise_or_value)
  -- If not a promise, return the value directly
  if type(promise_or_value) ~= "table" or not promise_or_value._state then
    trace("⏩", "await", "Not a promise, returning value directly")
    return promise_or_value
  end

  local promise = promise_or_value

  -- Must be in coroutine (check this first, even for settled promises)
  -- coroutine.running() returns (thread, is_main) in Lua 5.2+
  local co, is_main = coroutine.running()
  if not co or is_main then
    error("[Promise] await can only be called from within a coroutine")
  end

  -- Check if already settled
  if promise._state == "fulfilled" then
    trace("⏩", "await", "Promise already fulfilled")
    return promise._result
  elseif promise._state == "rejected" then
    trace("⏩", "await", "Promise already rejected")
    error(promise._error)
  end

  trace("⏸️", "await", "Suspending coroutine...")

  -- Register this coroutine to be resumed
  table.insert(promise._waiting_coroutines, { co = co })

  -- Yield and wait for resume
  local result, err = coroutine.yield()

  if err then
    trace("⏩", "await", "Resumed with error")
    error(err)
  end

  trace("⏩", "await", "Resumed with result")
  return result
end

--- Settle a promise (returns result, err tuple)
--- If the value is not a promise, it is returned as (value, nil)
--- @param promise_or_value any The promise to settle, or a regular value
--- @return any result The resolved value or nil
--- @return any err The error or nil
function M.settle(promise_or_value)
  -- If not a promise, return the value directly
  if type(promise_or_value) ~= "table" or not promise_or_value._state then
    trace("⏩", "settle", "Not a promise, returning value directly")
    return promise_or_value, nil
  end

  local promise = promise_or_value

  -- Must be in coroutine (check this first, even for settled promises)
  -- coroutine.running() returns (thread, is_main) in Lua 5.2+
  local co, is_main = coroutine.running()
  if not co or is_main then
    error("[Promise] settle can only be called from within a coroutine")
  end

  -- Check if already settled
  if promise._state == "fulfilled" then
    trace("⏩", "settle", "Promise already fulfilled")
    return promise._result, nil
  elseif promise._state == "rejected" then
    trace("⏩", "settle", "Promise already rejected")
    return nil, promise._error
  end

  trace("⏸️", "settle", "Suspending coroutine...")

  -- Register this coroutine to be resumed
  table.insert(promise._waiting_coroutines, { co = co })

  -- Yield and wait for resume (returns result, err)
  local result, err = coroutine.yield()

  trace("⏩", "settle", "Resumed")
  return result, err
end

-- =============================================================================
-- 7. COLLECTION (List + Indexing)
-- =============================================================================

function M.Collection(debug_name)
  debug_name = debug_name or "Collection"
  local self = M.List(debug_name)

  -- Indexes: { [name] = { getter = fn, map = { [key] = { item... } } } }
  self._indexes = {}
  -- Track current keys for items: { [item] = { [index_name] = key } }
  self._item_keys = {}

  --- Defines a new index
  --- @param name string Name of the index
  --- @param getter function(item) -> value | Signal
  function self:add_index(name, getter)
    if self._indexes[name] then error("Index " .. name .. " already exists") end
    self._indexes[name] = { getter = getter, map = {} }

    -- If we had existing items, we would index them here.
    -- For now, assume indexes are defined before adding items.
    if #self._items > 0 then
      for _, item in ipairs(self._items) do
        self:_track_item_index(item, name)
      end
    end
  end

  --- Internal: Update index for an item
  function self:_update_index_entry(item, index_name, new_key)
    local index = self._indexes[index_name]
    if not index then return end

    -- Remove from old key
    local item_keys = self._item_keys[item] or {}
    local old_key = item_keys[index_name]

    if old_key ~= nil then
      local bucket = index.map[old_key]
      if bucket then
        for i, it in ipairs(bucket) do
          if it == item then
            table.remove(bucket, i)
            break
          end
        end
        if #bucket == 0 then index.map[old_key] = nil end
      end
    end

    -- Add to new key
    if new_key ~= nil then
      local bucket = index.map[new_key]
      if not bucket then
        bucket = {}
        index.map[new_key] = bucket
      end
      table.insert(bucket, item)
    end

    -- Update tracked key
    if not self._item_keys[item] then self._item_keys[item] = {} end
    self._item_keys[item][index_name] = new_key
  end

  --- Internal: Setup tracking for an item on a specific index
  function self:_track_item_index(item, index_name)
    local index = self._indexes[index_name]
    local val = index.getter(item)

    -- Check if it's a Signal (duck typing: has .get and .subscribe/watch)
    if type(val) == "table" and val.get and val.watch then
      -- Initial value
      self:_update_index_entry(item, index_name, val:get())

      -- Watch for changes
      local unsub = val:watch(function(new_key)
        self:_update_index_entry(item, index_name, new_key)
      end)

      -- Register cleanup on the item itself, so if item is removed/disposed, we stop watching
      -- We use the List/Source mechanism `_register_cleanup` which runs when item is removed/extracted
      self:_register_cleanup(item, unsub)
    else
      -- Static value
      self:_update_index_entry(item, index_name, val)
    end
  end

  -- Override adopt to setup indexes
  local super_adopt = self.adopt
  function self:adopt(item)
    -- Call super
    local ret = super_adopt(self, item)

    -- Setup indexes
    for name, _ in pairs(self._indexes) do
      self:_track_item_index(item, name)
    end

    -- Cleanup index entries when item is removed (via _register_cleanup)
    self:_register_cleanup(item, function()
      -- Remove from all indexes
      for name, _ in pairs(self._indexes) do
        self:_update_index_entry(item, name, nil)
      end
      self._item_keys[item] = nil
    end)

    return ret
  end

  --- Query: Get all items for a key
  function self:get(index_name, key)
    local index = self._indexes[index_name]
    if not index then error("Unknown index: " .. index_name) end
    return index.map[key]
  end

  --- Query: Get one item for a key
  function self:get_one(index_name, key)
    local items = self:get(index_name, key)
    if items and #items > 0 then return items[1] end
    return nil
  end

  --- Aggregate: Apply function over items and return reactive Signal of result
  --- The signal updates when items are added/removed or when watched signals change
  --- @param aggregator function(items) -> value Function that computes aggregate from item list
  --- @param signal_getter function(item) -> Signal? Optional: extract signal to watch per item
  --- @return Signal Reactive signal that updates when collection or signals change
  function self:aggregate(aggregator, signal_getter)
    -- Create result signal
    local result = M.Signal(nil, self._debug_name .. ":aggregate")
    result:set_parent(self)

    -- Store result in weak table to break circular reference
    -- This allows ephemeral signals to be GC'd when no external strong refs exist
    local weak_result = setmetatable({ result }, { __mode = "v" })

    -- Helper to recompute aggregate
    local function recompute()
      local r = weak_result[1]
      if not r then return end -- Signal was GC'd
      local value = aggregator(self._items)
      r:set(value)
    end

    -- Initial computation
    recompute()

    -- Watch for items added/removed
    local unsub_added = self:on_added(function(item)
      -- If signal_getter provided, watch the signal on this item
      if signal_getter then
        local signal = signal_getter(item)
        if signal and type(signal) == "table" and signal.watch then
          local unsub_signal = signal:watch(function()
            recompute()
          end)
          -- Register cleanup so we stop watching when item is removed
          self:_register_cleanup(item, unsub_signal)
        end
      end
      recompute()
    end)

    local unsub_removed = self:on_removed(function()
      recompute()
    end)

    -- Setup signal watching for existing items
    if signal_getter then
      for _, item in ipairs(self._items) do
        local signal = signal_getter(item)
        if signal and type(signal) == "table" and signal.watch then
          local unsub_signal = signal:watch(function()
            recompute()
          end)
          self:_register_cleanup(item, unsub_signal)
        end
      end
    end

    -- Cleanup subscriptions when result signal is disposed
    result:on_dispose(unsub_added)
    result:on_dispose(unsub_removed)

    return result
  end

  --- Check if any item matches predicate (returns reactive Signal)
  --- @param predicate_or_getter function(item) -> boolean | function(item) -> Signal<boolean>
  --- @return Signal<boolean> Signal that is true if any item matches
  function self:some(predicate_or_getter)
    -- Always pass predicate_or_getter as signal_getter to handle:
    -- 1. Empty collections that get items added later
    -- 2. Signal-based predicates that need watching
    -- The aggregate function handles both Signal and boolean returns
    return self:aggregate(
      function(items)
        for _, item in ipairs(items) do
          local result = predicate_or_getter(item)
          -- Handle both Signal<boolean> and direct boolean
          local value
          if type(result) == "table" and result.get then
            value = result:get()
          else
            value = result
          end
          if value then
            return true
          end
        end
        return false
      end,
      predicate_or_getter -- Watch signals returned by getter
    )
  end

  --- Check if all items match predicate (returns reactive Signal)
  --- @param predicate_or_getter function(item) -> boolean | function(item) -> Signal<boolean>
  --- @return Signal<boolean> Signal that is true if all items match
  function self:every(predicate_or_getter)
    -- Always pass predicate_or_getter as signal_getter to handle:
    -- 1. Empty collections that get items added later
    -- 2. Signal-based predicates that need watching
    -- The aggregate function handles both Signal and boolean returns
    return self:aggregate(
      function(items)
        for _, item in ipairs(items) do
          local result = predicate_or_getter(item)
          -- Handle both Signal<boolean> and direct boolean
          local value
          if type(result) == "table" and result.get then
            value = result:get()
          else
            value = result
          end
          if not value then
            return false
          end
        end
        return true
      end,
      predicate_or_getter -- Watch signals returned by getter
    )
  end

  --- Create a filtered view of this collection
  --- @param index_or_predicate string|function Index name or predicate function
  --- @param index_value any? Value to filter by (only if first arg is string)
  --- @param collection_name string? Optional name for the filtered collection (defaults to "parent:filtered")
  --- @return table Filtered collection
  function self:where(index_or_predicate, index_value, collection_name)
    -- Determine collection name
    local child_name = collection_name or (self._debug_name .. ":filtered")

    -- Create child collection
    local child = M.Collection(child_name)

    -- Track parent-child relationship
    child._parent_collection = self

    -- Copy all indexes from parent to child (filtered views inherit all parent indexes)
    -- Each child gets its own index maps (not shared with parent)
    for index_name, index_def in pairs(self._indexes) do
      child._indexes[index_name] = {
        getter = index_def.getter,
        map = {} -- Fresh map for this filtered collection
      }
    end

    -- Determine filter type and store filter data
    if type(index_or_predicate) == "string" then
      child._filter_type = "index"
      child._filter_data = { index_name = index_or_predicate, index_value = index_value }
    elseif type(index_or_predicate) == "function" then
      child._filter_type = "predicate"
      child._filter_data = { predicate = index_or_predicate }
    else
      error("[Collection] where: First argument must be string (index name) or function (predicate)")
    end

    -- Helper: Check if item matches filter
    local function matches_filter(item)
      if child._filter_type == "index" then
        local index_name = child._filter_data.index_name
        local expected_value = child._filter_data.index_value

        -- Get the index getter from parent
        local index = self._indexes[index_name]
        if not index then
          error("[Collection] where: Unknown index: " .. index_name)
        end

        local actual_value = index.getter(item)

        -- Handle Signal values
        if type(actual_value) == "table" and actual_value.get then
          actual_value = actual_value:get()
        end

        return actual_value == expected_value
      else -- predicate
        return child._filter_data.predicate(item)
      end
    end

    -- Override adopt to validate and forward to parent
    local child_super_adopt = child.adopt
    function child:adopt(item)
      -- Validate item matches filter
      if not matches_filter(item) then
        error("[Collection] Cannot add item to filtered collection: item does not match filter")
      end

      -- Check if item is already in child
      local in_child = false
      for child_item in child.iter() do
        if child_item == item then
          in_child = true
          break
        end
      end

      if in_child then
        -- Already in child, nothing to do
        return item
      end

      -- Check if item is already in parent
      local in_parent = false
      for parent_item in self._parent_collection.iter() do
        if parent_item == item then
          in_parent = true
          break
        end
      end

      -- If not in parent, add to parent (which will trigger our subscription)
      if not in_parent then
        self._parent_collection:adopt(item)
        return item
      else
        -- Already in parent, just adopt locally
        return child_super_adopt(self, item)
      end
    end

    -- Helper to setup signal watching for an item
    local function setup_signal_watching(item)
      if child._filter_type == "index" then
        local index_name = child._filter_data.index_name
        local index = self._indexes[index_name]
        if index then
          local val = index.getter(item)
          -- Check if it's a Signal that we should watch
          if type(val) == "table" and val.get and val.watch then
            local unsub_signal = val:watch(function(new_value)
              -- Re-evaluate filter for this item
              local should_be_in_child = (new_value == child._filter_data.index_value)

              -- Check if currently in child
              local currently_in_child = false
              local child_index = nil
              for i, child_item in ipairs(child._items) do
                if child_item == item then
                  currently_in_child = true
                  child_index = i
                  break
                end
              end

              if should_be_in_child and not currently_in_child then
                -- Add to child
                child_super_adopt(child, item)
              elseif not should_be_in_child and currently_in_child then
                -- Remove from child
                trace("📤", child._debug_name, "Removing item (signal changed)")
                child:_run_cleanups(item)
                table.remove(child._items, child_index)
                child:_fire_removal(item) -- Notify downstream collections
              end
            end)

            -- Cleanup signal subscription when item is removed
            child:_register_cleanup(item, unsub_signal)
          end
        end
      end
    end

    -- Subscribe to parent additions - add matching items to child
    local unsub_added = self:on_added(function(item)
      if matches_filter(item) then
        -- Check if already in child
        local already_in_child = false
        for child_item in child.iter() do
          if child_item == item then
            already_in_child = true
            break
          end
        end

        if not already_in_child then
          child_super_adopt(child, item)
        end
      end

      -- Setup signal watching for newly added items
      setup_signal_watching(item)
    end)

    -- Subscribe to parent removals - remove from child
    local unsub_removed = self:on_removed(function(item)
      -- Check if item is in child
      for i, child_item in ipairs(child._items) do
        if child_item == item then
          trace("📤", child._debug_name, "Removing item (parent removed)")
          child:_run_cleanups(item)
          table.remove(child._items, i)
          child:_fire_removal(item) -- Notify downstream collections
          break
        end
      end
    end)

    -- Cleanup subscriptions when child is disposed
    child:on_dispose(unsub_added)
    child:on_dispose(unsub_removed)

    -- Initial population: add all matching items from parent
    -- and setup signal watching for each
    for item in self.iter() do
      if matches_filter(item) then
        child_super_adopt(child, item)
      end
      -- Setup signal watching for all parent items (not just matching ones)
      -- so we can detect when they should be added to the child
      setup_signal_watching(item)
    end

    return child
  end

  --- Create a filtered view where items' indexed value matches any item's ID in a source collection
  --- This enables reactive scoping like: frames:where_in("by_stack_id", stacks_collection)
  --- @param index_name string Index name to check on items in this collection
  --- @param source_collection table Source collection to match against (uses item.id)
  --- @param collection_name string? Optional name for the filtered collection
  --- @return table Filtered collection
  function self:where_in(index_name, source_collection, collection_name)
    local child_name = collection_name or (self._debug_name .. ":where_in")
    local child = M.Collection(child_name)
    child._parent_collection = self

    -- Copy indexes from parent
    for idx_name, index_def in pairs(self._indexes) do
      child._indexes[idx_name] = {
        getter = index_def.getter,
        map = {}
      }
    end

    -- Get the index getter
    local index = self._indexes[index_name]
    if not index then
      error("[Collection] where_in: Unknown index: " .. index_name)
    end

    -- Build set of valid IDs from source collection
    local valid_ids = {}
    for source_item in source_collection.iter() do
      if source_item.id then
        valid_ids[source_item.id] = true
      end
    end

    -- Helper: Check if item matches (its indexed value is in valid_ids)
    local function matches(item)
      local val = index.getter(item)
      if type(val) == "table" and val.get then
        val = val:get()
      end
      return valid_ids[val] == true
    end

    -- Helper: Add item to child if not already present
    local child_super_adopt = child.adopt
    local function add_to_child(item)
      for existing in child.iter() do
        if existing == item then return end
      end
      child_super_adopt(child, item)
    end

    -- Helper: Remove item from child
    local function remove_from_child(item)
      for i, child_item in ipairs(child._items) do
        if child_item == item then
          trace("📤", child._debug_name, "Removing item (where_in)")
          child:_run_cleanups(item)
          table.remove(child._items, i)
          child:_fire_removal(item)
          break
        end
      end
    end

    -- Setup signal watching for an item's index value
    local function setup_index_watching(item)
      local val = index.getter(item)
      if type(val) == "table" and val.get and val.watch then
        local unsub = val:watch(function(new_val)
          local should_be_in = valid_ids[new_val] == true
          local is_in = false
          for child_item in child.iter() do
            if child_item == item then
              is_in = true
              break
            end
          end
          if should_be_in and not is_in then
            add_to_child(item)
          elseif not should_be_in and is_in then
            remove_from_child(item)
          end
        end)
        child:_register_cleanup(item, unsub)
      end
    end

    -- When source collection adds an item, add its ID to valid set and re-check all parent items
    local unsub_source_add = source_collection:on_added(function(source_item)
      if source_item.id then
        valid_ids[source_item.id] = true
        -- Check all parent items
        for item in self.iter() do
          if matches(item) then
            add_to_child(item)
          end
        end
      end
    end)

    -- When source collection removes an item, remove its ID from valid set and re-check child items
    local unsub_source_remove = source_collection:on_removed(function(source_item)
      if source_item.id then
        valid_ids[source_item.id] = nil
        -- Check child items, remove those that no longer match
        local to_remove = {}
        for item in child.iter() do
          if not matches(item) then
            table.insert(to_remove, item)
          end
        end
        for _, item in ipairs(to_remove) do
          remove_from_child(item)
        end
      end
    end)

    -- When parent adds an item, add to child if matches
    local unsub_parent_add = self:on_added(function(item)
      if matches(item) then
        add_to_child(item)
      end
      setup_index_watching(item)
    end)

    -- When parent removes an item, remove from child
    local unsub_parent_remove = self:on_removed(function(item)
      remove_from_child(item)
    end)

    -- Cleanup
    child:on_dispose(unsub_source_add)
    child:on_dispose(unsub_source_remove)
    child:on_dispose(unsub_parent_add)
    child:on_dispose(unsub_parent_remove)

    -- Initial population
    for item in self.iter() do
      if matches(item) then
        child_super_adopt(child, item)
      end
      setup_index_watching(item)
    end

    return child
  end

  return self
end

M.Class = require("neostate.class")(M)

return M
