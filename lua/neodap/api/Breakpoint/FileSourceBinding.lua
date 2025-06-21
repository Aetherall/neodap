local Class = require('neodap.tools.class')
local Hookable = require("neodap.transport.hookable")

---@class api.FileSourceBindingProps
---@field manager api.BreakpointManager
---@field session api.Session
---@field source api.FileSource
---@field breakpointId string
---@field id integer?
---@field verified boolean
---@field line integer
---@field column? integer
---@field actualLine? integer
---@field actualColumn? integer
---@field message? string
---@field ref table -- Compatibility property for existing tests
---@field hookable Hookable

---@class api.FileSourceBinding: api.FileSourceBindingProps
---@field new Constructor<api.FileSourceBindingProps>
local FileSourceBinding = Class()

---@param manager api.BreakpointManager
---@param session api.Session
---@param source api.FileSource
---@param breakpoint api.FileSourceBreakpoint
---@return api.FileSourceBinding
function FileSourceBinding.unverified(manager, session, source, breakpoint)
  return FileSourceBinding:new({
    breakpointId = breakpoint.id,
    manager = manager,
    session = session,
    source = source,
    verified = false,
    line = breakpoint.location.line,
    column = breakpoint.location.column,
    message = breakpoint.message,
    ref = breakpoint, -- Use the original breakpoint as ref
    hookable = Hookable.create()
  })
end

---Update binding from DAP breakpoint response
---@param dapBreakpoint dap.Breakpoint
function FileSourceBinding:update(dapBreakpoint)
  self.id = dapBreakpoint.id
  self.verified = dapBreakpoint.verified
  self.actualLine = dapBreakpoint.line
  self.actualColumn = dapBreakpoint.column
  self.message = dapBreakpoint.message

  -- Update compatibility ref object
  self.ref = dapBreakpoint
end

function FileSourceBinding:onUnbound(listener, opts)
  return self.manager:onUnbound(listener, opts)
end

---Listen for hit events on this binding
---@param listener fun(hit: { thread: api.Thread, body: dap.StoppedEventBody })
---@param opts? HookOptions
function FileSourceBinding:onHit(listener, opts)
  -- Register the listener for future hit events
  return self.hookable:on('Hit', listener, opts)
end

---@param thread api.Thread
---@param body dap.StoppedEventBody
function FileSourceBinding:triggerHit(thread, body)
  return self.hookable:emit('Hit', {
    thread = thread,
    body = body,
  })
end


---@return dap.SourceBreakpoint
function FileSourceBinding:toDapSourceBreakpoint()
  return {
    source = self.source.ref,
    line = self.actualLine or self.line,
    column = self.actualColumn or self.column or 0,
  }
end


function FileSourceBinding:matches(dapBinding)
  local matchesPath = dapBinding.source and dapBinding.source.path == self.source:absolutePath()
  local matchesLine = dapBinding.line == self.actualLine or dapBinding.line == self.line
  local matchesColumn = dapBinding.column == self.actualColumn or dapBinding.column == self.column

  return matchesPath and matchesLine and (matchesColumn or not dapBinding.column)
end


return FileSourceBinding
