local BreakpointManagerImpl = require("neodap.api.Breakpoint.BreakpointManager")
local BaseSource = require("neodap.api.Session.Source.BaseSource")
local Location = require("neodap.api.Breakpoint.Location")

---@class BreakpointManagerAPI
---@field onBreakpoint fun(callback: fun(breakpoint: api.FileSourceBreakpoint)): fun()
---@field onBreakpointRemoved fun(callback: fun(breakpoint: api.FileSourceBreakpoint)): fun()
---@field setBreakpoint fun(location: api.SourceFileLocation): api.FileSourceBreakpoint
---@field removeBreakpoint fun(breakpoint: api.FileSourceBreakpoint)
---@field getBreakpoints fun(): api.BreakpointCollection
---@field getBindings fun(): api.BindingCollection
---@field toggleBreakpoint fun(location: api.SourceFileLocation): api.FileSourceBreakpoint


local BreakpointManager = {
  name = "BreakpointManager",
  
  ---@param api Api
  ---@return BreakpointManagerAPI
  plugin = function(api)
    local manager = BreakpointManagerImpl.create(api)

    
    ---@class (partial) api.BaseSource
    ---@field addBreakpoint fun(self: api.BaseSource, location: api.SourceFileLocation): api.FileSourceBreakpoint

    function BaseSource:addBreakpoint(opts)
      local location = Location.SourceFile.fromSource(self, opts)
      return manager:addBreakpoint(location)
    end
    

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

return BreakpointManager