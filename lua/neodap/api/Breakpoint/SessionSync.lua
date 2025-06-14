local Class = require('neodap.tools.class')

---@class api.SessionSyncProps
---@field _manager api.BreakpointManager
---@field _session api.Session

---@class api.SessionSync: api.SessionSyncProps
---@field new Constructor<api.SessionSyncProps>
local SessionSync = Class()

---Create a new SessionSync instance
---@param manager api.BreakpointManager
---@param session api.Session
---@return api.SessionSync
function SessionSync.create(manager, session)
  return SessionSync:new({
    _manager = manager,
    _session = session,
  })
end

---Setup DAP event listeners for this session
function SessionSync:listenToDAP()
  self:_handleBreakpointNew()
  self:_handleBreakpointChanged()
  self:_handleBreakpointRemoved()
  self:_setupDAPSync()
end

---Bind existing breakpoints to this session
function SessionSync:bindExistingBreakpoints()
  local allBreakpoints = self._manager._storage:getAll()
  for _, breakpoint in ipairs(allBreakpoints) do
    -- Check if breakpoint needs to be bound to this session
    local binding = breakpoint:binding(self._session)
    if not binding then
      -- This breakpoint might need to be synced to this session
      -- Let DAP sync handle this through normal flow
    end
  end
end

---Sync breakpoints to DAP for a source
---@param breakpoints api.SourceBreakpoint[]
---@param source api.Source
function SessionSync:syncBreakpointsToDAP(breakpoints, source)
  local dapBreakpoints = vim.tbl_map(function(breakpoint)
    return breakpoint:toDapBreakpoint(self._session)
  end, breakpoints)

  return self._session.ref.calls:setBreakpoints({
    source = source.ref,
    breakpoints = dapBreakpoints
  }):wait()
end

-- Private: Handle new breakpoint event
function SessionSync:_handleBreakpointNew()
  return self._session:onBreakpointNew(function(breakpoint)
    local existing = self._manager:find_by_dap(breakpoint)
    local instance, binding = self._manager:_createOrUpdateBreakpoint(self._session, breakpoint)
    if not instance then return end

    -- Only emit BreakpointAdded for truly new breakpoints, not existing ones
    if not existing then
      self._manager.hookable:emit('BreakpointAdded', instance)

      -- IMPORTANT: Emit Bound events AFTER BreakpointAdded to ensure
      -- api:onBreakpoint listeners are registered before bound events fire
      if binding then
        instance.hookable:emit('Bound', binding)
      end
    end
  end, { name = "BreakpointNew-" .. self._session.ref.id })
end

-- Private: Handle changed breakpoint event
function SessionSync:_handleBreakpointChanged()
  return self._session:onBreakpointChanged(function(breakpoint)
    local existing = self._manager:find_by_dap(breakpoint)
    local instance, binding = self._manager:_createOrUpdateBreakpoint(self._session, breakpoint)
    if not instance then return end

    -- Only emit BreakpointAdded for truly new breakpoints, not existing ones
    if not existing then
      self._manager.hookable:emit('BreakpointAdded', instance)

      -- IMPORTANT: Emit Bound events AFTER BreakpointAdded to ensure
      -- api:onBreakpoint listeners are registered before bound events fire
      if binding then
        instance.hookable:emit('Bound', binding)
      end
    end
  end, { name = "BreakpointChanged-" .. self._session.ref.id })
end

-- Private: Handle removed breakpoint event
function SessionSync:_handleBreakpointRemoved()
  return self._session:onBreakpointRemoved(function(breakpoint)
    if not breakpoint.id then return end

    local existing = self._manager:find_by_dap(breakpoint)
    if not existing then return end

    existing:handleBindingRemoved(self._session, breakpoint)

    -- Check if breakpoint has any remaining bindings
    local hasBindings = false
    for _, _ in pairs(existing._bindings) do
      hasBindings = true
      break
    end

    -- If no bindings remain, remove the breakpoint completely
    if not hasBindings then
      self._manager:_removeBreakpointCompletely(existing)
      self._manager.hookable:emit('BreakpointRemoved', existing)
    end
  end, { name = "BreakpointRemoved-" .. self._session.ref.id })
end

-- Private: Setup DAP synchronization for this session
function SessionSync:_setupDAPSync()
  -- Update DAP when breakpoint is added
  self._manager:onBreakpointAdded(function(breakpoint)
    local source = breakpoint:source(self._session)
    if not source then return end

    local breakpoints = self._manager:getSourceBreakpoints(source)
    self:syncBreakpointsToDAP(breakpoints, source)
  end, { name = "BindBreakpointOnAdded-" .. self._session.ref.id })

  -- Update DAP when breakpoint is removed
  self._manager:onBreakpointRemoved(function(breakpoint)
    local binding = breakpoint:binding(self._session)
    if not binding or not binding.source then return end

    local breakpoints = self._manager:getSourceBreakpoints(binding.source)
    self:syncBreakpointsToDAP(breakpoints, binding.source)
  end, { name = "UnbindBreakpointOnRemoved-" .. self._session.ref.id })
end

return SessionSync
