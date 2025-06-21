local Class = require('neodap.tools.class')
local nio = require('nio')
local Hookable = require("neodap.transport.hookable")
local FileSourceBreakpoint = require('neodap.api.Breakpoint.FileSourceBreakpoint')
local FileSourceBinding = require('neodap.api.Breakpoint.FileSourceBinding')
local Location = require('neodap.api.Breakpoint.Location')
local BindingCollection = require("neodap.api.Breakpoint.BindingCollection")
local BreakpointCollection = require("neodap.api.Breakpoint.BreakpointCollection")

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
    hookable = Hookable.create(),
    bindings = BindingCollection.create(),
    breakpoints = BreakpointCollection.create(),
  })

  instance:listen()
  return instance
end

---@param location api.SourceFileLocation
function BreakpointManager:addBreakpoint(location)
  local existing = self.breakpoints:atLocation(location):first()
  if existing then
    return existing;
  end

  local breakpoint = FileSourceBreakpoint.atLocation(self, location)
  self.breakpoints:add(breakpoint)
  self.hookable:emit('BreakpointAdded', breakpoint)
  return breakpoint
end

---@param location api.SourceFileLocation
function BreakpointManager:toggleBreakpoint(location)
  local existing = self.breakpoints:atLocation(location):first()
  if existing then
    for binding in self.bindings:forBreakpoint(existing):each() do
      self.hookable:emit('BindingUnbound', binding)
      self.bindings:remove(binding)

      self.bindings:forSession(binding.session):forSource(binding.source):push()
    end

    self.breakpoints:remove(existing)
    self.hookable:emit('BreakpointRemoved', existing)
    return nil
  end

  local breakpoint = FileSourceBreakpoint.atLocation(self, location)
  self.breakpoints:add(breakpoint)
  self.hookable:emit('BreakpointAdded', breakpoint)
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
  -- print("BM Listening for DAP events to manage breakpoints and bindings...")
  self.api:onSession(function(session)
    -- print("BM New session started: " .. session.id)

    session:onBindingNew(function(dapBinding)
      -- Lets first check if the binding already exists for this session.
      -- Maybe the adapter is sending a new event after we created the binding manually here.
      -- In that case, we want to update the existing binding with the adapter's data.

      local sessionBindings = self.bindings:forSession(session)

      local binding = sessionBindings:match(dapBinding):first()
      if binding then
        binding:update(dapBinding)
        return
      end

      local location = Location.SourceFile.fromDapBinding(dapBinding)

      if not location then
        return -- No valid location from DAP binding, cannot create binding
      end

      local breakpoint = self:ensureBreakpointAt(location)

      local filesource = session:getFileSourceAt(location)
      if not filesource then
        return
      end

      local binding = FileSourceBinding.unverified(self, session, filesource, breakpoint)
      if not binding then
        return
      end

      self.bindings:add(binding)
      self.hookable:emit('BindingBound', binding)
    end, { name = "$.S." .. session.id .. ".B.dap.onBreakpointNew" })

    session:onBindingChanged(function(dapBinding)
      -- Lets first check if the binding already exists for this session.
      -- Maybe the adapter is sending a changed event for a binding we already have.

      local sessionBindings = self.bindings:forSession(session)

      local binding = sessionBindings:match(dapBinding):first()
      if binding then
        binding:update(dapBinding)
        return
      end

      -- If we reach here, it means the binding does not exist in our sessionBreakpoints.
      -- But maybe it still has a matching breakpoint in the storage.

      local location = Location.SourceFile.fromDapBinding(dapBinding)
      if not location then
        return -- No valid location from DAP binding, cannot create binding
      end

      local breakpoint = self:ensureBreakpointAt(location)

      -- If we have a matching breakpoint, we can assume the binding should exist.
      local filesource = session:getFileSourceAt(location)
      if not filesource then
        return
      end

      local binding = FileSourceBinding.unverified(self, session, filesource, breakpoint)
      if not binding then
        return
      end

      self.bindings:add(binding)
      self.hookable:emit('BindingBound', binding)
    end, { name = "$.BM." .. session.id .. ".onBreakpointChanged" })

    session:onBindingRemoved(function(body)
      -- Lets first check if the binding already exists for this session.
      -- Maybe the adapter is sending a removed event for a binding we already have.

      local sessionBreakpoints = self.bindings:forSession(session)

      local binding = sessionBreakpoints:match(body):first()

      if binding then
        self.bindings:remove(binding)
        self.hookable:emit('BindingUnbound', binding)
      end

      -- Now, lets check if the breakpoint should be removed.
      local breakpoint = self.breakpoints:match(body):first()
      if not breakpoint then
        return -- No matching breakpoint found, nothing to remove
      end
    end, { name = "$.BM." .. session.id .. ".onBreakpointRemoved" })

    session:onSourceLoaded(function(source)
      local filesource = source:asFile()

      if not filesource then
        return -- Only file sources are supported for now
      end

      local breakpoints = self.breakpoints:atSourceId(filesource:identifier())
      local sessionBindings = self.bindings:forSession(session)

      for breakpoint in breakpoints:each() do
        local binding = sessionBindings:forBreakpoint(breakpoint):first()
        if not binding then
          -- Create a new binding for this session
          binding = FileSourceBinding.unverified(self, session, filesource, breakpoint)
          self.bindings:add(binding)
          self.hookable:emit('BindingBound', binding)
        end
      end

      self.bindings:forSession(session):forSource(filesource):push()
    end, { name = "$.BM." .. session.id .. ".onSourceLoaded" })

    session:onThread(function(thread)
      thread:onStopped(function(body)
        if body.reason ~= 'breakpoint' then
          return
        end

        local bindings = self.bindings:forSession(session):forIds(body.hitBreakpointIds or {})
        for binding in bindings:each() do
          binding:triggerHit(thread, body)
          self.hookable:emit('BindingHit', binding)
        end
      end, { name = "$.BM." .. session.id .. ".T." .. thread.id .. ".onThreadStopped" })
    end, { name = "$.BM." .. session.id .. ".onThread" })
  end)

  -- self:onBreakpointRemoved(function(breakpoint)
  --   nio.sleep(50)
  --   for session in self.api:eachSession() do
  --     local existing = self.bindings:forSession(session):forBreakpoint(breakpoint):first()
  --     if not existing then
  --       local filesource = session:getFileSourceAt(breakpoint.location)
  --       if filesource then
  --         local binding = FileSourceBinding.unverified(self, session, filesource, breakpoint)
  --         self.bindings:add(binding)
  --         self.hookable:emit('BindingBound', binding)
  --       end

  --       self.bindings:forSession(session):forSource(filesource):push()
  --     end
  --   end
  -- end, { name = "BM.onBreakpointRemoved", priority = 25 })

  self:onBreakpointAdded(function(breakpoint)
    nio.sleep(50)
    for session in self.api:eachSession() do
      local existing = self.bindings:forSession(session):forBreakpoint(breakpoint):first()
      if not existing then
        local filesource = session:getFileSourceAt(breakpoint.location)
        if filesource then
          local binding = FileSourceBinding.unverified(self, session, filesource, breakpoint)
          self.bindings:add(binding)
          self.hookable:emit('BindingBound', binding)
        end

        self.bindings:forSession(session):forSource(filesource):push()
      end
    end
  end, { name = "BM.onBreakpointAdded", priority = 25 })
end

return BreakpointManager
