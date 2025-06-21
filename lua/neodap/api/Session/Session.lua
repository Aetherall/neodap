local Class = require("neodap.tools.class")
local Thread = require("neodap.api.Session.Thread")
local Source = require('neodap.api.Session.Source.Source')
local BaseSource = require('neodap.api.Session.Source.BaseSource')
local Hookable = require("neodap.transport.hookable")

---@class api.SessionProps
---@field id integer
---@field ref Session
---@field protected _threads { [integer]: api.Thread? }
---@field _sources { [string]: api.Source? }
---@field hookable Hookable
---@field manager Manager

---@class api.Session: api.SessionProps
---@field new Constructor<api.SessionProps>
local Session = Class();

---@param ref Session
---@param manager Manager
function Session.wrap(ref, manager)
  ---@type api.Session
  local instance = Session:new({
    id = ref.id,
    ref = ref,
    _threads = {},
    _sources = {},
    _sessionBreakpoints = {},
    hookable = Hookable.create(),
    manager = manager
  })

  instance:listen()

  return instance
end

function Session:listen()
  local sessionId = tostring(self.ref.id or "unknown")
  local timestamp = tostring(os.time())
  local uniqueId = sessionId .. "_" .. timestamp .. "_" .. math.random(1000, 9999)

  self.ref.events:on('thread', function(body)
    if body.reason == 'started' then
      -- print("DEBUG: Session creating thread for threadId:", body.threadId)
      local thread = Thread.instanciate(self, body.threadId)
      self._threads[body.threadId] = thread
      -- print("DEBUG: Thread created, stored in _threads[" .. body.threadId .. "]")
    end
  end, { name = "SessionThreadStarted_" .. uniqueId, priority = 2 })

  self.ref.events:on('thread', function(body)
    if body.reason == 'exited' then
      self._threads[body.threadId] = nil
    end
  end, { name = "SessionThreadExited_" .. uniqueId, priority = 98 })


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
---@param predicate fun(source: api.Source): T
---@return T
function Session:findSource(predicate)
  for _, source in pairs(self._sources) do
    local result = predicate(source)
    if result then
      return result
    end
  end
  return nil
end


---@param location api.SourceFileLocation
---@return api.FileSource?
function Session:getFileSourceAt(location)
  return self:findSource(function(source)
  local filesource = source:asFile()
  if not filesource then
    return false
  end  
  -- print("DEBUG: Checking source:", vim.inspect(filesource.id))

    local samePlace = location:isAtSourceId(filesource.id)
    if not samePlace then
      return false
    end

    return filesource
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
      print("DEBUG: Session received breakpoint event - reason:", body.reason, "breakpoint:")
      if body.reason == "new" then
        print("DEBUG: Session forwarding 'new' breakpoint to listener")
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
      -- print("DEBUG: Session received breakpoint event - reason:", body.reason, "breakpoint:",
        -- vim.inspect(body.breakpoint))
      if body.reason == "changed" then
        -- print("DEBUG: Session forwarding 'changed' breakpoint to listener")
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

---@param listener fun(binding: api.FileSourceBinding)
function Session:onBinding(listener, opts)
  return self.manager.breakpoints:onBound(function(binding)
    if binding.session.id == self.id then
      listener(binding)
    end
  end, opts)
end

---@param listener fun(binding: api.FileSourceBinding, hit: table)
---@param opts? HookOptions
function Session:onBindingHit(listener, opts)
  return self:onBinding(function (binding)
    binding:onHit(function(hit)
      listener(binding, hit)
    end, opts)
  end, opts)
end

return Session
