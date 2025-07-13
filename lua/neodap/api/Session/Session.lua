local Class = require("neodap.tools.class")
local Thread = require("neodap.api.Session.Thread")
local Source = require('neodap.api.Session.Source.Source')
local BaseSource = require('neodap.api.Session.Source.BaseSource')
local Hookable = require("neodap.transport.hookable")
local Logger = require("neodap.tools.logger")

---@class api.SessionProps
---@field id integer
---@field ref Session
---@field protected _threads { [integer]: api.Thread? }
---@field _sources { [string]: api.Source? }
---@field hookable Hookable
---@field manager Manager
---@field api Api

---@class api.Session: api.SessionProps
---@field new Constructor<api.SessionProps>
local Session = Class();

---@param ref Session
---@param manager Manager
---@param parentHookable? Hookable
---@param api? Api
function Session.wrap(ref, manager, parentHookable, api)
  ---@type api.Session
  local instance = Session:new({
    id = ref.id,
    ref = ref,
    _threads = {},
    _sources = {},
    _sessionBreakpoints = {},
    hookable = Hookable.create(parentHookable),
    manager = manager,
    api = api
  })

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
      self._threads[body.threadId] = thread
      -- print("DEBUG: Thread created, stored in _threads[" .. body.threadId .. "]")
    end
  end, { name = "SessionThreadStarted_" .. uniqueId, priority = 2 })

  self.ref.events:on('thread', function(body)
    if body.reason == 'exited' then
      local thread = self._threads[body.threadId]
      if thread and thread.destroy then
        thread:destroy()
      end
      self._threads[body.threadId] = nil
    end
  end, { name = "SessionThreadExited_" .. uniqueId, priority = 98, preemptible = false })


  self:onLoadedSourceNew(function(dapSource)
    local id = BaseSource.dap_identifier(dapSource)
    if not id then return end

    local existing = self._sources[id]

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
    self._sources[id] = instance

    self.hookable:emit('SourceLoaded', instance)
  end, { name = "SessionLoadedSourceNew_" .. uniqueId, priority = 1 })

  self:onLoadedSourceChanged(function(dapSource)
    local id = BaseSource.dap_identifier(dapSource)
    if not id then return end

    local existing = self._sources[id]
    if existing then
      -- TODO: Update existing source with new content
      -- existing:onChanged(source)
    else
      -- If no existing source, just create a new one
      self._sources[id] = Source.instanciate(self, dapSource)
      self.hookable:emit('SourceLoaded', self._sources[id])
    end
  end, { name = "SessionLoadedSourceChanged_" .. uniqueId, priority = 1 })


  self:onLoadedSourceRemoved(function(dapSource)
    local id = BaseSource.dap_identifier(dapSource)
    if not id then return end

    local existing = self._sources[id]
    if existing then
      -- TODO: Remove local source, trigger its onRemoved event
      -- existing:onRemoved()
      self._sources[id] = nil
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
      local thread = self._threads[body.threadId]
      if thread then
        -- print("DEBUG: Found thread in _threads, calling listener")
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

---@return api.Source?
function Session:getSourceForPath(path)
  for _, source in pairs(self._sources) do
    local filesource = source:asFile()
    if filesource and filesource:absolutePath() == path then
      return source
    end
  end
end

---@generic T
---@param predicate fun(source: api.Source): T?
---@return T
function Session:findSource(predicate)
  for _, source in pairs(self._sources) do
    local result = predicate(source)
    if result then
      return source
    end
  end
  return nil
end


---@param location api.SourceFilePosition|api.SourceFileLine|api.SourceFile
---@return api.FileSource?
function Session:getFileSourceAt(location)
  return self:findSource(function(source)
    local filesource = source:asFile()
    return filesource and filesource:absolutePath() == location.path
  end)
end

---Find virtual source by source identifier
---@param identifier VirtualSourceIdentifier
---@return api.VirtualSource?
function Session:getVirtualSourceByIdentifier(identifier)
  return self:findSource(function(source)
    local virtualsource = source:asVirtual()
    if not virtualsource then
      return false
    end
    
    local source_identifier = virtualsource:identifier()
    return source_identifier:equals(identifier)
  end)
end

---Get or create a source for the given DAP source
---This is the authoritative way to get source instances in the system
---@param dapSource dap.Source
---@return api.Source|nil
function Session:getSourceFor(dapSource)
  -- Initialize the cache if needed
  if not self._sources then
    ---@type { [string]: api.Source? }
    self._sources = {}
  end

  local identifier = BaseSource.dap_identifier(dapSource)
  if not identifier then
    -- TODO: Should we error here ?
    return nil
  end

  -- Check if we already have this source cached
  local existing = self._sources[identifier]
  if existing then
    return existing
  end

  -- Cache and return the new source
  self._sources[identifier] = Source.instanciate(self, dapSource)

  self.hookable:emit('SourceLoaded', self._sources[identifier])

  return self._sources[identifier]
end

---@param listener fun(body: dap.Breakpoint)
---@param opts? HookOptions
function Session:onBindingNew(listener, opts)
  return self.ref.events:on('breakpoint',
    ---@param body dap.BreakpointEventBody
    function(body)
      local log = Logger.get()
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
      local log = Logger.get()
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

--- Destroys this session and all its child resources
--- This method ensures complete cleanup of threads, sources, and handlers
function Session:destroy()
  local log = Logger.get()
  log:debug("Session", self.id, "destroy() called - cleaning up child resources")
  
  -- Clean up all threads first
  for threadId, thread in pairs(self._threads) do
    if thread and thread.destroy then
      log:debug("Session", self.id, "destroying thread", threadId)
      thread:destroy()
    end
  end
  
  -- Clean up all sources (VirtualSource:destroy() handles virtual buffer cleanup)
  for sourceId, source in pairs(self._sources) do
    if source and source.destroy then
      log:debug("Session", self.id, "destroying source", sourceId)
      source:destroy()
    end
  end
  
  -- Clean up our hookable (and all handlers registered on it)
  if self.hookable and not self.hookable.destroyed then
    log:debug("Session", self.id, "destroying hookable and all handlers")
    self.hookable:destroy()
  end
  
  -- Clear references
  self._threads = {}
  self._sources = {}
  
  log:info("Session", self.id, "destroyed successfully")
end

---Get valid breakpoint locations for a source range using DAP's breakpointLocations request
---@param source api.FileSource
---@param line integer
---@param column? integer
---@return dap.BreakpointLocation[]|nil locations Array of valid breakpoint locations, or nil if not supported
function Session:getBreakpointLocations(source, line, column)
  local log = Logger.get()
  
  -- Check if adapter supports breakpointLocations
  log:debug("Session", self.id, "- Checking adapter capabilities...")
  log:debug("Session", self.id, "- self.ref.capabilities:", vim.inspect(self.ref.capabilities))
  
  if not self.ref.capabilities or not self.ref.capabilities.supportsBreakpointLocationsRequest then
    log:debug("Session", self.id, "- Adapter does not support breakpointLocations request")
    if not self.ref.capabilities then
      log:debug("Session", self.id, "- No capabilities object found")
    else
      log:debug("Session", self.id, "- supportsBreakpointLocationsRequest:", self.ref.capabilities.supportsBreakpointLocationsRequest)
    end
    return nil
  end
  
  column = column or 0
  
  local args = {
    source = source.ref,
    line = line
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

---Find the closest valid breakpoint location to the requested position
---@param source api.FileSource
---@param line integer
---@param column? integer
---@return { line: integer, column: integer }|nil closest Closest valid location, or nil if none found
function Session:findClosestBreakpointLocation(source, line, column)
  local locations = self:getBreakpointLocations(source, line, column)
  if not locations or #locations == 0 then
    return nil
  end
  
  column = column or 0
  
  -- Sort locations by column to find the best match
  table.sort(locations, function(a, b) 
    return (a.column or 0) < (b.column or 0) 
  end)
  
  -- For better UX, prefer the earliest valid location (beginning of statement)
  -- unless the user specifically clicked at a later valid location
  local earliest = locations[1]
  if not earliest then
    return nil
  end
  
  -- Check if any location is exactly at the requested position
  for _, location in ipairs(locations) do
    local locColumn = location.column or 0
    if locColumn == column then
      return {
        line = location.line,
        column = locColumn
      }
    end
  end
  
  -- Default to the earliest (leftmost) valid location
  return {
    line = earliest.line,
    column = earliest.column or 0
  }
end

return Session
