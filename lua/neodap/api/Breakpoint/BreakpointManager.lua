local Class = require('neodap.tools.class')
local nio = require('nio')
local Hookable = require("neodap.transport.hookable")
local FileSourceBreakpoint = require('neodap.api.Breakpoint.FileSourceBreakpoint')
local FileSourceBinding = require('neodap.api.Breakpoint.FileSourceBinding')
local Location = require('neodap.api.Breakpoint.Location')
local BindingCollection = require("neodap.api.Breakpoint.BindingCollection")
local BreakpointCollection = require("neodap.api.Breakpoint.BreakpointCollection")
local Logger = require("neodap.tools.logger")

---@class api.BreakpointManagerProps
---@field api Api
---@field public bindings  api.BindingCollection
---@field public breakpoints api.BreakpointCollection
---@field hookable Hookable

---@class api.BreakpointManager: api.BreakpointManagerProps
---@field new Constructor<api.BreakpointManagerProps>
local BreakpointManager = Class()

---@param api Api
function BreakpointManager.create(api)
  local instance = BreakpointManager:new({
    api = api,
    hookable = Hookable.create(api.hookable), -- Create as child of API's hookable
    bindings = BindingCollection.create(),
    breakpoints = BreakpointCollection.create(),
  })

  instance:listen()
  return instance
end

---@param location api.SourceFileLocation
function BreakpointManager:addBreakpoint(location)
  local log = Logger.get()
  log:info("BreakpointManager:addBreakpoint called for location:", location)
  
  -- Log current state of breakpoint collection
  local all_breakpoints = {}
  for breakpoint in self.breakpoints:each() do
    table.insert(all_breakpoints, breakpoint.id)
  end
  log:debug("Current breakpoints in collection:", vim.inspect(all_breakpoints))
  
  local existing = self.breakpoints:atLocation(location):first()
  if existing then
    log:info("Breakpoint already exists at location, returning existing breakpoint:", existing.id)
    log:debug("Stack trace for duplicate attempt:", debug.traceback())
    return existing;
  end

  local breakpoint = FileSourceBreakpoint.atLocation(self, location)
  self.breakpoints:add(breakpoint)
  log:info("Created new breakpoint with ID:", breakpoint.id, "at", location)
  log:debug("Breakpoint creation stack trace:", debug.traceback())
  
  -- Track how many times this breakpoint has triggered events
  local event_key = "event_count_" .. breakpoint.id
  local current_count = self[event_key] or 0
  current_count = current_count + 1
  self[event_key] = current_count
  
  if current_count > 1 then
    log:warn("EVENT: Breakpoint", breakpoint.id, "has triggered BreakpointAdded event", current_count, "times")
  end
  
  self.hookable:emit('BreakpointAdded', breakpoint)
  log:info("Emitted BreakpointAdded event for breakpoint:", breakpoint.id, "(event #" .. current_count .. ")")
  return breakpoint
end

---@param listener fun(breakpoint: api.FileSourceBreakpoint)
function BreakpointManager:onBreakpointAdded(listener, opts)
  return self.hookable:on('BreakpointAdded', listener, opts)
end

---@param listener fun(breakpoint: api.FileSourceBreakpoint)
function BreakpointManager:onBreakpointRemoved(listener, opts)
  return self.hookable:on('BreakpointRemoved', listener, opts)
end

---@param listener fun(binding: api.FileSourceBinding)
---@param opts? HookOptions
function BreakpointManager:onBound(listener, opts)
  return self.hookable:on('BindingBound', listener, opts)
end

---@param listener fun(binding: api.FileSourceBinding)
---@param opts? HookOptions
function BreakpointManager:onUnbound(listener, opts)
  return self.hookable:on('BindingUnbound', listener, opts)
end

---Toggle a breakpoint at any location (requested or actual), supporting unified interaction
---@param location api.SourceFileLocation
---@return api.FileSourceBreakpoint?
function BreakpointManager:toggleBreakpoint(location)
  local log = Logger.get()
  
  -- Find breakpoint by either requested or actual location
  local existing = self.breakpoints:findByAnyLocation(location, self.bindings)

  if existing then
    log:info("BreakpointManager:toggleBreakpoint - Found existing breakpoint:", existing.id, "removing it")
    
    -- Remove all bindings for this breakpoint
    for binding in self.bindings:forBreakpoint(existing):each() do
      log:info("BreakpointManager:toggleBreakpoint - Removing binding", binding.id, "for session", binding.session.id)
      self.hookable:emit('BindingUnbound', binding)
      self.bindings:remove(binding)
      
      -- Push updated breakpoints to debug adapter
      log:info("BreakpointManager:toggleBreakpoint - Pushing updated breakpoints to debug adapter")
      self.bindings:pushForSource(binding.session, binding.source)
    end
    
    self.breakpoints:remove(existing)
    self.hookable:emit('BreakpointRemoved', existing)
    return nil
  else
    -- Create new breakpoint at the requested location
    
    log:info("BreakpointManager:toggleBreakpoint - Creating new breakpoint at:", location.path, "line", location.line, "col", location.column)
    
    local breakpoint = FileSourceBreakpoint.atLocation(self, location)
    self.breakpoints:add(breakpoint)
    self.hookable:emit('BreakpointAdded', breakpoint)
    return breakpoint
  end
