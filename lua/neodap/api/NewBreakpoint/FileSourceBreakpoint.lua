local Class = require('neodap.tools.class')
local Hookable = require("neodap.transport.hookable")

---@class api.NewFileSourceBreakpointProps
---@field id string
---@field manager api.NewBreakpointManager
---@field location api.NewSourceFileLocation
---@field condition? string
---@field logMessage? string
---@field hookable Hookable

---@class api.NewFileSourceBreakpoint: api.NewFileSourceBreakpointProps
---@field new Constructor<api.NewFileSourceBreakpointProps>
local FileSourceBreakpoint = Class()

---@param manager api.NewBreakpointManager
---@param location api.NewSourceFileLocation
---@param opts? { condition?: string, logMessage?: string }
---@return api.NewFileSourceBreakpoint
function FileSourceBreakpoint.atLocation(manager, location, opts)
  opts = opts or {}
  
  return FileSourceBreakpoint:new({
    id = location.key,
    manager = manager,
    location = location,
    condition = opts.condition,
    logMessage = opts.logMessage,
    hookable = Hookable.create(),
  })
end

---@return api.NewSourceFileLocation
function FileSourceBreakpoint:getLocation()
  return self.location
end

---@param condition? string
function FileSourceBreakpoint:setCondition(condition)
  if self.condition ~= condition then
    self.condition = condition
    self:emit('ConditionChanged', condition)
    -- Trigger resync for all sessions
    self.manager:resyncBreakpoint(self)
  end
end

---@param logMessage? string
function FileSourceBreakpoint:setLogMessage(logMessage)
  if self.logMessage ~= logMessage then
    self.logMessage = logMessage
    self:emit('LogMessageChanged', logMessage)
    -- Trigger resync for all sessions
    self.manager:resyncBreakpoint(self)
  end
end

-- Internal method to emit events
---@param event string
---@param data any
function FileSourceBreakpoint:emit(event, data)
  return self.hookable:emit(event, data)
end

-- API Methods: Hierarchical Event Registration

---@param listener fun(binding: api.NewFileSourceBinding)
---@param opts? HookOptions
---@return fun() unsubscribe
function FileSourceBreakpoint:onBinding(listener, opts)
  -- Register for future bindings
  local unsubscribe1 = self.manager:onBound(function(binding)
    if binding.breakpointId == self.id then
      listener(binding)
    end
  end, opts)
  
  -- Call listener for existing bindings
  for binding in self:getBindings():each() do
    listener(binding)
  end
  
  return unsubscribe1
end

---@param listener fun(hit: { thread: api.Thread, body: dap.StoppedEventBody, binding: api.NewFileSourceBinding })
---@param opts? HookOptions
---@return fun() unsubscribe
function FileSourceBreakpoint:onHit(listener, opts)
  return self:onBinding(function(binding)
    binding:onHit(function(hit)
      listener({
        thread = hit.thread,
        body = hit.body,
        binding = binding,
      })
    end, opts)
  end, opts)
end

---@param listener fun()
---@param opts? HookOptions
---@return fun() unsubscribe
function FileSourceBreakpoint:onRemoved(listener, opts)
  return self.hookable:on('Removed', listener, opts)
end

---@param listener fun(condition: string?)
---@param opts? HookOptions
---@return fun() unsubscribe
function FileSourceBreakpoint:onConditionChanged(listener, opts)
  return self.hookable:on('ConditionChanged', listener, opts)
end

---@param listener fun(logMessage: string?)
---@param opts? HookOptions
---@return fun() unsubscribe
function FileSourceBreakpoint:onLogMessageChanged(listener, opts)
  return self.hookable:on('LogMessageChanged', listener, opts)
end

-- Query Methods (Read-only access to bindings)

---@return api.NewBindingCollection
function FileSourceBreakpoint:getBindings()
  -- Delegate to manager - maintain architectural purity
  return self.manager.bindings:forBreakpoint(self)
end

---@param session api.Session
---@return api.NewFileSourceBinding?
function FileSourceBreakpoint:getBindingForSession(session)
  return self.manager.bindings:forBreakpoint(self):forSession(session):first()
end

---@return api.NewFileSourceBinding[]
function FileSourceBreakpoint:getAllBindings()
  return self:getBindings():toArray()
end

-- Utility Methods

---@param dapBreakpoint dap.Breakpoint
---@return boolean
function FileSourceBreakpoint:matches(dapBreakpoint)
  local matchesPath = dapBreakpoint.source and dapBreakpoint.source.path == self.location.path
  local matchesLine = dapBreakpoint.line == self.location.line
  local matchesColumn = dapBreakpoint.column == self.location.column

  return matchesPath and matchesLine and (matchesColumn or not dapBreakpoint.column)
end

---@return dap.SourceBreakpoint
function FileSourceBreakpoint:toDapBreakpoint()
  return {
    line = self.location.line,
    column = self.location.column,
    condition = self.condition,
    logMessage = self.logMessage,
  }
end

-- Internal lifecycle method (called by manager)
function FileSourceBreakpoint:destroy()
  self:emit('Removed')
  self.hookable:destroy()
end

return FileSourceBreakpoint