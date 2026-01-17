-- Scoped reactivity for neograph-native
--
-- Provides automatic scope management by overwriting signal/edge methods:
-- - :use() subscriptions auto-register with current scope
-- - :each() creates child scope per item
-- - When scope cancels, all descendants cancel
--
-- Usage:
--   local scoped = require("neodap.scoped")
--   scoped.install(graph)  -- patches graph's signals/edges
--
-- Then use signals/edges normally - scopes are implicit.

local M = {}

-- =============================================================================
-- Scope implementation
-- =============================================================================

local Scope = {}
Scope.__index = Scope

function Scope.new(parent)
  local self = setmetatable({
    parent = parent,
    children = setmetatable({}, { __mode = "v" }), -- weak refs
    cleanups = {},
    cancelled = false,
  }, Scope)

  if parent then
    table.insert(parent.children, self)
  end

  return self
end

function Scope:onCleanup(fn)
  if self.cancelled then
    pcall(fn)
    return
  end
  table.insert(self.cleanups, fn)
end

---Check if scope is done (for async.Context compatibility)
---@return boolean
function Scope:done()
  if self.cancelled then return true end
  if self.parent then return self.parent:done() end
  return false
end

function Scope:cancel()
  if self.cancelled then return end
  self.cancelled = true

  -- Cancel children first (depth-first)
  for _, child in ipairs(self.children) do
    child:cancel()
  end
  self.children = {}

  -- Run cleanups in reverse order
  for i = #self.cleanups, 1, -1 do
    pcall(self.cleanups[i])
  end
  self.cleanups = {}
end

M.Scope = Scope

-- =============================================================================
-- Scope stack (current scope tracking)
-- =============================================================================

local scope_stack = {}
local root_scope = Scope.new(nil)
table.insert(scope_stack, root_scope)

