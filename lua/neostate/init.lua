---@diagnostic disable: invisible
local M = {}

-- =============================================================================
-- 0. TELEMETRY & CONFIGURATION
-- =============================================================================

---@type { trace: boolean, debug_context: boolean, log_fn: function }
local Config = {
  trace = false,
  debug_context = false, -- New flag for file/line info
  log_fn = function(msg) print(msg) end
}

--- Configure the reactor
--- @param opts { trace: boolean, debug_context: boolean, log_fn: function }
function M.setup(opts)
  Config = vim.tbl_extend("force", Config, opts or {})
end

-- Internal: Visual indentation based on stack depth
local _stack_depth = 0
local function get_indent()
  return string.rep("  ", _stack_depth)
end

-- INTROSPECTION ENGINE
-- Walks up the stack to find the first caller that isn't inside reactor.lua
local function get_caller_info()
  if not Config.debug_context then return "" end

  -- Level 3 is usually where the user code starts
  -- (1: get_caller_info, 2: trace, 3: public_api method, 4: user call)
  -- We scan from 3 to 6 to find the relevant frame.
  for i = 3, 6 do
    local info = debug.getinfo(i, "Sln")
    if not info then break end

    -- Simple heuristic: If the source file is NOT this file, it's user code.
    -- We assume this file is named 'reactor.lua'.
    if info.source and not info.source:match("reactor.lua$") then
      local src = info.source:sub(2) -- remove '@'
      -- Shorten path to just filename for cleanliness
      local filename = src:match("^.+/(.+)$") or src
      return string.format(" @%s:%d", filename, info.currentline)
    end
  end
  return ""
end

local function trace(icon, subject, action)
  if not Config.trace then return end
  local context = get_caller_info()

  -- Layout: [Indent][Icon] [Subject] ... [Action] ... [File:Line]
  local info = string.format("%s%s %-18s %-25s %s",
    get_indent(),
    icon,
    "[" .. tostring(subject) .. "]",
    action or "",
    context
  )
  Config.log_fn(info)
end

-- =============================================================================
-- 1. CONTEXT ENGINE
-- =============================================================================

local _active_contexts = setmetatable({}, { __mode = "k" })

local function get_current_context()
  local co = coroutine.running() or "main"
  return _active_contexts[co]
end

-- =============================================================================
-- 2. DISPOSABLE TRAIT
-- =============================================================================

---@class Disposable
---@field _disposed boolean
---@field _disposables function[]
---@field _debug_name string
local Disposable = {}

function Disposable:on_dispose(fn)
  if self._disposed then
    pcall(fn); return
  end
  table.insert(self._disposables, fn)
end

function Disposable:dispose()
  if self._disposed then return end

  trace("🔴", self._debug_name, "Disposing...")
  self._disposed = true

  for i = #self._disposables, 1, -1 do
    local fn = self._disposables[i]
    local ok, err = pcall(fn)
    if not ok then
      vim.notify("[Reactor] Error disposing: " .. tostring(err), vim.log.levels.WARN)
    end
  end
  self._disposables = {}
end

function Disposable:run(fn)
  local co = coroutine.running() or "main"
  local prev = _active_contexts[co]

  _active_contexts[co] = self
  _stack_depth = _stack_depth + 1

  local ok, err = pcall(fn)

  _stack_depth = _stack_depth - 1
  _active_contexts[co] = prev

  if not ok then error(err) end
end

function Disposable:bind(fn)
  return function(...)
    return self:run(function(...) return fn(...) end, ...)
  end
end

--- Mixin: Applies Disposable trait
function M.Component(target, explicit_parent, debug_name)
  target = target or {}

  target._disposed = false
  target._disposables = {}
  target._debug_name = debug_name or "Component"

  target.on_dispose = Disposable.on_dispose
  target.dispose = Disposable.dispose
  target.run = Disposable.run
  target.bind = Disposable.bind

  local parent = explicit_parent or get_current_context()

  if parent then
    if type(parent.on_dispose) == "function" then
      trace("🔗", target._debug_name, "Attached to " .. (parent._debug_name or "Unknown"))
      parent:on_dispose(function() target:dispose() end)
    else
      error("[Reactor] Parent must be a Component")
    end
  else
    trace("🌱", target._debug_name, "Created (Root)")
  end

  return target
end

-- =============================================================================
-- 3. REACTIVE SIGNAL
-- =============================================================================

function M.Signal(initial_value, debug_name)
  debug_name = debug_name or "Signal"
  local self = M.Component({}, nil, debug_name)

  self._val = initial_value
  self._effects = {}

  function self.get() return self._val end

  function self.set(new_val)
    if self._disposed or self._val == new_val then return end

    trace("⚡", self._debug_name, string.format("%s -> %s", tostring(self._val), tostring(new_val)))
    self._val = new_val

    vim.schedule(function()
      if self._disposed then return end
      for _, effect in ipairs(self._effects) do
        if effect.cleanup then pcall(effect.cleanup) end
        local ok, res = pcall(effect.fn, new_val)
        if ok and type(res) == "function" then effect.cleanup = res end
      end
    end)
  end

  function self.use_effect(fn)
    ---@type { fn: function, cleanup: function|nil }
    local effect = { fn = fn, cleanup = nil }
    table.insert(self._effects, effect)

    self:on_dispose(function()
      if effect.cleanup then pcall(effect.cleanup) end
    end)

    -- Initial Trace
    trace("🎣", self._debug_name, "Effect Registered")

    vim.schedule(function()
      if self._disposed then return end
      local ok, res = pcall(fn, self._val)
      if ok and type(res) == "function" then effect.cleanup = res end
    end)
  end

  return self
end

-- =============================================================================
-- 4. OBSERVABLE LIST
-- =============================================================================

function M.List(debug_name)
  debug_name = debug_name or "List"
  local self = M.Component({ _items = {}, _listeners = {} }, nil, debug_name)

  function self.add(data)
    local item_name = debug_name .. ":Item"
    local item = M.Component({ data = data }, self, item_name)

    table.insert(self._items, item)
    trace("📥", self._debug_name, "Added Item. Count: " .. #self._items)

    for _, listener_wrapper in ipairs(self._listeners) do
      listener_wrapper(item)
    end
    return item
  end

  function self.remove(id_check_fn)
    for i, item in ipairs(self._items) do
      if id_check_fn(item.data) then
        trace("📤", self._debug_name, "Removing Item")
        item:dispose()
        table.remove(self._items, i)
        return
      end
    end
  end

  function self.each(fn)
    trace("👀", self._debug_name, "Subscriber Added")

    local listener_wrapper = function(item)
      item:run(function()
        local user_cleanup = fn(item)
        if type(user_cleanup) == "function" then
          item:on_dispose(user_cleanup)
        end
      end)
    end

    table.insert(self._listeners, listener_wrapper)

    for _, item in ipairs(self._items) do
      listener_wrapper(item)
    end

    return function()
      trace("🙈", self._debug_name, "Subscriber Removed")
      for i, l in ipairs(self._listeners) do
        if l == listener_wrapper then
          table.remove(self._listeners, i)
          return
        end
      end
    end
  end

  return self
end

-- =============================================================================
-- 5. ROOT MOUNTER
-- =============================================================================

function M.mount(bufnr, debug_name)
  debug_name = debug_name or ("Root:" .. tostring(bufnr))
  local root = M.Component({}, nil, debug_name)

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

function M.void(fn)
  return function(...)
    local args = { ... }
    coroutine.wrap(function() fn(unpack(args)) end)()
  end
end

return M
