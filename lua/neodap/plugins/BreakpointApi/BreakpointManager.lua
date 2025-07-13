local Class = require('neodap.tools.class')
local nio = require('nio')
local Hookable = require("neodap.transport.hookable")
local FileSourceBreakpoint = require('neodap.plugins.BreakpointApi.FileSourceBreakpoint')
local FileSourceBinding = require('neodap.plugins.BreakpointApi.FileSourceBinding')
local Location = require('neodap.api.Location')
local BreakpointCollection = require("neodap.plugins.BreakpointApi.BreakpointCollection")
local BindingCollection = require("neodap.plugins.BreakpointApi.BindingCollection")
local Logger = require("neodap.tools.logger")

---@class api.BreakpointManagerProps
---@field api Api
---@field breakpoints api.BreakpointCollection
---@field bindings api.BindingCollection
---@field hookable Hookable
---@field pendingOperations table<string, any?>

---@class api.BreakpointManager: api.BreakpointManagerProps
---@field new Constructor<api.BreakpointManagerProps>
local BreakpointManager = Class()

---@param api Api
---@return api.BreakpointManager
function BreakpointManager.create(api)
  local instance = BreakpointManager:new({
    api = api,
    hookable = Hookable.create(api.hookable),
    breakpoints = BreakpointCollection.create(),
    bindings = BindingCollection.create(),
    pendingOperations = {},
  })

  instance:listen()
  return instance
end

-- Core Breakpoint Operations

---@param location api.SourceFilePosition
---@param opts? { condition?: string, logMessage?: string }
---@return api.FileSourceBreakpoint
function BreakpointManager:addBreakpoint(location, opts)
  local log = Logger.get()
  local identifier = location:getSourceIdentifier()
  log:info("BreakpointManager:addBreakpoint called for location:", identifier:toString(), location.line)
  
  -- Check for existing breakpoint
  local existing = self.breakpoints:atLocation(location):first()
  if existing then
    log:info("Breakpoint already exists at location, returning existing:", existing.id)
    return existing
  end

  -- Create new breakpoint (pure user intent)
  local breakpoint = FileSourceBreakpoint.atLocation(self, location, opts)
  self.breakpoints:add(breakpoint)
  
  log:info("Created new breakpoint with ID:", breakpoint.id)
  self.hookable:emit('BreakpointAdded', breakpoint)
  
  -- Queue sync for all active sessions
  for session in self.api:eachSession() do
    local source = session:getSourceByIdentifier(identifier)
    if source then
      self:queueSourceSync(source, session)
    end
  end
  
  return breakpoint
end

---@param breakpoint api.FileSourceBreakpoint
function BreakpointManager:removeBreakpoint(breakpoint)
  local log = Logger.get()
  log:info("BreakpointManager:removeBreakpoint called for:", breakpoint.id)
  
  -- Remove from collection
  self.breakpoints:remove(breakpoint)
  
  -- Remove all bindings for this breakpoint
  local bindingsToRemove = self.bindings:forBreakpoint(breakpoint):toArray()
  for _, binding in ipairs(bindingsToRemove) do
    self.bindings:remove(binding)
    binding:destroy()  -- Binding emits its own 'Unbound' event
  end
  
  -- Queue sync for all affected sessions
  local identifier = breakpoint.location:getSourceIdentifier()
  for session in self.api:eachSession() do
    local source = session:getSourceByIdentifier(identifier)
    if source then
      self:queueSourceSync(source, session)
    end
  end
  
  -- Only breakpoint emits removal event
  breakpoint:destroy()  -- Breakpoint emits its own 'Removed' event
end

---@param location api.SourceFilePosition
---@return api.FileSourceBreakpoint?
function BreakpointManager:toggleBreakpoint(location)
  local existing = self.breakpoints:atLocation(location):first()
  
  if existing then
    self:removeBreakpoint(existing)
    return nil
  else
    return self:addBreakpoint(location)
  end
end

---@param breakpoint api.FileSourceBreakpoint
function BreakpointManager:resyncBreakpoint(breakpoint)
  -- Queue sync for all sessions that have this source
  local identifier = breakpoint.location:getSourceIdentifier()
  for session in self.api:eachSession() do
    local source = session:getSourceByIdentifier(identifier)
    if source then
      self:queueSourceSync(source, session)
    end
  end
end

-- Source Synchronization (Core of Lazy Binding)

