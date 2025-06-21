local Class = require('neodap.tools.class')
local Hookable = require("neodap.transport.hookable")

---@class api.FileSourceBreakpointProps
---@field api Api
---@field manager api.BreakpointManager
---@field id string
---@field hookable Hookable
---@field location api.SourceFileLocation
---@field message? string

---@class api.FileSourceBreakpoint: api.FileSourceBreakpointProps
---@field new Constructor<api.FileSourceBreakpointProps>
local FileSourceBreakpoint = Class()

---@param manager api.BreakpointManager
---@param location api.SourceFileLocation
function FileSourceBreakpoint.atLocation(manager, location)
  return FileSourceBreakpoint:new({
    id = location.key,
    api = manager.api,
    manager = manager,
    message = nil,
    hookable = Hookable.create(),
    location = location,
  })
end

function FileSourceBreakpoint:onBound(listener, opts)
  return self.manager:onBound(function (binding)
    if binding.breakpointId == self.id then
      listener(binding)
    end
  end, opts)
end

---@param listener fun(hit: { thread: api.Thread, body: dap.StoppedEventBody, binding: api.FileSourceBinding })
function FileSourceBreakpoint:onHit(listener, opts)
  return self:onBound(function (binding)
    binding:onHit(function(hit)
      listener({
        thread = hit.thread,
        body = hit.body,
        binding = binding,
      })
    end, opts)
  end, opts)
end

---@param dapBinding dap.Breakpoint
function FileSourceBreakpoint:matches(dapBinding)
  local matchesPath = dapBinding.source and dapBinding.source.path == self.location.path
  local matchesLine = dapBinding.line == self.location.line
  local matchesColumn = dapBinding.column == self.location.column

  return matchesPath and matchesLine and (matchesColumn or not dapBinding.column)
end

return FileSourceBreakpoint
