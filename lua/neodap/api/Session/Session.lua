local Class = require('neodap.tools.class')
local Thread = require("neodap.api.Session.Thread")
local Source = require('neodap.api.Session.Source')
local SourceIdentifier = require('neodap.api.Location.SourceIdentifier')
local Hookable = require("neodap.transport.hookable")
local Logger = require("neodap.tools.logger")
local Threads = require("neodap.api.Session.Threads")
local Sources = require("neodap.api.Session.Sources")

---@class api.SessionProps
---@field id integer
---@field ref Session
---@field threads api.Threads
---@field sources api.Sources
---@field hookable Hookable
---@field manager Manager
---@field api Api

---@class api.Session: api.SessionProps
---@field new Constructor<api.SessionProps>
local Session = Class()

---@param ref Session
---@param manager Manager
---@param parentHookable? Hookable
---@param api? Api
function Session.wrap(ref, manager, parentHookable, api)
  local instance = Session:new({
    id = ref.id,
    ref = ref,
    threads = Threads.create(),
    sources = Sources.init(),
    manager = manager,
    api = api,
    hookable = Hookable.create(parentHookable)
  })

  -- Initialize event listeners
  instance:listen()

  -- Register cleanup on session termination and exit
  ref.events:on('terminated', function()
    instance:destroy()
  end, { name = "SessionCleanup_terminated_" .. instance.id, priority = 999, preemptible = false })

  ref.events:on('exited', function()
    instance:destroy()
  end, { name = "SessionCleanup_exited_" .. instance.id, priority = 999, preemptible = false })

  return instance
end

function Session:listen()
  local sessionId = tostring(self.ref.id or "unknown")
  local timestamp = tostring(os.time())
  local uniqueId = sessionId .. "_" .. timestamp .. "_" .. math.random(1000, 9999)

  self.ref.events:on('thread', function(body)
    if body.reason == 'started' then
      -- print("DEBUG: Session creating thread for threadId:", body.threadId)
      local thread = Thread.instanciate(self, body.threadId, self.hookable)
      self.threads:add(thread)
      -- print("DEBUG: Thread created, stored in threads collection")
    end
  end, { name = "SessionThreadStarted_" .. uniqueId, priority = 2 })

  self.ref.events:on('thread', function(body)
    if body.reason == 'exited' then
      local thread = self.threads:getBy("id", body.threadId)
      if thread then thread:destroy() end
      self.threads:removeBy("id", body.threadId)
    end
  end, { name = "SessionThreadExited_" .. uniqueId, priority = 98, preemptible = false })


  self:onLoadedSourceNew(function(dapSource)
    local identifier = SourceIdentifier.fromDapSource(dapSource, self)
    if not identifier then return end
    local id = identifier:toString()

    local existing = self.sources[id]

    if existing then
      if not dapSource.checksums then
        return
        -- print(vim.inspect(dapSource))
        -- error('cannot determine if existing source is outdated, no checksums provided')
      end

      local same = existing:matchesChecksums(dapSource.checksums)
      if same then
        return -- already loaded and matches checksums
      end

      -- TODO: Existing source is outdated, trigger onChanged
      -- existing:onChanged(source)
      return
    end

    -- Create a new source instance
    local instance = Source.instanciate(self, dapSource)
    self.sources:add(instance)
    self.hookable:emit('SourceLoaded', instance)
  end, { name = "SessionLoadedSourceNew_" .. uniqueId, priority = 1 })

  self:onLoadedSourceChanged(function(dapSource)
    local identifier = SourceIdentifier.fromDapSource(dapSource, self)
    if not identifier then return end
    local id = identifier:toString()

    local existing = self.sources:getBy("id", id)
    if existing then
      -- TODO: Update existing source with new content
      -- existing:onChanged(source)
    else
      -- If no existing source, just create a new one
      local instance = Source.instanciate(self, dapSource)
      self.sources:add(instance)
      self.hookable:emit('SourceLoaded', instance)
    end
  end, { name = "SessionLoadedSourceChanged_" .. uniqueId, priority = 1 })


  self:onLoadedSourceRemoved(function(dapSource)
    local identifier = SourceIdentifier.fromDapSource(dapSource, self)
    if not identifier then return end
    local id = identifier:toString()

    local existing = self.sources:getBy("id", id)
    if existing then
      -- TODO: Remove local source, trigger its onRemoved event
      -- existing:onRemoved()
      self.sources:removeBy("id", id)
    end
  end, { name = "SessionLoadedSourceRemoved_" .. uniqueId, priority = 1 })
