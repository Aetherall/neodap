local BreakpointManagerImpl = require("neodap.plugins.BreakpointApi.BreakpointManager")
local Location = require("neodap.api.Location")

---@class BreakpointApiPlugin
---@field onBreakpoint fun(callback: fun(breakpoint: api.FileSourceBreakpoint)): fun()
---@field onBreakpointRemoved fun(callback: fun(breakpoint: api.FileSourceBreakpoint)): fun()
---@field setBreakpoint fun(location: api.SourceFileLocation): api.FileSourceBreakpoint
---@field removeBreakpoint fun(breakpoint: api.FileSourceBreakpoint)
---@field getBreakpoints fun(): api.BreakpointCollection
---@field getBindings fun(): api.BindingCollection
---@field toggleBreakpoint fun(self: any, location: api.SourceFileLocation): api.FileSourceBreakpoint


local BreakpointApi = {
  name = "BreakpointApi",
  
  ---@param api Api
  ---@return BreakpointApiPlugin
  plugin = function(api)
    local manager = BreakpointManagerImpl.create(api)

    -- No longer modifying BaseSource prototype - use manager directly

    return {
      onBreakpoint = function(callback)
        return manager:onBreakpoint(callback)
      end,

      onBreakpointRemoved = function(callback)
        return manager:onBreakpointRemoved(callback)
      end,

      setBreakpoint = function(location)
        return manager:addBreakpoint(location)
      end,

      removeBreakpoint = function(breakpoint)
        return manager:removeBreakpoint(breakpoint)
      end,

      getBreakpoints = function()
        return manager.breakpoints
      end,

      getBindings = function()
        return manager.bindings
      end,

      toggleBreakpoint = function(self, location) 
        return manager:toggleBreakpoint(location)
      end,
    }
  end,
}

return BreakpointApi