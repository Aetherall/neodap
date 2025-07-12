local Class = require('neodap.tools.class')
local Hookable = require("neodap.transport.hookable")
local Location = require("neodap.api.Breakpoint.Location")

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
  local Logger = require("neodap.tools.logger")
  local log = Logger.get()
  
  log:info("FileSourceBinding.unverified - Creating binding for breakpoint:", breakpoint.id)
  log:debug("Binding details - session:", session.id, "source:", source:identifier(), "line:", breakpoint.location.line, "column:", breakpoint.location.column)
  
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
  local Logger = require("neodap.tools.logger")
  local log = Logger.get()
  
  log:info("FileSourceBinding:update - Updating binding for breakpoint:", self.breakpointId)
  log:debug("Update details - DAP ID:", dapBreakpoint.id, "verified:", dapBreakpoint.verified, "actual line:", dapBreakpoint.line, "actual column:", dapBreakpoint.column)
  
  if self.line ~= dapBreakpoint.line or self.column ~= dapBreakpoint.column then
    log:warn("Binding location mismatch - requested:", self.line, self.column, "actual:", dapBreakpoint.line, dapBreakpoint.column)
  end
  
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

function FileSourceBinding:location()
  return Location.SourceFile.fromSource(self.source, {
    line = self.actualLine or self.line,
    column = self.actualColumn or self.column,
  })
end


function FileSourceBinding:matches(dapBinding)
  local matchesPath = dapBinding.source and dapBinding.source.path == self.source:absolutePath()
  local matchesLine = dapBinding.line == self.actualLine or dapBinding.line == self.line
  local matchesColumn = dapBinding.column == self.actualColumn or dapBinding.column == self.column

  return matchesPath and matchesLine and (matchesColumn or not dapBinding.column)
end


return FileSourceBinding