end

function Session:onInitialized(listener, opts)
  return self.ref.events:on('initialized', listener, opts)
end

---@param listener fun(body: dap.OutputEventBody)
function Session:onOutput(listener, opts)
  return self.ref.events:on('output', listener, opts)
end

---@param listener fun(thread: api.Thread, body: dap.ThreadEventBody)
---@param opts? HookOptions
function Session:onThread(listener, opts)
  return self.ref.events:on('thread', function(body)
    if body.reason == 'started' then
      -- print("DEBUG: Session onThread called for threadId:", body.threadId)
      local thread = self.threads:getBy("id", body.threadId)
      if thread then
        -- print("DEBUG: Found thread in threads collection, calling listener")
        listener(thread, body)
      else
        -- print("DEBUG: Thread not found in _threads!")
        -- print("DEBUG: Available threads:", vim.inspect(vim.tbl_keys(self._threads)))
      end
    end
  end, opts)
end

---@param listener fun(body: dap.TerminatedEventBody)
---@param opts? HookOptions
function Session:onTerminated(listener, opts)
  return self.ref.events:on('terminated', listener, opts)
end

---@param listener fun(body: dap.ExitedEventBody)
---@param opts? HookOptions
function Session:onExited(listener, opts)
  return self.ref.events:on('exited', listener, opts)
end

---@param listener fun(source: api.Source)
---@param opts? HookOptions
function Session:onSourceLoaded(listener, opts)
  return self.hookable:on('SourceLoaded', listener, opts)
end

---@param listener fun(body: dap.Source)
---@param opts? HookOptions
function Session:onLoadedSourceNew(listener, opts)
  return self.ref.events:on('loadedSource',
    function(body)
      if body.reason == "new" then
        listener(body.source)
      end
    end
    , opts)
end

---@param listener fun(body: dap.Source)
---@param opts? HookOptions
function Session:onLoadedSourceChanged(listener, opts)
  return self.ref.events:on('loadedSource',
    function(body)
      if body.reason == "changed" then
        listener(body.source)
      end
    end
    , opts)
end

---@param listener fun(source: dap.Source)
---@param opts? HookOptions
function Session:onLoadedSourceRemoved(listener, opts)
  return self.ref.events:on('loadedSource',
    function(body)
      if body.reason == "removed" then
        listener(body.source)
      end
    end
    , opts)
end

---Find source by unified source identifier (preferred method)
---@param identifier SourceIdentifier | api.Location
---@return api.Source?
function Session:getSource(identifier)
  local sourceId = identifier:getSourceId()
  return self.sources:findBy("id", sourceId:toString())
end

---Get or create a source for the given DAP source
---This is the authoritative way to get source instances in the system
---@param dapSource dap.Source
---@return api.Source|nil
function Session:getSourceFor(dapSource)
  local identifier = SourceIdentifier.fromDapSource(dapSource, self)
  if not identifier then return nil end

  local existing = self.sources:findBy("id", identifier:toString())
  if existing then return existing end

  local source = Source.instanciate(self, dapSource)
  self.sources:add(source)
  self.hookable:emit('SourceLoaded', source)
  return source
end

---@param listener fun(body: dap.Breakpoint)
---@param opts? HookOptions
function Session:onBindingNew(listener, opts)
  return self.ref.events:on('breakpoint',
    ---@param body dap.BreakpointEventBody
    function(body)
      local log = Logger.get("API:Session")
      log:debug("Session", self.id, "- Received breakpoint event - reason:", body.reason, "breakpoint:", body.breakpoint)
      if body.reason == "new" then
        log:debug("Session", self.id, "- Forwarding 'new' breakpoint to listener")
        listener(body.breakpoint)
      end
    end
    , opts)
end

---@param listener fun(body: dap.Breakpoint)
---@param opts? HookOptions
function Session:onBindingChanged(listener, opts)
  return self.ref.events:on('breakpoint',
    ---@param body dap.BreakpointEventBody
    function(body)
      local log = Logger.get("API:Session")
      log:debug("Session", self.id, "- Received breakpoint event - reason:", body.reason, "breakpoint:", body.breakpoint)
      if body.reason == "changed" then
        log:debug("Session", self.id, "- Forwarding 'changed' breakpoint to listener")
        listener(body.breakpoint)
      end
    end
    , opts)
end

---@param listener fun(body: dap.Breakpoint)
---@param opts? HookOptions
function Session:onBindingRemoved(listener, opts)
  ---@param body dap.BreakpointEventBody
  return self.ref.events:on('breakpoint', function(body)
    if body.reason == "removed" then
      listener(body.breakpoint)
    end
  end
  , opts)