---@param source api.FileSource | api.VirtualSource
---@param session api.Session
function BreakpointManager:queueSourceSync(source, session)
  local key = session.id .. ":" .. source:identifier():toString()
  
  if self.pendingOperations[key] then
    return -- Already queued
  end
  
  self.pendingOperations[key] = {
    queued = true,
    cancelled = false,
    startTime = os.time()
  }
  
  nio.run(function()
    nio.sleep(50) -- Batch window
    
    -- Check if cancelled
    if self.pendingOperations[key] and self.pendingOperations[key].cancelled then
      self.pendingOperations[key] = nil
      return
    end
    
    self:syncSourceToSession(source, session)
    self.pendingOperations[key] = nil
  end)
end

---@param source api.FileSource | api.VirtualSource
---@param session api.Session
function BreakpointManager:syncSourceToSession(source, session)
  local log = Logger.get()
  log:info("BreakpointManager:syncSourceToSession - source:", source:identifier():toString(), "session:", session.id)
  
  -- 1. Gather all breakpoints for this source (unified approach)
  local sourceBreakpoints = self.breakpoints:atSource(source:identifier())
  
  -- 2. Get existing bindings to preserve DAP state
  local existingBindings = self.bindings:forSession(session):forSource(source)
  ---@type table<string, api.FileSourceBinding?>
  local bindingsByBreakpointId = {}
  for binding in existingBindings:each() do
    bindingsByBreakpointId[binding.breakpointId] = binding
  end
  
  -- 3. Emit pending event
  self.hookable:emit('SourceSyncPending', {
    source = source,
    session = session,
    breakpoints = sourceBreakpoints:toArray()
  })
  
  -- 4. Build DAP request preserving existing IDs and positions
  local dapBreakpoints = {}
  for breakpoint in sourceBreakpoints:each() do
    local existingBinding = bindingsByBreakpointId[breakpoint.id]
    
    if existingBinding then
      -- Use existing binding's verified position and ID
      local dapBp = existingBinding:toDapSourceBreakpoint()
      table.insert(dapBreakpoints, dapBp)
    else
      -- New breakpoint, use requested position
      local dapBp = breakpoint:toDapBreakpoint()
      table.insert(dapBreakpoints, dapBp)
    end
  end
  
  log:info("Sending", #dapBreakpoints, "breakpoints to DAP for source:", source:identifier():toString())
  
  -- 5. Build DAP source for the request (use source ref directly)
  local dapSource = source.ref
  
  -- 6. Send to DAP (replaces all breakpoints for source)
  local result = session.ref.calls:setBreakpoints({
    source = dapSource,
    breakpoints = dapBreakpoints
  }):wait()
  
  log:debug("DAP returned", #result.breakpoints, "breakpoint responses")
  
  -- 7. Reconcile bindings with response
  self:reconcileBindings(source, session, sourceBreakpoints, result.breakpoints, bindingsByBreakpointId)
  
  -- 8. Emit completion event
  self.hookable:emit('SourceSyncComplete', {
    source = source,
    session = session
  })
end

---@param source api.FileSource | api.VirtualSource
---@param session api.Session
---@param breakpoints api.BreakpointCollection
---@param dapResponses dap.Breakpoint[]
---@param existingBindingsMap table<string, api.FileSourceBinding?>
function BreakpointManager:reconcileBindings(source, session, breakpoints, dapResponses, existingBindingsMap)
  local log = Logger.get()
  local breakpointArray = breakpoints:toArray()
  local processedBindings = {}
  
  -- Match DAP responses to breakpoints by array position
  for i, dapBreakpoint in ipairs(dapResponses) do
    local breakpoint = breakpointArray[i]
    
    if breakpoint and dapBreakpoint.verified then
      local existingBinding = existingBindingsMap[breakpoint.id]
      
      if existingBinding then
        -- Update existing binding
        log:debug("Updating existing binding for breakpoint:", breakpoint.id)
        existingBinding:update(dapBreakpoint)  -- Binding emits its own 'Updated' event
        processedBindings[existingBinding] = true
      else
        -- Create new verified binding
        log:debug("Creating new binding for breakpoint:", breakpoint.id)
        local binding = FileSourceBinding.verified(self, session, source, breakpoint, dapBreakpoint)
        self.bindings:add(binding)
        self.hookable:emit('BindingBound', binding)
        processedBindings[binding] = true
      end
    elseif breakpoint then
      -- DAP rejected this breakpoint
      local existingBinding = existingBindingsMap[breakpoint.id]
      if existingBinding then
        log:debug("Removing rejected binding for breakpoint:", breakpoint.id)
        self.bindings:remove(existingBinding)
        existingBinding:destroy()  -- Binding emits its own 'Unbound' event
      end
      
      -- Emit failure event
      self.hookable:emit('BreakpointFailed', {
        breakpoint = breakpoint,
        session = session,
        error = dapBreakpoint and dapBreakpoint.message or "Verification failed"
      })
    end
  end
  
  -- Remove bindings for breakpoints that no longer exist
  for _, binding in pairs(existingBindingsMap) do
    if not processedBindings[binding] then
      log:debug("Removing stale binding for breakpoint:", binding.breakpointId)
      self.bindings:remove(binding)
      binding:destroy()  -- Binding emits its own 'Unbound' event
    end
  end
end

-- Event Registration API (Hierarchical)

---@param listener fun(breakpoint: api.FileSourceBreakpoint)
---@param opts? HookOptions
---@return fun() unsubscribe
function BreakpointManager:onBreakpoint(listener, opts)
  -- Register for future breakpoints
  local unsubscribe1 = self.hookable:on('BreakpointAdded', listener, opts)
  
  -- Call listener for existing breakpoints
  for breakpoint in self.breakpoints:each() do
    listener(breakpoint)
  end
  
  return unsubscribe1
end

---@param listener fun(binding: api.FileSourceBinding)
---@param opts? HookOptions
---@return fun() unsubscribe
function BreakpointManager:onBound(listener, opts)
  return self.hookable:on('BindingBound', listener, opts)
end


---@param listener fun(event: { source: api.FileSource, session: api.Session, breakpoints: api.FileSourceBreakpoint[] })
---@param opts? HookOptions
---@return fun() unsubscribe
function BreakpointManager:onSourceSyncPending(listener, opts)
  return self.hookable:on('SourceSyncPending', listener, opts)
end

---@param listener fun(event: { source: api.FileSource, session: api.Session })
---@param opts? HookOptions
---@return fun() unsubscribe
function BreakpointManager:onSourceSyncComplete(listener, opts)
  return self.hookable:on('SourceSyncComplete', listener, opts)
end

-- DAP Event Handling

function BreakpointManager:listen()
  local log = Logger.get()
  log:info("BreakpointManager:listen - Starting to listen for DAP events")
  
  self.api:onSession(function(session)
    log:info("BreakpointManager - New session started:", session.id)

    -- When source loads, sync existing breakpoints
    session:onSourceLoaded(function(source)
      log:info("Session", session.id, "- Source loaded:", source:identifier():toString())
      self:queueSourceSync(source, session)
    end)

    -- Handle DAP breakpoint events (should be rare with source-level sync)
    session:onBindingNew(function(dapBinding)
      log:debug("Session", session.id, "- Unexpected DAP binding new event:", dapBinding)
      -- This should rarely happen with proper source-level sync
      -- But we can handle it by triggering a resync
      local location = Location.fromDapBinding(dapBinding)

      if not location then
        log:warn("Session", session.id, "- Could not create location from DAP binding:", dapBinding)
        return
      end

      local sourcefile = location:SourceFile()
      local source = session:getFileSourceAt(sourcefile)
      if source then
        self:queueSourceSync(source, session)
      end
    end)

    -- Handle hit events
    session:onThread(function(thread)
      thread:onStopped(function(body)
        if body.reason ~= 'breakpoint' then
          return
        end
        
        log:info("Session", session.id, "Thread", thread.id, "- Stopped at breakpoint(s):", body.hitBreakpointIds)

        local hitBindings = self.bindings:forSession(session):forIds(body.hitBreakpointIds or {})
        for binding in hitBindings:each() do
          log:debug("Session", session.id, "- Triggering hit for binding:", binding.id)
          binding:triggerHit(thread, body)
          self.hookable:emit('BindingHit', binding)
        end
      end)
    end)

    -- Handle session end
    session:onTerminated(function()
      log:info("Session", session.id, "- Session ended, cleaning up bindings")
      
      -- Cancel pending operations
      for key, operation in pairs(self.pendingOperations) do
        if key:match("^" .. session.id .. ":") then
          operation.cancelled = true
        end
      end
      
      -- Remove all bindings for this session
      local sessionBindings = self.bindings:forSession(session):toArray()
      for _, binding in ipairs(sessionBindings) do
        self.bindings:remove(binding)
        binding:destroy()  -- Binding emits its own 'Unbound' event
      end
    end, { preemptible = false })  -- Must complete cleanup even if session is destroyed
  end)
end


return BreakpointManager