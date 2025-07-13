local Class = require('neodap.tools.class')
local Hookable = require("neodap.transport.hookable")

---@class api.FileSourceBreakpointProps
---@field id string
---@field manager api.BreakpointManager
---@field location api.SourceFileLocation
---@field condition? string
---@field logMessage? string
---@field hookable Hookable

---@class api.FileSourceBreakpoint: api.FileSourceBreakpointProps
---@field new Constructor<api.FileSourceBreakpointProps>
local FileSourceBreakpoint = Class()

---@param manager api.BreakpointManager
---@param location api.SourceFileLocation
---@param opts? { condition?: string, logMessage?: string }
---@return api.FileSourceBreakpoint
function FileSourceBreakpoint.atLocation(manager, location, opts)
  opts = opts or {}
  
  print("BREAKPOINT_LIFECYCLE: Creating breakpoint with location:", location and location.key or "NIL")
  
  local instance = FileSourceBreakpoint:new({
    id = location.key,
    manager = manager,
    location = location,
    condition = opts.condition,
    logMessage = opts.logMessage,
    hookable = Hookable.create(manager.hookable),
  })
  
  print("BREAKPOINT_LIFECYCLE: Created breakpoint", instance.id, "with location:", instance.location and instance.location.key or "NIL")
  
  return instance
end

---@return api.SourceFileLocation
function FileSourceBreakpoint:getLocation()
  print("BREAKPOINT_LIFECYCLE: getLocation() called for breakpoint", self.id, "location:", self.location and self.location.key or "NIL")
  if not self.location then
    print("ERROR: FileSourceBreakpoint:getLocation() - self.location is NIL!")
    print("Breakpoint ID:", self.id)
    print("Stack trace:")
    print(debug.traceback())
  end
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

---@param listener fun(binding: api.FileSourceBinding)
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

---@param listener fun(hit: { thread: api.Thread, body: dap.StoppedEventBody, binding: api.FileSourceBinding })
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

---@return api.BindingCollection
function FileSourceBreakpoint:getBindings()
  -- Delegate to manager - maintain architectural purity
  return self.manager.bindings:forBreakpoint(self)
end

---@param session api.Session
---@return api.FileSourceBinding?
function FileSourceBreakpoint:getBindingForSession(session)
  return self.manager.bindings:forBreakpoint(self):forSession(session):first()
end

---@return api.FileSourceBinding[]
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
  print("BREAKPOINT_LIFECYCLE: Destroying breakpoint", self.id, "location before destroy:", self.location and self.location.key or "NIL")
  self:emit('Removed')
  self.hookable:destroy()
  print("BREAKPOINT_LIFECYCLE: Destroyed breakpoint", self.id, "location after destroy:", self.location and self.location.key or "NIL")
end

return FileSourceBreakpoint