end

---Get valid breakpoint locations for a source range using DAP's breakpointLocations request
---@param source api.Source
---@param line? integer
---@param column? integer
---@return dap.BreakpointLocation[]|nil locations Array of valid breakpoint locations, or nil if not supported
function Session:getBreakpointLocations(source, line, column)
  local log = Logger.get("API:Session")

  -- Check if adapter supports breakpointLocations
  log:debug("Session", self.id, "- Checking adapter capabilities...")
  log:debug("Session", self.id, "- self.ref.capabilities:", vim.inspect(self.ref.capabilities))

  if not self.ref.capabilities or not self.ref.capabilities.supportsBreakpointLocationsRequest then
    log:debug("Session", self.id, "- Adapter does not support breakpointLocations request")
    if not self.ref.capabilities then
      log:debug("Session", self.id, "- No capabilities object found")
    else
      log:debug("Session", self.id, "- supportsBreakpointLocationsRequest:",
        self.ref.capabilities.supportsBreakpointLocationsRequest)
    end
    return nil
  end

  column = column or 0

  local args = {
    source = source.ref,
    line = line or 0,
    -- Only specify line, not column - let adapter return all valid locations on this line
    -- According to DAP spec: "If only the line is specified, the request returns all possible locations in that line"
  }

  log:debug("Session", self.id, "- Requesting breakpoint locations for line", line, "column", column)
  log:debug("Session", self.id, "- Request args:", vim.inspect(args))

  local success, result = pcall(function()
    return self.ref.calls:breakpointLocations(args):wait()
  end)

  if not success then
    log:debug("Session", self.id, "- breakpointLocations request failed:", result)
    return nil
  end

  log:debug("Session", self.id, "- breakpointLocations response:", vim.inspect(result))
  if result.breakpoints and #result.breakpoints > 0 then
    log:debug("Session", self.id, "- Valid breakpoint locations:")
    for i, location in ipairs(result.breakpoints) do
      log:debug("Session", self.id, "  [" .. i .. "] line:", location.line, "column:", location.column)
    end
  end
  log:debug("Session", self.id, "- Found", #result.breakpoints, "valid breakpoint locations")
  return result.breakpoints
end

-- ---@param opts { filter: 'stopped' | 'all' | 'running' }?
-- ---@return fun(): api.Thread?
-- function Session:eachThread(opts)
--   local filter = opts and opts.filter or 'all'

--   if filter == 'all' then
--     return self.threads:each()
--   elseif filter == 'stopped' then
--     return self.threads:eachWhere(function(thread) return thread.stopped end)
--   elseif filter == 'running' then
--     return self.threads:eachWhere(function(thread) return not thread.stopped end)
--   else
--     return self.threads:each()
--   end
-- end

-- ---Find the closest valid breakpoint location to the requested position
-- ---@param source api.Source
-- ---@param opts { line?: integer, column?: integer }
-- ---@return { line: integer, column: integer }|nil closest Closest valid location, or nil if none found
-- function Session:findClosestBreakpointLocation(source, opts)
--   local locations = self:getBreakpointLocations(source, opts.line, opts.column)
--   if not locations or #locations == 0 then
--     return nil
--   end

--   opts.column = opts.column or 0

--   -- Sort locations by column to find the best match
--   table.sort(locations, function(a, b)
--     return (a.column or 0) < (b.column or 0)
--   end)

--   -- For better UX, prefer the earliest valid location (beginning of statement)
--   -- unless the user specifically clicked at a later valid location
--   local earliest = locations[1]
--   if not earliest then
--     return nil
--   end

--   -- Check if any location is exactly at the requested position
--   for _, location in ipairs(locations) do
--     local locColumn = location.column or 0
--     if locColumn == opts.column then
--       return {
--         line = location.line,
--         column = locColumn
--       }
--     end
--   end

--   -- Default to the earliest (leftmost) valid location
--   return {
--     line = earliest.line,
--     column = earliest.column or 0
--   }
-- end

--- Destroys this session and all its child resources
--- This method ensures complete cleanup of threads, sources and handlers
function Session:destroy()
  -- Clean up threads using Collection methods

  for thread in self.threads:each() do
    thread:destroy()
  end
  self.threads:clear()

  -- for source in self.sources:each() do
  --   source:destroy()
  -- end
  self.sources:clear()

  self.hookable:destroy()
end

return Session