end

---@param location api.SourceFileLocation
function BreakpointManager:ensureBreakpointAt(location)
  local matching = self.breakpoints:atLocation(location):first()
  if matching then
    return matching
  end

  local new = FileSourceBreakpoint.atLocation(self, location)

  self.breakpoints:add(new)
  self.hookable:emit('BreakpointAdded', new):wait()

  return new
end

function BreakpointManager:listen()
  local log = Logger.get()
  log:info("BreakpointManager:listen - Starting to listen for DAP events")
  log:debug("BreakpointManager:listen stack trace:", debug.traceback())
  
  self.api:onSession(function(session)
    log:info("BreakpointManager - New session started:", session.id)
    log:debug("Session creation stack trace:", debug.traceback())

    session:onBindingNew(function(dapBinding)
      local log = Logger.get()
      log:debug("Session", session.id, "- onBindingNew event received:", dapBinding)
      
      -- Lets first check if the binding already exists for this session.
      -- Maybe the adapter is sending a new event after we created the binding manually here.
      -- In that case, we want to update the existing binding with the adapter's data.

      local sessionBindings = self.bindings:forSession(session)

      local binding = sessionBindings:match(dapBinding):first()
      if binding then
        log:debug("Session", session.id, "- Found existing binding, updating with DAP data")
        binding:update(dapBinding)
        -- Emit event to notify UI plugins about the binding update
        self.hookable:emit('BindingBound', binding)
        return
      end

      local location = Location.SourceFile.fromDapBinding(dapBinding)

      if not location then
        log:warn("Session", session.id, "- No valid location from DAP binding, cannot create binding")
        return -- No valid location from DAP binding, cannot create binding
      end
      
      log:debug("Session", session.id, "- Location from DAP binding:", location)

      local breakpoint = self:ensureBreakpointAt(location)
      log:debug("Session", session.id, "- Ensured breakpoint at location, ID:", breakpoint.id)

      local filesource = session:getFileSourceAt(location)
      if not filesource then
        log:warn("Session", session.id, "- No file source found for location:", location)
        return
      end
      log:debug("Session", session.id, "- Found file source:", filesource:identifier())

      local binding = FileSourceBinding.unverified(self, session, filesource, breakpoint)
      if not binding then
        log:error("Session", session.id, "- Failed to create binding")
        return
      end

      self.bindings:add(binding)
      log:info("Session", session.id, "- Created and added binding for breakpoint:", breakpoint.id)
      
      -- Capture buffer snapshot after binding creation
      local path = breakpoint.location.path
      local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(path))
      if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
        -- vim.schedule(function()
          log:snapshot(bufnr, "After binding creation for " .. breakpoint.id)
        -- end)
      end
      
      self.hookable:emit('BindingBound', binding)
      log:debug("Session", session.id, "- Emitted BindingBound event")
    end, { name = "$.S." .. session.id .. ".B.dap.onBreakpointNew" })

    session:onBindingChanged(function(dapBinding)
      -- Lets first check if the binding already exists for this session.
      -- Maybe the adapter is sending a changed event for a binding we already have.

      local sessionBindings = self.bindings:forSession(session)

      local binding = sessionBindings:forIds({dapBinding.id}):first()

      -- local binding = sessionBindings:match(dapBinding):first()
      if binding then
        log:debug("Session", session.id, "- Updating existing binding with changed event")
        binding:update(dapBinding)
        -- Emit event to notify UI plugins about the binding update
        self.hookable:emit('BindingBound', binding)
        return
      end

      -- If we reach here, it means the binding does not exist in our sessionBreakpoints.
      -- But maybe it still has a matching breakpoint in the storage.

      local location = Location.SourceFile.fromDapBinding(dapBinding)
      if not location then
        log:warn("Session", session.id, "- No valid location from DAP binding in changed event")
        return -- No valid location from DAP binding, cannot create binding
      end

      local breakpoint = self:ensureBreakpointAt(location)

      -- If we have a matching breakpoint, we can assume the binding should exist.
      local filesource = session:getFileSourceAt(location)
      if not filesource then
        log:warn("Session", session.id, "- No file source found for location:", location)
        return
      end

      local binding = FileSourceBinding.unverified(self, session, filesource, breakpoint)
      if not binding then
        log:error("Session", session.id, "- Failed to create binding for filesource:", filesource:identifier())
        return
      end

      self.bindings:add(binding)
      self.hookable:emit('BindingBound', binding)
    end, { name = "$.BM." .. session.id .. ".onBreakpointChanged" })

    session:onBindingRemoved(function(body)
      local log = Logger.get()
      log:debug("Session", session.id, "- onBindingRemoved event received:", body)
      
      -- Lets first check if the binding already exists for this session.
      -- Maybe the adapter is sending a removed event for a binding we already have.

      local sessionBreakpoints = self.bindings:forSession(session)

      local binding = sessionBreakpoints:match(body):first()

      if binding then
        log:info("Session", session.id, "- Removing binding for breakpoint:", binding.breakpointId)
        self.bindings:remove(binding)
        self.hookable:emit('BindingUnbound', binding)
      else
        log:warn("Session", session.id, "- No matching binding found to remove")
      end

      -- Now, lets check if the breakpoint should be removed.
      local breakpoint = self.breakpoints:match(body):first()
      if not breakpoint then
        log:debug("Session", session.id, "- No matching breakpoint found, nothing to remove")
        return -- No matching breakpoint found, nothing to remove
      end
    end, { name = "$.BM." .. session.id .. ".onBreakpointRemoved" })

    session:onSourceLoaded(function(source)
      local log = Logger.get()
      local filesource = source:asFile()

      if not filesource then
        return -- Only file sources are supported for now
      end
      
      log:info("Session", session.id, "- Source loaded:", filesource:identifier())

      local breakpoints = self.breakpoints:atSourceId(filesource:identifier())
      local sessionBindings = self.bindings:forSession(session)
      local breakpointCount = 0
      
      for breakpoint in breakpoints:each() do
        breakpointCount = breakpointCount + 1
        local binding = sessionBindings:forBreakpoint(breakpoint):first()
        if not binding then
          -- Create a new binding for this session
          log:debug("Session", session.id, "- Creating binding for existing breakpoint:", breakpoint.id)
          binding = FileSourceBinding.unverified(self, session, filesource, breakpoint)
          self.bindings:add(binding)
          self.hookable:emit('BindingBound', binding)
        else
          log:debug("Session", session.id, "- Binding already exists for breakpoint:", breakpoint.id)
        end
      end
      
      log:info("Session", session.id, "- Found", breakpointCount, "breakpoints for source")

      log:debug("Session", session.id, "- Pushing breakpoints to debug adapter")
      self.bindings:pushForSource(session, filesource)
    end, { name = "$.BM." .. session.id .. ".onSourceLoaded" })

    session:onThread(function(thread)
      thread:onStopped(function(body)
        local log = Logger.get()
        if body.reason ~= 'breakpoint' then
          return
        end
        
        log:info("Session", session.id, "Thread", thread.id, "- Stopped at breakpoint(s):", body.hitBreakpointIds)

        local bindings = self.bindings:forSession(session):forIds(body.hitBreakpointIds or {})
        local hitCount = 0
        for binding in bindings:each() do
          hitCount = hitCount + 1
          log:debug("Session", session.id, "- Triggering hit for binding:", binding.id, "breakpoint:", binding.breakpointId)
          binding:triggerHit(thread, body)
          self.hookable:emit('BindingHit', binding)
          
          -- Capture buffer snapshot after breakpoint hit
          local breakpoint = self.breakpoints:get(binding.breakpointId)
          if breakpoint then
            local path = breakpoint.location.path
            -- vim.schedule(function()
              local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(path))
              if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
                log:snapshot(bufnr, "After breakpoint hit for " .. binding.breakpointId)
              end
            -- end)
          end
        end
        
        if hitCount == 0 then
          log:warn("Session", session.id, "- No bindings found for hit breakpoint IDs:", body.hitBreakpointIds)
        end
      end, { name = "$.BM." .. session.id .. ".T." .. thread.id .. ".onThreadStopped" })
    end, { name = "$.BM." .. session.id .. ".onThread" })
  end)

  self:onBreakpointAdded(function(breakpoint)
    local log = Logger.get()
    log:debug("BreakpointManager - onBreakpointAdded handler triggered for:", breakpoint.id)
    
    nio.sleep(50)
    for session in self.api:eachSession() do
      log:debug("Checking session", session.id, "for breakpoint", breakpoint.id)
      
      local existing = self.bindings:forSession(session):forBreakpoint(breakpoint):first()
      if not existing then
        local filesource = session:getFileSourceAt(breakpoint.location)
        if filesource then
          log:debug("Session", session.id, "- Creating binding for new breakpoint")
          local binding = FileSourceBinding.unverified(self, session, filesource, breakpoint)
          self.bindings:add(binding)
          self.hookable:emit('BindingBound', binding)
          
          log:debug("Session", session.id, "- Pushing updated breakpoints to adapter")
          self.bindings:pushForSource(session, filesource)
        else
          log:debug("Session", session.id, "- No file source found for breakpoint location")
        end
      else
        log:debug("Session", session.id, "- Binding already exists for breakpoint")
      end
    end
  end, { name = "BM.onBreakpointAdded", priority = 25 })
end

return BreakpointManager