function M.current()
  return scope_stack[#scope_stack]
end

function M.push(parent)
  local scope = Scope.new(parent or M.current())
  table.insert(scope_stack, scope)
  return scope
end

function M.pop()
  if #scope_stack > 1 then
    return table.remove(scope_stack)
  end
  return nil
end

function M.root()
  return root_scope
end

-- Run function within a new child scope
function M.scoped(fn)
  local scope = M.push()
  local ok, result = pcall(fn)
  M.pop()
  if not ok then error(result, 0) end
  return result, scope
end

---Run function in a specific scope
---@param scope table
---@param fn function
function M.withScope(scope, fn)
  table.insert(scope_stack, scope)
  local ok, result = pcall(fn)
  table.remove(scope_stack)
  if not ok then error(result, 0) end
  return result
end

---Create a new child scope (for plugins)
---@param parent? table Parent scope (defaults to root)
---@return table scope
function M.createScope(parent)
  return Scope.new(parent or M.root())
end

-- =============================================================================
-- Graph patching - overwrite signal/edge methods
-- =============================================================================

-- Track which graphs have been patched
local patched_graphs = setmetatable({}, { __mode = "k" })

-- Track current effect's nested unsubs (for auto-cleanup on re-run)
local effect_unsubs_stack = {}

local function current_effect_unsubs()
  return effect_unsubs_stack[#effect_unsubs_stack]
end

-- Patch a signal's :use() method to auto-register with scope
-- Nested :use() calls are auto-cleaned when outer effect re-runs
local function patch_signal(signal)
  if rawget(signal, "_scoped_patched") then return signal end

  local original_use = signal.use

  function signal:use(effect)
    local scope = M.current()
    local nested_unsubs = {} -- Track unsubs created during this effect
    local user_cleanup = nil

    local function run_nested_cleanup()
      for i = #nested_unsubs, 1, -1 do
        pcall(nested_unsubs[i])
      end
      nested_unsubs = {}
    end

    local function wrapped_effect(value)
      -- Clean up previous nested subscriptions
      run_nested_cleanup()
      if user_cleanup then
        pcall(user_cleanup)
        user_cleanup = nil
      end

      -- Push our unsubs collector so nested :use() calls register with us
      table.insert(effect_unsubs_stack, nested_unsubs)
      local ok, result = pcall(effect, value)
      table.remove(effect_unsubs_stack)

      if ok and type(result) == "function" then
        user_cleanup = result
      elseif not ok then
        error(result, 0)
      end
    end

    local unsub = original_use(self, wrapped_effect)

    -- Register with current scope
    if scope then
      scope:onCleanup(function()
        run_nested_cleanup()
        if user_cleanup then pcall(user_cleanup) end
        unsub()
      end)
    end

    -- Also register with parent effect if we're nested
    local parent_unsubs = current_effect_unsubs()
    if parent_unsubs then
      table.insert(parent_unsubs, function()
        run_nested_cleanup()
        if user_cleanup then pcall(user_cleanup) end
        unsub()
      end)
    end

    return unsub
  end

  rawset(signal, "_scoped_patched", true)
  return signal
end

-- Patch an edge's :each() method to create per-item scopes
local function patch_edge(edge)
  if rawget(edge, "_scoped_patched") then return edge end

  local original_each = edge.each

  function edge:each(onItem)
    local item_scopes = {} -- item id -> scope
    local parent = M.current()

    local unsub = original_each(self, function(item)
      local item_id = item._id or tostring(item)

      -- Create child scope for this item
      local item_scope = Scope.new(parent)
      item_scopes[item_id] = item_scope

      -- Run effect in item's scope
      table.insert(scope_stack, item_scope)
      local ok, user_cleanup = pcall(onItem, item)
      table.remove(scope_stack)

      if ok and type(user_cleanup) == "function" then
        item_scope:onCleanup(user_cleanup)
      end

      -- Return cleanup that cancels item's scope
      return function()
        local scope = item_scopes[item_id]
        if scope then
          item_scopes[item_id] = nil
          scope:cancel()
        end
      end
    end)

    -- Register unsub with current scope
    if parent then
      parent:onCleanup(function()
        unsub()
        -- Cancel all remaining item scopes
        for _, item_scope in pairs(item_scopes) do
          item_scope:cancel()
        end
        item_scopes = {}
      end)
    end

    return unsub
  end

  rawset(edge, "_scoped_patched", true)
  return edge
end

-- Hook into graph to patch signals/edges as they're accessed
local function install_on_graph(graph)
  if patched_graphs[graph] then return graph end

  local original_insert = graph.insert

  -- Patch insert to patch signals/edges on new entities
  function graph:insert(type_name, props)
    local entity = original_insert(self, type_name, props)
    return patch_entity(entity)
  end

  -- Patch get to patch returned entities
  local original_get = graph.get
  function graph:get(id)
    local entity = original_get(self, id)
    if entity then
      return patch_entity(entity)
    end
    return entity
  end

  patched_graphs[graph] = true
  return graph
end

-- Patch an entity's signal/edge properties
function patch_entity(entity)
  if rawget(entity, "_scoped_patched") then return entity end

  -- We need to patch signals and edges lazily as they're accessed
  -- Use __index hooking on the entity's metatable

  local mt = getmetatable(entity)
  if not mt then
    rawset(entity, "_scoped_patched", true)
    return entity
  end

  local original_index = mt.__index

  -- Create new metatable that wraps __index
  local new_mt = {}
  for k, v in pairs(mt) do
    new_mt[k] = v
  end

  new_mt.__index = function(self, key)
    -- Get value from original
    local value
    if type(original_index) == "function" then
      value = original_index(self, key)
    elseif type(original_index) == "table" then
      value = original_index[key]
    else
      value = nil
    end

    -- If it's a signal or edge, patch it
    if value ~= nil and type(value) == "table" then
      if value.use and value.get and not rawget(value, "_scoped_patched") then
        -- Looks like a signal
        patch_signal(value)
      elseif value.each and value.iter and not rawget(value, "_scoped_patched") then
        -- Looks like an edge
        patch_edge(value)
      end
    end

    return value
  end

  setmetatable(entity, new_mt)
  rawset(entity, "_scoped_patched", true)
  return entity
end

-- =============================================================================
-- flatMap: Signal transformation
-- =============================================================================

---Create a signal that switches to watching whatever signal the transform returns
---When source changes, disposes old inner signal and subscribes to new one
---Works with neograph-native signals that have :get() and :use() methods
---@param source table Source signal
---@param transform function(value): Signal|nil Function that returns a signal to watch
---@return table FlatMappedSignal
function M.flatMap(source, transform)
  local inner = nil
  local inner_unsub = nil
  local listeners = {}
  local next_id = 1

  local function get_inner()
    local value = source:get()
    return value ~= nil and transform(value) or nil
  end

  local function notify(value)
    for _, cb in pairs(listeners) do
      pcall(cb, value)
    end
  end

  local function subscribe_inner()
    if inner_unsub then
      pcall(inner_unsub); inner_unsub = nil
    end
    -- Dispose old inner signal to prevent use-after-free crashes
    if inner and inner.dispose then pcall(inner.dispose, inner) end
    inner = get_inner()
    if inner and inner.use then
      -- neograph-native signals use :use() not :onChange()
      inner_unsub = inner:use(function(value)
        notify(value)
      end)
    end
  end

  -- Initial subscription
  subscribe_inner()

  -- Subscribe to source changes using :use()
  local source_unsub = source:use(function()
    subscribe_inner()
    local value = inner and inner:get() or nil
    notify(value)
  end)

  local flat = {}

  function flat:get()
    return inner and inner:get() or nil
  end

  function flat:use(effect)
    local cleanup = nil

    local function runCleanup()
      if cleanup then
        pcall(cleanup); cleanup = nil
      end
    end

    local function runEffect(value)
      runCleanup()
      local ok, result = pcall(effect, value)
      if ok and type(result) == "function" then cleanup = result end
    end

    runEffect(self:get())
    local id = next_id
    next_id = next_id + 1
    listeners[id] = runEffect

    return function()
      runCleanup()
      listeners[id] = nil
    end
  end

  function flat:dispose()
    if inner_unsub then
      pcall(inner_unsub); inner_unsub = nil
    end
    if inner and inner.dispose then pcall(inner.dispose, inner) end
    if source_unsub then
      pcall(source_unsub); source_unsub = nil
    end
    inner = nil
    listeners = {}
  end

  return flat
end

-- =============================================================================
-- Public API
-- =============================================================================

---Install scoped reactivity on a neograph-native graph
---@param graph table The neograph-native graph
---@return table graph The same graph (mutated)
function M.install(graph)
  return install_on_graph(graph)
end

-- Alias for backward compatibility
M.wrap = M.install

return M
