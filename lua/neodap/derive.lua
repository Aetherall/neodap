-- Derived signals for neograph-native
-- Provides reactive computations from multiple sources

local M = {}

-- ============================================================================
-- Deep equality for change detection
-- ============================================================================

local function deep_equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not deep_equal(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

-- ============================================================================
-- Multi-source derived signal
-- ============================================================================

---Create a derived signal from multiple sources
---@param compute fun(): any Function that computes the derived value
---@param subscribe fun(notify: fun()): fun() Function that subscribes to deps, returns unsub
---@return table signal Signal-like object with :get(), :use()
function M.derive(compute, subscribe)
  local current = nil
  local subscribers = {}
  local unsub_deps = nil

  local function notify()
    -- Wrap compute in pcall to handle entity deletion gracefully
    local ok, new_val = pcall(compute)
    if not ok then
      new_val = nil
    end
    -- Deep equality check to avoid spurious updates
    if not deep_equal(new_val, current) then
      current = new_val
      for _, cb in ipairs(subscribers) do
        pcall(cb, current)
      end
    end
  end

  -- Subscribe to dependencies
  unsub_deps = subscribe(notify)

  -- Initial computation
  local ok, initial = pcall(compute)
  current = ok and initial or nil

  local signal = {}

  ---Get current computed value
  function signal:get()
    return current
  end

  ---Subscribe with use() pattern (runs immediately, then on changes)
  ---@param effect fun(value): fun()? Effect function, returns optional cleanup
  ---@return fun() unsub
  function signal:use(effect)
    local cleanup = nil

    local function runCleanup()
      if cleanup then
        pcall(cleanup)
        cleanup = nil
      end
    end

    -- Run effect immediately
    local ok, result = pcall(effect, current)
    if ok and type(result) == "function" then
      cleanup = result
    end

    -- Subscribe to changes
    table.insert(subscribers, function(val)
      runCleanup()
      local ok2, result2 = pcall(effect, val)
      if ok2 and type(result2) == "function" then
        cleanup = result2
      end
    end)

    local cb = subscribers[#subscribers]

    -- Return unsubscribe
    local unsub = function()
      runCleanup()
      for i, c in ipairs(subscribers) do
        if c == cb then
          table.remove(subscribers, i)
          break
        end
      end
    end

    -- Register unsub with current scope for automatic cleanup
    local scoped = require("neodap.scoped")
    local scope = scoped.current()
    if scope then
      scope:onCleanup(unsub)
    end

    return unsub
  end

  ---Clean up all subscriptions
  function signal:cleanup()
    if unsub_deps then
      unsub_deps()
      unsub_deps = nil
    end
    subscribers = {}
  end

  return signal
end

-- ============================================================================
-- Simple derived signal (single source transform)
-- ============================================================================

local DerivedSignal = {}
DerivedSignal.__index = DerivedSignal

---Create a derived signal that transforms a source signal
---@param source table Source signal with :get() and :use()
---@param transform fun(value): any Transform function
---@return table derived
function DerivedSignal.new(source, transform)
  return setmetatable({
    _source = source,
    _transform = transform,
  }, DerivedSignal)
end

function DerivedSignal:get()
  local raw = self._source:get()
  if raw == nil then return nil end
  return self._transform(raw)
end

function DerivedSignal:use(effect)
  local transform = self._transform
  return self._source:use(function(raw)
    local val = raw ~= nil and transform(raw) or nil
    return effect(val)
  end)
end

M.DerivedSignal = DerivedSignal

-- ============================================================================
-- Derived signal from explicit dependencies
-- ============================================================================

---Create a derived signal from explicit dependencies
---Re-computes when any dependency changes
---@param deps table[] Array of signals (with :use() method)
---@param compute fun(): any Function that computes the derived value
---@return table signal Signal-like object with :get(), :use()
function M.from(deps, compute)
  return M.derive(compute, function(notify)
    local unsubs = {}
    for _, dep in ipairs(deps) do
      if dep.use then
        table.insert(unsubs, dep:use(function() notify() end))
      end
    end
    return function()
      for _, unsub in ipairs(unsubs) do
        pcall(unsub)
      end
    end
  end)
end

return M
