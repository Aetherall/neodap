local Class = require('neodap.tools.class')
local Hookable = require("neodap.transport.hookable")

---@class api.NewFileSourceBindingProps
---@field manager api.NewBreakpointManager
---@field session api.Session
---@field source api.FileSource
---@field breakpointId string
---@field id integer
---@field verified boolean
---@field line integer
---@field column? integer
---@field actualLine integer
---@field actualColumn? integer
---@field message? string
---@field hookable Hookable

---@class api.NewFileSourceBinding: api.NewFileSourceBindingProps
---@field new Constructor<api.NewFileSourceBindingProps>
local FileSourceBinding = Class()

---Create a verified binding from DAP response
---@param manager api.NewBreakpointManager
---@param session api.Session
---@param source api.FileSource
---@param breakpoint api.NewFileSourceBreakpoint
---@param dapBreakpoint dap.Breakpoint
---@return api.NewFileSourceBinding
function FileSourceBinding.verified(manager, session, source, breakpoint, dapBreakpoint)
  return FileSourceBinding:new({
    manager = manager,
    session = session,
    source = source,
    breakpointId = breakpoint.id,
    id = dapBreakpoint.id,
    verified = true, -- Always true in lazy approach
    line = breakpoint.location.line,
    column = breakpoint.location.column,
    actualLine = dapBreakpoint.line,
    actualColumn = dapBreakpoint.column,
    message = dapBreakpoint.message,
    hookable = Hookable.create(),
  })
end

---Update binding from DAP response
---@param dapBreakpoint dap.Breakpoint
function FileSourceBinding:update(dapBreakpoint)
  local changed = false
  
  if self.id ~= dapBreakpoint.id then
    self.id = dapBreakpoint.id
    changed = true
  end
  
  if self.actualLine ~= dapBreakpoint.line then
    self.actualLine = dapBreakpoint.line
    changed = true
  end
  
  if self.actualColumn ~= dapBreakpoint.column then
    self.actualColumn = dapBreakpoint.column
    changed = true
  end
  
  if self.message ~= dapBreakpoint.message then
    self.message = dapBreakpoint.message
    changed = true
  end
  
  if changed then
    self:emit('Updated', dapBreakpoint)
  end
end

-- Internal method to emit events
---@param event string
---@param data any
function FileSourceBinding:emit(event, data)
  return self.hookable:emit(event, data)
end

-- API Methods: Event Registration

---@param listener fun(hit: { thread: api.Thread, body: dap.StoppedEventBody })
---@param opts? HookOptions
---@return fun() unsubscribe
function FileSourceBinding:onHit(listener, opts)
  return self.hookable:on('Hit', listener, opts)
end

---@param listener fun(dapBreakpoint: dap.Breakpoint)
---@param opts? HookOptions
---@return fun() unsubscribe
function FileSourceBinding:onUpdated(listener, opts)
  return self.hookable:on('Updated', listener, opts)
end

---@param listener fun()
---@param opts? HookOptions
---@return fun() unsubscribe
function FileSourceBinding:onUnbound(listener, opts)
  return self.hookable:on('Unbound', listener, opts)
end

-- Query Methods

---@return api.NewFileSourceBreakpoint?
function FileSourceBinding:getBreakpoint()
  return self.manager.breakpoints:get(self.breakpointId)
end

---@return api.NewSourceFileLocation
function FileSourceBinding:getActualLocation()
  local Location = require('neodap.api.NewBreakpoint.Location')
  return Location.SourceFile.fromSource(self.source, {
    line = self.actualLine,
    column = self.actualColumn,
  })
end

---@return api.NewSourceFileLocation
function FileSourceBinding:getRequestedLocation()
  local Location = require('neodap.api.NewBreakpoint.Location')
  return Location.SourceFile.fromSource(self.source, {
    line = self.line,
    column = self.column,
  })
end

---@return boolean
function FileSourceBinding:wasMoved()
  return self.actualLine ~= self.line or self.actualColumn ~= self.column
end

-- Utility Methods

---@return dap.SourceBreakpoint
function FileSourceBinding:toDapSourceBreakpoint()
  local breakpoint = self:getBreakpoint()
  return {
    line = self.actualLine,
    column = self.actualColumn or 0,
    condition = breakpoint and breakpoint.condition,
    logMessage = breakpoint and breakpoint.logMessage,
  }
end

---@return dap.SourceBreakpoint
function FileSourceBinding:toDapSourceBreakpointWithId()
  local dapBreakpoint = self:toDapSourceBreakpoint()
  dapBreakpoint.id = self.id
  return dapBreakpoint
end

---@param dapBinding dap.Breakpoint
---@return boolean
function FileSourceBinding:matches(dapBinding)
  -- Match by DAP ID if available
  if self.id and dapBinding.id then
    return self.id == dapBinding.id
  end
  
  -- Fallback to location matching
  local matchesPath = dapBinding.source and dapBinding.source.path == self.source:absolutePath()
  local matchesLine = dapBinding.line == self.actualLine or dapBinding.line == self.line
  local matchesColumn = dapBinding.column == self.actualColumn or dapBinding.column == self.column

  return matchesPath and matchesLine and (matchesColumn or not dapBinding.column)
end

-- Hit handling (called by manager)
---@param thread api.Thread
---@param body dap.StoppedEventBody
function FileSourceBinding:triggerHit(thread, body)
  self:emit('Hit', {
    thread = thread,
    body = body,
  })
end

-- Internal lifecycle method (called by manager)
function FileSourceBinding:destroy()
  self:emit('Unbound')
  self.hookable:destroy()
end

return FileSourceBinding