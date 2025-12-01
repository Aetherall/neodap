local neostate = require("neostate")

local M = {}

-- =============================================================================
-- EXCEPTION FILTER
-- =============================================================================

---@class ExceptionFilter : Class
---@field debugger Debugger
---@field id string           -- Composite: "{adapter_type}:{filter_id}"
---@field adapter_type string -- "python", "pwa-node", etc.
---@field filter_id string    -- "raised", "uncaught", etc.
---@field label string
---@field description string?
---@field enabled Signal<boolean>
---@field bindings table      -- Filtered view of debugger.exception_filter_bindings
local ExceptionFilter = neostate.Class("ExceptionFilter")

function ExceptionFilter:init(debugger, adapter_type, config)
  self.debugger = debugger
  self.adapter_type = adapter_type
  self.filter_id = config.filter
  self.id = adapter_type .. ":" .. config.filter

  -- URI: dap:filter:<adapter>:<filter_id>
  self.uri = "dap:filter:" .. adapter_type .. ":" .. config.filter
  self.key = self.id
  self._type = "exception_filter"

  self.label = config.label or config.filter
  self.description = config.description

  -- Enabled state (initialized from default or false)
  self.enabled = self:signal(config.default or false, "enabled")

  -- Filtered bindings collection for this exception filter
  self._bindings = debugger.exception_filter_bindings:where(
    "by_filter",
    self.filter_id,
    "ExceptionFilterBindings:Filter:" .. self.id
  )
  self._bindings:set_parent(self)

  -- State tracking: "disabled" | "enabled" | "hit"
  -- Reactively computed from enabled and bindings
  local has_hit = self._bindings:some(function(binding)
    return binding.hit
  end)

  self.state = neostate.Signal("disabled", "state")
  self.state:set_parent(self)

  -- Update state reactively
  local function update_state()
    if has_hit:get() then
      self.state:set("hit")
    elseif self.enabled:get() then
      self.state:set("enabled")
    else
      self.state:set("disabled")
    end
  end

  has_hit:watch(update_state)
  self.enabled:watch(update_state)

  -- When enabled state changes, sync to all bound sessions
  self.enabled:watch(function()
    neostate.void(function()
      for binding in self._bindings:iter() do
        binding.session:_sync_exception_filters_to_dap()
      end
    end)()
  end)
end

---Get filtered bindings for this exception filter
---@return table Filtered collection
function ExceptionFilter:bindings()
  return self._bindings
end

---Register callback for bindings (existing + future)
---@param fn function  -- Called with (binding)
---@return function unsubscribe
function ExceptionFilter:onBinding(fn)
  return self._bindings:each(fn)
end

---Register callback for verified bindings only
---@param fn function  -- Called with (binding)
---@return function unsubscribe
function ExceptionFilter:onVerifiedBinding(fn)
  return self._bindings:each(function(binding)
    return binding.verified:use(function(verified)
      if verified then
        return fn(binding)
      end
    end)
  end)
end

---Register callback for when ANY binding is hit
---@param fn function  -- Called with (binding)
---@return function unsubscribe
function ExceptionFilter:onHit(fn)
  return self._bindings:each(function(binding)
    return binding:onHit(function()
      return fn(binding)
    end)
  end)
end

---Register callback for sessions this filter is bound to
---@param fn function  -- Called with (session)
---@return function unsubscribe
function ExceptionFilter:onSession(fn)
  return self:onBinding(function(binding)
    return fn(binding.session)
  end)
end

M.ExceptionFilter = ExceptionFilter

return M
