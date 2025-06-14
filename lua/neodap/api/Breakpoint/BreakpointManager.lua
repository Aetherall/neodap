local Class = require('neodap.tools.class')
local Hookable = require("neodap.transport.hookable")
local SourceBreakpoint = require('neodap.api.Breakpoint.SourceBreakpoint')
local BreakpointStorage = require('neodap.api.Breakpoint.BreakpointStorage')
local SessionSync = require('neodap.api.Breakpoint.SessionSync')

---@class api.BreakpointManagerProps
---@field api Api
---@field _storage api.BreakpointStorage
---@field _sessionSyncs table<string, api.SessionSync>
---@field hookable Hookable

---@class api.BreakpointManager: api.BreakpointManagerProps
---@field new Constructor<api.BreakpointManagerProps>
local BreakpointManager = Class()

---@param api Api
function BreakpointManager.create(api)
  local instance = BreakpointManager:new({
    api = api,
    hookable = Hookable.create(),
    _storage = BreakpointStorage.create(),
    _sessionSyncs = {},
  })

  instance:listen()
  return instance
end

---@param dapBreakpoint dap.Breakpoint
---@return api.SourceBreakpoint?
function BreakpointManager:find_by_dap(dapBreakpoint)
  local id = SourceBreakpoint.getUniqueId(dapBreakpoint)
  return id and self._storage:getById(id)
end

-- Private: Create or update breakpoint instance
---@param session api.Session
---@param dapBreakpoint dap.Breakpoint
---@return api.SourceBreakpoint?, api.SimpleBinding?
function BreakpointManager:_createOrUpdateBreakpoint(session, dapBreakpoint)
  if not dapBreakpoint.id then return nil, nil end

  local existing = self:find_by_dap(dapBreakpoint)

  if existing then
    local binding = existing:handleBindingChanged(session, dapBreakpoint)
    return existing, binding
  end

  if not dapBreakpoint.source or not dapBreakpoint.line or not dapBreakpoint.source.path then
    return nil, nil -- Invalid breakpoint data
  end

  local instance = SourceBreakpoint.create(self.api, {
    path = dapBreakpoint.source.path,
    line = dapBreakpoint.line or 0,
    column = dapBreakpoint.column or 0,
  })

  self._storage:add(instance)
  local binding = instance:handleBindingNew(session, dapBreakpoint)

  return instance, binding
end

-- Main event listener setup (simplified with SessionSync)
function BreakpointManager:listen()
  self.api:onSession(function(session)
    -- Create SessionSync instance for this session
    local sessionSync = SessionSync.create(self, session)

    -- Store session sync (simple assignment)
    rawset(self._sessionSyncs, session.ref.id, sessionSync)

    -- Setup DAP event handling through SessionSync
    sessionSync:listenToDAP()
    sessionSync:bindExistingBreakpoints()
  end)
end

---@param breakpoint api.SourceBreakpoint
function BreakpointManager:_removeBreakpointCompletely(breakpoint)
  -- Remove from storage (no more dual storage to maintain)
  self._storage:remove(breakpoint)
end

---@param source api.Source
---@return api.SourceBreakpoint[]
function BreakpointManager:getSourceBreakpoints(source)
  local id = source:identifier()
  if not id then return {} end

  return self._storage:getBySourceId(id)
end

---@param session api.Session
---@param source api.Source
function BreakpointManager:pushSessionSourceBreakpoints(session, source)
  local breakpoints = self:getSourceBreakpoints(source)
  if #breakpoints == 0 then
    -- Clear existing breakpoints for this source
    local nio = require("nio")
    nio.run(function()
      session.ref.calls:setBreakpoints({
        source = source.ref,
        breakpoints = {}
      }):wait()
    end)
    return
  end

  local dapBreakpoints = {}
  for _, breakpoint in ipairs(breakpoints) do
    local dapBp = breakpoint:toDapBreakpoint(session)
    if dapBp then
      table.insert(dapBreakpoints, dapBp)
    end
  end

  local nio = require("nio")
  nio.run(function()
    session.ref.calls:setBreakpoints({
      source = source.ref,
      breakpoints = dapBreakpoints
    }):wait()
  end)
end

---@param session api.Session The session initiating the breakpoint changes
---@param source api.Source
---@param sourceBreakpoints dap.SourceBreakpoint[]
function BreakpointManager:setSourceBreakpoints(session, source, sourceBreakpoints)
  if not source:isFile() then
    return
  end

  -- Clear existing breakpoints for this source
  local existing = self:getSourceBreakpoints(source)
  for _, bp in ipairs(existing) do
    self._storage:remove(bp.id)
  end

  -- Create internal breakpoints directly from source breakpoints
  local createdBreakpoints = {}
  for _, sourceBp in ipairs(sourceBreakpoints) do
    -- Create breakpoint instance
    local breakpoint = SourceBreakpoint.create(self.api, {
      path = source:absolutePath(),
      line = sourceBp.line or 0,
      column = sourceBp.column or 0,
    })
    self._storage:add(breakpoint)
    local binding = breakpoint:bind(session, source)

    -- Store for later bound event emission
    table.insert(createdBreakpoints, { breakpoint = breakpoint, binding = binding })

    -- Emit the BreakpointAdded event for API-created breakpoints
    self.hookable:emit('BreakpointAdded', breakpoint)
  end

  -- Now emit Bound events AFTER all BreakpointAdded events
  for _, item in ipairs(createdBreakpoints) do
    if item.binding then
      item.breakpoint.hookable:emit('Bound', item.binding)
    end
  end


  local sourceId = source:identifier()
  if not sourceId then
    return -- Can't sync unidentifiable sources
  end

  for otherSession in self.api:eachSession() do
    if otherSession.ref.id ~= session.ref.id then
      local sessionSource = self:_findSessionSource(otherSession, sourceId)
      if sessionSource then
        -- For each breakpoint that exists for this source, create bindings for this session
        local sourceBreakpoints = self:getSourceBreakpoints(sessionSource)
        for _, breakpoint in ipairs(sourceBreakpoints) do
          breakpoint:bind(otherSession, sessionSource)
        end

        -- Now sync breakpoints to this session's version of the source
        self:pushSessionSourceBreakpoints(otherSession, sessionSource)
      end
    end
  end

  return self:getSourceBreakpoints(source)
end

-- PRIVATE: Find a source in a session by identifier
---@param session api.Session
---@param sourceId string
---@return api.Source?
function BreakpointManager:_findSessionSource(session, sourceId)
  -- Check session sources by path/identifier matching
  -- Sources are stored in session._sources table
  if not session._sources then
    return nil
  end

  for _, sessionSource in pairs(session._sources) do
    if sessionSource:identifier() == sourceId then
      return sessionSource
    end
  end
  return nil
end

---@param listener fun(breakpoint: api.SourceBreakpoint)
function BreakpointManager:onBreakpointAdded(listener, opts)
  return self.hookable:on('BreakpointAdded', listener, opts)
end

---@param listener fun(breakpoint: api.SourceBreakpoint)
function BreakpointManager:onBreakpointRemoved(listener, opts)
  return self.hookable:on('BreakpointRemoved', listener, opts)
end

return BreakpointManager
