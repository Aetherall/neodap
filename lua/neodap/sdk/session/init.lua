---@class Session : Class
---@field id string
---@field debugger Debugger
---@field client DapClient
---@field capabilities dap.Capabilities?  -- Set after initialize
---@field name Signal<string>
---@field state Signal<SessionState>
---@field parent Session?
---@field children List<Session>
---@field bindings List<Binding>
---@field threads List<Thread>
---@field outputs List<Output>
---@field sources Collection<Source>
---@field _exception_filter_bindings Collection<ExceptionFilterBinding>  -- Cached subcollection

---@alias SessionState "initializing" | "running" | "stopped" | "terminated"

local neostate = require("neostate")
local Thread = require("neodap.sdk.session.thread").Thread
local SourceModule = require("neodap.sdk.debugger.source")
local Source = SourceModule.Source
local compute_correlation_key = SourceModule.compute_correlation_key
local neoword = require("neoword")
local Output = require("neodap.sdk.session.output").Output
local Binding = require("neodap.sdk.session.breakpoint_binding").Binding
local SourceBinding = require("neodap.sdk.session.source_binding").SourceBinding
local ExceptionFilterBinding = require("neodap.sdk.session.exception_filter_binding").ExceptionFilterBinding

local M = {}

-- =============================================================================
-- SESSION
-- =============================================================================

---@class Session : Class
local Session = neostate.Class("Session")

function Session:init(debugger, logical_type, adapter, parent_session)
  self.debugger = debugger
  self.parent = parent_session
  self._logical_type = logical_type
  self.adapter = adapter

  -- Generate unique session ID (pronounceable random ID)
  self.id = neoword.generate()

  -- URI and key for EntityStore
  self.uri = "dap:session:" .. self.id
  self.key = self.id
  self._type = "session"

  -- Eager expansion: sessions auto-expand in tree views
  self.eager = true

  self.name = self:signal("debug-session", "name")
  self.state = self:signal("initializing", "state")

  -- Event emitter for lifecycle hooks
  self._event_listeners = {}

  -- Track how this session was started (from process event)
  self.start_method = self:signal(nil, "start_method")           -- "launch" | "attach" | "attachForSuspendedLaunch"
  self.is_auto_attached = self:signal(false, "is_auto_attached") -- Convenience flag
  self.process_id = self:signal(nil, "process_id")               -- OS process ID

  -- Note: children and outputs are managed via EntityStore, accessed via children() and outputs() methods

  -- Bind all existing global breakpoints to this session
  -- The DAP adapter will decide which ones are relevant (via verified flag)
  for breakpoint in debugger.breakpoints:iter() do
    self:_try_bind_breakpoint(breakpoint)
  end

  -- Create cached subcollection for exception filter bindings
  self._exception_filter_bindings = debugger.exception_filter_bindings:where(
    "by_session",
    self.id,
    "ExceptionFilterBindings:Session:" .. self.id
  )
  self._exception_filter_bindings:set_parent(self)

  -- Bind all exception filters for this adapter type
  for filter in debugger.exception_filters:where("by_adapter", logical_type):iter() do
    local binding = ExceptionFilterBinding:new(filter, self)
    binding:set_parent(self)
    -- Add to EntityStore with edges to session and filter
    debugger.store:add(binding, "exception_filter_binding", {
      { type = "exception_filter_binding", to = self.uri },
      { type = "exception_filter_binding", to = filter.uri }
    })
  end

  -- Connect to the adapter
  local raw_client = self.adapter.connect()

  -- Wrap client to return Promises instead of using callbacks
  self.client = {
    request = function(_, command, args)
      local promise = neostate.Promise(nil, "DAP:" .. command)

      -- Call raw client with callback that resolves/rejects the promise
      raw_client:request(command, args, function(err, result)
        if err then
          promise:reject(err)
        else
          promise:resolve(result)
        end
      end)

      return promise
    end,

    on = function(_, event, handler)
      return raw_client:on(event, handler)
    end,

    on_request = function(_, command, handler)
      return raw_client:on_request(command, handler)
    end,

    close = function(_)
      return raw_client:close()
    end,

    is_closing = function(_)
      return raw_client:is_closing()
    end,
  }

  -- Wire up DAP events
  self:_setup_events()

  -- Cleanup on dispose
  self:on_dispose(function()
    self.client:close()
  end)
end

---Set up DAP event handlers
function Session:_setup_events()
  local client = self.client

  -- Initialized - sync breakpoints and exception filters, then send configurationDone
  client:on("initialized", self:bind(neostate.void(function(body)
    -- Sync all registered breakpoints BEFORE configurationDone
    self:_sync_breakpoints_to_dap(nil)

    -- Sync exception filters
    self:_sync_exception_filters_to_dap()

    -- All breakpoints synced, now send configurationDone
    local result, err = neostate.settle(client:request("configurationDone", vim.empty_dict()))
    if not err then
      self.state:set("running")
    end
  end)))

  -- Thread lifecycle
  client:on("thread", self:bind(function(body)
    if body.reason == "started" then
      local thread = Thread:new(self, body.threadId)

      -- Add to EntityStore with parent edge to session
      self.debugger.store:add(thread, "thread", {
        { type = "parent", to = self.uri }
      })
      -- Add children edge from session to thread (for follow traversal)
      self.debugger.store:add_edge(self.uri, "threads", thread.uri)
    elseif body.reason == "exited" then
      -- Remove from EntityStore
      local thread_uri = "dap:session:" .. self.id .. "/thread:" .. body.threadId
      self.debugger.store:dispose_entity(thread_uri)
    end
  end))

  --Thread stopped
  client:on("stopped", self:bind(function(body)
    self.state:set("stopped")

    -- Mark bindings as hit if stopped at breakpoint
    if body.reason == "breakpoint" then
      if body.hitBreakpointIds then
        -- Precise: mark only specific bindings by DAP ID
        -- Search within THIS session's bindings, not global (DAP IDs are per-session)
        for _, hit_id in ipairs(body.hitBreakpointIds) do
          local binding = self:bindings():get_one("by_dap_id", hit_id)
          if binding then
            binding.hit:set(true)
          end
        end
      else
        -- Fallback: adapter didn't provide IDs, need to infer from stack
        -- Fetch top frame to determine which binding was hit
        local thread_id = body.threadId
        local thread = self:_find_thread(thread_id)
        if thread then
          neostate.void(function()
            -- Wait a bit for breakpoint sync to complete (race condition fix)
            vim.wait(100)

            local stack = thread:stack()
            if stack then
              local top_frame = stack:top()
              if top_frame then
                -- Find binding by location (binding.location is updated when adapter adjusts line)
                local binding = self:bindings():get_one("by_location", top_frame.location)

                if binding then
                  binding.hit:set(true)
                end
              end
            end
          end)()
        end
      end
    end

    local thread_id = body.threadId
    if body.allThreadsStopped then
      -- Update all threads
      for thread in self:threads():iter() do
        thread:_on_stopped(body.reason, body.threadId == thread.id)
      end
    else
      -- Update specific thread
      local thread = self:_find_thread(thread_id)
      if thread then
        thread:_on_stopped(body.reason, true)
      end
    end

    -- NOTE: Frame fetching is lazy - happens when thread:stack() is called
    -- active_frame will be set when frames are actually created
  end))

  -- Thread continued
  client:on("continued", self:bind(function(body)
    -- Clear hit state and active frames for this session's bindings
    for binding in self:bindings():iter() do
      binding.hit:set(false)
      binding.active_frame:set(nil)
    end

    -- Mark current stacks as expired when thread continues
    local threads_to_update = {}
    if body.allThreadsContinued then
      for thread in self:threads():iter() do
        table.insert(threads_to_update, thread)
      end
    else
      local thread = self:_find_thread(body.threadId)
      if thread then
        table.insert(threads_to_update, thread)
      end
    end

    for _, thread in ipairs(threads_to_update) do
      local current_stack = thread._current_stack:release()
      if current_stack then
        current_stack:_mark_expired()
      end
    end

    if body.allThreadsContinued then
      self.state:set("running")
      for thread in self:threads():iter() do
        thread:_on_continued()
      end
    else
      local thread = self:_find_thread(body.threadId)
      if thread then
        thread:_on_continued()
      end
      -- Check if all threads in this session are running
      local any_stopped = false
      for t in self:threads():iter() do
        if t.state:get() == "stopped" then
          any_stopped = true
          break
        end
      end
      if not any_stopped then
        self.state:set("running")
      end
    end
  end))

  -- Output (Output:new adds itself to EntityStore)
  client:on("output", self:bind(function(body)
    Output:new(self, body)
  end))

  -- Breakpoint events (verification updates)
  client:on("breakpoint", self:bind(function(body)
    local bp_data = body.breakpoint
    -- Find binding by DAP ID
    for binding in self:bindings():iter() do
      if binding.dapId:get() == bp_data.id then
        binding.verified:set(bp_data.verified)
        binding.message:set(bp_data.message)
        if bp_data.line then
          binding.actualLine:set(bp_data.line)
        end
        break
      end
    end
  end))

  -- loadedSource event (source added/changed/removed)
  client:on("loadedSource", self:bind(function(body)
    local reason = body.reason
    local source_data = body.source

    if reason == "new" then
      self:get_or_create_source(source_data)
    elseif reason == "changed" then
      self:_handle_source_changed(source_data)
    elseif reason == "removed" then
      self:_handle_source_removed(source_data)
    end
  end))

  -- Process event (tracks how session was started)
  client:on("process", self:bind(function(body)
    -- Store process information
    if body.systemProcessId then
      self.process_id:set(body.systemProcessId)
    end

    -- Track start method
    if body.startMethod then
      self.start_method:set(body.startMethod)

      -- Set convenience flag for auto-attached sessions
      if body.startMethod == "attachForSuspendedLaunch" then
        self.is_auto_attached:set(true)
      else
        self.is_auto_attached:set(false)
      end
    end
  end))

  -- Session terminated
  client:on("terminated", self:bind(function(body)
    self.state:set("terminated")

    -- Dispose all threads for this session via EntityStore
    for thread in self:threads():iter() do
      self.debugger.store:dispose_entity(thread.uri)
    end

    -- Dispose all bindings for this session
    for binding in self:bindings():iter() do
      self.debugger.store:dispose_entity(binding.uri)
    end

    -- Dispose all source bindings for this session
    for sb in self:source_bindings():iter() do
      self.debugger.store:dispose_entity(sb.uri)
    end

    -- Dispose session entity from EntityStore
    self.debugger.store:dispose_entity(self.uri)

    self:dispose()
  end))

  -- Handle startDebugging reverse request (for child sessions)
  client:on_request("startDebugging", self:bind(function(args)
    neostate.void(function()
      local config = args.configuration
      local request_type = args.request -- "launch" or "attach"

      -- Create child session (passes just the type, adapter is reused from parent)
      local child = self.debugger:create_session(self._logical_type, self)

      -- Set session name from config (js-debug provides names like "script.js [12345]")
      child.name:set(config.name)

      -- Start the session
      child:initialize({
        clientID = "neodap",
        adapterID = self._logical_type,
        pathFormat = "path",
        linesStartAt1 = true,
        columnsStartAt1 = true,
      })

      if request_type == "launch" then
        child:launch(config)
      elseif request_type == "attach" then
        child:attach(config)
      end
    end)()
    -- Return success immediately
    return {}
  end))

  -- Handle runInTerminal reverse request (for launching programs in terminals)
  client:on_request("runInTerminal", function(args)
    local pid = self.debugger:run_in_terminal(args)
    return { processId = pid }
  end)
end

---Get root session ID (walks parent chain)
---@return string
function Session:get_root_id()
  local session = self
  while session.parent do
    session = session.parent
  end
  return session.id
end

---Get filtered threads for this session
---@return table Filtered collection of threads
function Session:threads()
  if not self._threads then
    self._threads = self.debugger.threads:where(
      "by_session_id",
      self.id,
      "Threads:Session:" .. self.id
    )
  end
  return self._threads
end

---Get filtered frames for this session (across all threads/stacks)
---@return table Filtered collection of frames
function Session:frames()
  if not self._frames then
    self._frames = self.debugger.frames:where(
      "by_session_id",
      self.id,
      "Frames:Session:" .. self.id
    )
  end
  return self._frames
end

---Find thread by ID
---@param thread_id number
---@return Thread?
function Session:_find_thread(thread_id)
  for thread in self:threads():iter() do
    if thread.id == thread_id then
      return thread
    end
  end
  return nil
end

---Try to bind a global breakpoint to this session
---@param breakpoint Breakpoint
function Session:_try_bind_breakpoint(breakpoint)
  -- Check if already bound
  for binding in self:bindings():iter() do
    if binding.breakpoint == breakpoint then
      return -- Already bound
    end
  end

  -- Create binding
  -- The DAP adapter will return verified:false for breakpoints it doesn't care about
  local binding = Binding:new(breakpoint, self)
  binding:set_parent(self)  -- Bind lifecycle to session

  -- Add to EntityStore with edges to session and breakpoint
  self.debugger.store:add(binding, "binding", {
    { type = "binding", to = self.uri },
    { type = "binding", to = breakpoint.uri }
  })

  -- Sync to DAP (adapter will verify/reject as appropriate)
  self:_sync_breakpoints_to_dap()
end

---Sync all breakpoints for a file to DAP (async - must be called in coroutine)
---@param source? { path?: string, name?: string, correlation_key?: string }  -- If nil, sync all files
---@return string? error
function Session:_sync_breakpoints_to_dap(source)
  -- Don't sync if session not ready or terminated
  local state = self.state:get()
  if not self.client or state == "terminated" or self.client:is_closing() then
    return nil
  end

  -- Helper to get a unique identifier for a source (supports virtual sources)
  local function get_source_key(src)
    return src.path or src.name or src.correlation_key or "unknown"
  end

  -- Helper to check if a breakpoint matches the filter source
  local function matches_source(bp_source, filter_source)
    if not filter_source then return true end
    -- Match by path, name, or correlation_key
    if filter_source.path and bp_source.path == filter_source.path then return true end
    if filter_source.name and bp_source.name == filter_source.name then return true end
    if filter_source.correlation_key and bp_source.correlation_key == filter_source.correlation_key then return true end
    return false
  end

  -- Group bindings by source (only enabled breakpoints)
  local by_source = {}
  for binding in self:bindings():iter() do
    local bp = binding.breakpoint
    local source_key = get_source_key(bp.source)
    -- Skip disabled breakpoints
    if bp.enabled:get() and matches_source(bp.source, source) then
      if not by_source[source_key] then
        by_source[source_key] = { source = bp.source, bindings = {} }
      end
      table.insert(by_source[source_key].bindings, binding)
    end
  end

  -- Send setBreakpoints for each source and await completion
  for _, data in pairs(by_source) do
    local dap_breakpoints = {}
    for _, binding in ipairs(data.bindings) do
      local bp = binding.breakpoint
      table.insert(dap_breakpoints, {
        line = bp.line,
        column = bp.column,  -- Optional column position
        condition = bp.condition:get(),
        logMessage = bp.logMessage:get(),
        hitCondition = bp.hitCondition:get(),
      })
    end

    -- Build DAP source object
    -- For virtual sources, look up session-specific sourceReference from SourceBinding
    -- A source is virtual if it has sourceReference > 0, regardless of whether path is set
    -- (js-debug sets path to pseudo-paths like "<node_internals>/internal/timers")
    local dap_source = { name = data.source.name, path = data.source.path }

    -- For virtual sources (identified by sourceReference > 0 in the breakpoint),
    -- we must look up the session-specific sourceReference from SourceBinding.
    -- sourceReference values are NOT portable between sessions!
    local is_virtual_source = data.source.sourceReference and data.source.sourceReference > 0
    local found_binding = false

    if data.source.correlation_key then
      for sb in self.debugger.source_bindings:iter() do
        if sb.session == self and sb.source.correlation_key == data.source.correlation_key then
          found_binding = true
          if sb.sourceReference > 0 then
            dap_source.sourceReference = sb.sourceReference
          end
          break
        end
      end
    end

    -- For virtual sources, if no SourceBinding found for this session, skip entirely.
    -- The sourceReference from the breakpoint is from a different session and won't work.
    if is_virtual_source and not found_binding then
      goto continue
    end

    local result, err = neostate.settle(self.client:request("setBreakpoints", {
      source = dap_source,
      breakpoints = dap_breakpoints,
    }))

    if not err and result and result.breakpoints then
      -- Update bindings with verification results
      for i, bp_result in ipairs(result.breakpoints) do
        local binding = data.bindings[i]
        if binding then
          binding.dapId:set(bp_result.id)
          binding.verified:set(bp_result.verified)
          binding.message:set(bp_result.message)
          binding.actualLine:set(bp_result.line)
          binding.actualColumn:set(bp_result.column)
        end
      end
    end
    ::continue::
  end

  return nil
end

---Sync exception filters to DAP (async - must be called in coroutine)
---@return string? error
function Session:_sync_exception_filters_to_dap()
  -- Don't sync if session not ready or terminated
  local state = self.state:get()
  if not self.client or state == "terminated" or self.client:is_closing() then
    return nil
  end

  -- Collect enabled filter IDs and bindings in single pass
  local filters = {}
  local enabled_bindings = {}
  for binding in self:exception_filter_bindings():iter() do
    if binding.filter.enabled:get() then
      table.insert(filters, binding.filter.filter_id)
      table.insert(enabled_bindings, binding)
    end
  end

  local result, err = neostate.settle(self.client:request("setExceptionBreakpoints", {
    filters = filters,
  }))

  if err then
    return err
  end

  -- Update binding verification from response
  -- DAP spec: response order matches request order
  if result and result.breakpoints then
    for i, bp_result in ipairs(result.breakpoints) do
      local binding = enabled_bindings[i]
      if binding then
        binding.dapId = bp_result.id
        binding.verified:set(bp_result.verified)
        binding.message:set(bp_result.message)
      end
    end
  end

  return nil
end

---Get or create a Source entity from global registry
---Creates source binding for this session if needed
---@param data { path?: string, name?: string, sourceReference?: number, checksums?: table, adapterData?: any }
---@return Source
function Session:get_or_create_source(data)
  -- Compute correlation key (same logic as in source.lua)
  local correlation_key
  if data.path then
    correlation_key = data.path
  else
    local checksum_str = nil
    if data.checksums and #data.checksums > 0 then
      checksum_str = data.checksums[1].checksum
    end
    if checksum_str then
      correlation_key = (data.name or "unknown") .. ":" .. neoword.generate(checksum_str)
    else
      correlation_key = data.name or "unknown"
    end
  end

  -- Look up or create global source
  local source = self.debugger.sources:get_one("by_correlation_key", correlation_key)
  if not source then
    -- Create new global source
    source = Source:new(self.debugger, data)

    -- Add to EntityStore (global source, no edges)
    self.debugger.store:add(source, "source", {})
  end

  -- Look up existing binding for this session
  local existing_binding = nil
  for binding in self.debugger.source_bindings:iter() do
    if binding.session == self and binding.source == source then
      existing_binding = binding
      break
    end
  end

  -- Create binding if needed
  if not existing_binding then
    local binding = SourceBinding:new(
      source,
      self,
      data.sourceReference or 0,
      data.adapterData
    )

    -- Add to EntityStore with edges to session and source
    self.debugger.store:add(binding, "source_binding", {
      { type = "source_binding", to = self.uri },
      { type = "source_binding", to = source.uri }
    })
  end

  return source
end

---Initialize session with standard DAP initialization sequence
---@param init_args? dap.InitializeRequestArguments  -- Optional, SDK provides defaults
---@return string? error
function Session:initialize(init_args)
  -- Provide sensible defaults for DAP initialization
  local default_args = {
    clientID = "neodap",
    clientName = "Neodap SDK",
    adapterID = self.adapter and self.adapter.type or "unknown",
    pathFormat = "path",
    linesStartAt1 = true,
    columnsStartAt1 = true,
    supportsVariableType = true,
    supportsVariablePaging = false,
    supportsRunInTerminalRequest = true, -- Enable runInTerminal support
  }

  -- Merge user args with defaults (user args take precedence)
  local merged_args = vim.tbl_deep_extend("force", default_args, init_args or {})

  local result, err = neostate.settle(self.client:request("initialize", merged_args))
  if err then
    return err
  end

  -- Store capabilities for later use (completions, etc.)
  self.capabilities = result

  -- configurationDone will be sent automatically in initialized event
  return nil
end

---Launch a program
---Must be called from within a coroutine context
---@param launch_args dap.LaunchRequestArguments
---@return string? error
function Session:launch(launch_args)
  -- Store launch args for potential restart
  self._launch_args = launch_args
  self._request_type = "launch"

  -- Send launch request (will yield in coroutine context)
  -- The launch request may not complete until after configurationDone is sent
  local result, err = neostate.settle(self.client:request("launch", launch_args))
  return err
end

---Attach to a process
---@param attach_args dap.AttachRequestArguments
---@return string? error
function Session:attach(attach_args)
  -- Store attach args for potential restart
  self._launch_args = attach_args
  self._request_type = "attach"

  local result, err = neostate.settle(self.client:request("attach", attach_args))
  return err
end

---Continue execution
---@param thread_id? number  -- If nil, continue all threads
---@return string? error, boolean? all_continued
function Session:continue(thread_id)
  thread_id = thread_id or 0 -- 0 means all threads per DAP spec

  -- Immediately invalidate current stacks before continuing using release() to avoid disposal
  -- This ensures that when the thread stops again, thread:stack() will fetch fresh data
  if thread_id == 0 then
    -- All threads
    for thread in self:threads():iter() do
      local current = thread._current_stack:release()
      if current then
        current:_mark_expired()
      end
    end
  else
    -- Specific thread
    local thread = self:_find_thread(thread_id)
    if thread then
      local current = thread._current_stack:release()
      if current then
        current:_mark_expired()
      end
    end
  end

  local result, err = neostate.settle(self.client:request("continue", {
    threadId = thread_id,
  }))

  if err then
    return err, nil
  else
    return nil, result and result.allThreadsContinued
  end
end

-- =============================================================================
-- LIFECYCLE HOOKS
-- =============================================================================

---Register callback for threads (existing + future)
---@param fn function  -- Called with (thread)
---@return function unsubscribe
function Session:onThread(fn)
  return self:threads():each(fn)
end

---Get filtered bindings for this session
---@return table Filtered collection of bindings
function Session:bindings()
  if not self._bindings then
    self._bindings = self.debugger.bindings:where(
      "by_session_id",
      self.id,
      "Bindings:Session:" .. self.id
    )
  end
  return self._bindings
end

---Register callback for breakpoint bindings (existing + future)
---@param fn function  -- Called with (binding)
---@return function unsubscribe
function Session:onBinding(fn)
  return self:bindings():each(fn)
end

---Get filtered outputs for this session
---@return View Filtered view of outputs
function Session:outputs()
  if not self._outputs then
    self._outputs = self.debugger.outputs:where(
      "by_session_id",
      self.id,
      "Outputs:Session:" .. self.id
    )
  end
  return self._outputs
end

---Register callback for debug output (existing + future)
---@param fn function  -- Called with (output)
---@return function unsubscribe
function Session:onOutput(fn)
  return self:outputs():each(fn)
end

---Get child sessions (sessions spawned from this session)
---@return View Filtered view of child sessions
function Session:children()
  if not self._children then
    -- Create a single-entity view of this session, then follow "children" edge
    local self_view = self.debugger.sessions:where("by_id", self.id)
    self._children = self_view:follow("children", "session")
  end
  return self._children
end

---Register callback for child sessions (existing + future)
---@param fn function  -- Called with (child_session)
---@return function unsubscribe
function Session:onChild(fn)
  return self:children():each(fn)
end

---Get filtered exception filter bindings for this session
---@return table Filtered collection of exception filter bindings
function Session:exception_filter_bindings()
  return self._exception_filter_bindings
end

---Register callback for exception filter bindings (existing + future)
---@param fn function  -- Called with (binding: ExceptionFilterBinding)
---@return function unsubscribe
function Session:onExceptionFilterBinding(fn)
  return self._exception_filter_bindings:each(fn)
end

---Get filtered source bindings for this session
---@return table Filtered collection of source bindings
function Session:source_bindings()
  if not self._source_bindings then
    self._source_bindings = self.debugger.source_bindings:where(
      "by_session_id",
      self.id,
      "SourceBindings:Session:" .. self.id
    )
  end
  return self._source_bindings
end

---Get filtered sources for this session (via source bindings)
---@return table Filtered collection of sources
function Session:sources()
  -- Create a temporary collection that maps bindings to sources
  -- This is a bit tricky since we need to return sources, not bindings
  -- For now, let's just iterate through bindings and collect unique sources
  local sources_list = {}
  local seen = {}

  for binding in self:source_bindings():iter() do
    if not seen[binding.source] then
      table.insert(sources_list, binding.source)
      seen[binding.source] = true
    end
  end

  return sources_list
end

---Register callback for sources (existing + future)
---@param fn function  -- Called with (source)
---@return function unsubscribe
function Session:onSource(fn)
  -- Call fn for each existing source
  for _, source in ipairs(self:sources()) do
    fn(source)
  end

  -- Subscribe to future source bindings and call fn with the source
  return self:source_bindings():each(function(binding)
    fn(binding.source)
  end)
end

---Register callback for restart event
---@param fn function  -- Called when restart begins (no arguments)
---@return function unsubscribe
function Session:onRestart(fn)
  return self:_on("restart", fn)
end

---Register callback for restarted event
---@param fn function  -- Called when restart completes (no arguments)
---@return function unsubscribe
function Session:onRestarted(fn)
  return self:_on("restarted", fn)
end

---Internal: Register event listener
---@param event string
---@param fn function
---@return function unsubscribe
function Session:_on(event, fn)
  if not self._event_listeners[event] then
    self._event_listeners[event] = {}
  end
  table.insert(self._event_listeners[event], fn)

  -- Return unsubscribe function
  return function()
    local listeners = self._event_listeners[event]
    if listeners then
      for i, listener in ipairs(listeners) do
        if listener == fn then
          table.remove(listeners, i)
          break
        end
      end
    end
  end
end

---Internal: Emit event to all listeners
---@param event string
function Session:_emit(event)
  local listeners = self._event_listeners[event]
  if listeners then
    for _, fn in ipairs(listeners) do
      pcall(fn)
    end
  end
end

-- =============================================================================
-- LOADED SOURCE EVENT HANDLERS
-- =============================================================================

---Handle loadedSource "changed" event
---@param data dap.Source
---@private
function Session:_handle_source_changed(data)
  -- Compute correlation key for lookup
  local correlation_key = compute_correlation_key(data)

  -- Find existing source
  local source = self.debugger.sources:get_one("by_correlation_key", correlation_key)
  if not source then
    -- Treat as new if not found
    self:get_or_create_source(data)
    return
  end

  -- Update binding's sourceReference if changed
  local binding = self:_find_source_binding(source)
  if binding then
    if data.sourceReference then
      binding.sourceReference = data.sourceReference
    end
    if data.adapterData then
      binding.adapterData = data.adapterData
    end
  end

  -- Invalidate cached content so next fetch gets fresh data
  source:_invalidate_content()
end

---Handle loadedSource "removed" event - removes binding only, keeps Source
---@param data dap.Source
---@private
function Session:_handle_source_removed(data)
  local correlation_key = compute_correlation_key(data)

  -- Find and remove the binding for this session
  local binding = self.debugger.source_bindings:find(function(b)
    return b.session == self and b.source.correlation_key == correlation_key
  end)
  if binding then
    self.debugger.store:dispose_entity(binding.uri)
  end
end

---Find source binding for this session by source
---@param source Source
---@return SourceBinding?
---@private
function Session:_find_source_binding(source)
  for binding in self.debugger.source_bindings:iter() do
    if binding.session == self and binding.source == source then
      return binding
    end
  end
  return nil
end

-- =============================================================================
-- VARIABLES
-- =============================================================================

---Get filtered variables for this session
---@return table Filtered collection of variables
function Session:variables()
  if not self._variables then
    self._variables = self.debugger.variables:where(
      "by_session_id",
      self.id,
      "Variables:Session:" .. self.id
    )
  end
  return self._variables
end

---Register callback for variables in this session (existing + future)
---@param fn function  -- Called with (variable)
---@return function unsubscribe
function Session:onVariable(fn)
  return self:variables():each(fn)
end

---Get variable history by evaluateName (all values across stacks)
---Returns variables with the same evaluateName, ordered by stack sequence
---@param evaluate_name string  -- The evaluateName to search for
---@return table[]  -- Array of { stack_id, value, type, variable }
function Session:getVariableHistory(evaluate_name)
  local history = {}

  -- Use index to efficiently find all variables with this evaluateName in this session
  local matching_vars = self:variables():where("by_evaluate_name", evaluate_name)
  for var in matching_vars:iter() do
    table.insert(history, {
      stack_id = var.stack_id,
      value = var.value:get(),
      type = var.type:get(),
      is_current = var._is_current:get(),
      variable = var,
    })
  end

  return history
end

---Get current variable by evaluateName (from current stack only)
---@param evaluate_name string  -- The evaluateName to search for
---@return Variable?
function Session:getCurrentVariable(evaluate_name)
  -- Chain index filters: session variables -> current only -> by evaluate name
  local current_vars = self:variables():where("by_is_current", true)
  local matching_vars = current_vars:where("by_evaluate_name", evaluate_name)
  for var in matching_vars:iter() do
    return var  -- Return first match
  end
  return nil
end

-- =============================================================================
-- COMPLETIONS
-- =============================================================================

---Check if the debug adapter supports completions
---@return boolean
function Session:supportsCompletions()
  return self.capabilities and self.capabilities.supportsCompletionsRequest or false
end

---Get completion trigger characters (defaults to "." if not specified)
---@return string[]
function Session:completionTriggerCharacters()
  if self.capabilities and self.capabilities.completionTriggerCharacters then
    return self.capabilities.completionTriggerCharacters
  end
  return { "." }
end

---Get completions for text at cursor position
---@param text string  Text typed so far (e.g., "user.na")
---@param column integer  Cursor position within text (1-based)
---@param opts? { frameId?: number, line?: integer }  Optional frame scope and line
---@return string? error, dap.CompletionItem[]? completions
function Session:completions(text, column, opts)
  opts = opts or {}

  local result, err = neostate.settle(self.client:request("completions", {
    text = text,
    column = column,
    frameId = opts.frameId,
    line = opts.line,
  }))

  if err then
    return err, nil
  end

  if not result or not result.targets then
    return nil, {}
  end

  return nil, result.targets
end

-- =============================================================================
-- SESSION CONTROL
-- =============================================================================

---Check if the debug adapter supports terminate request
---@return boolean
function Session:supportsTerminate()
  return self.capabilities and self.capabilities.supportsTerminateRequest or false
end

---Gracefully terminate the debuggee (different from disconnect)
---Use terminate when you want to stop the debuggee but potentially restart it
---@param restart? boolean  -- Restart the debuggee after termination
---@return string? error
function Session:terminate(restart)
  if not self:supportsTerminate() then
    return "Adapter does not support terminate request"
  end

  local result, err = neostate.settle(self.client:request("terminate", {
    restart = restart or false,
  }))

  return err
end

-- =============================================================================
-- LOADED SOURCES
-- =============================================================================

---Check if the debug adapter supports loadedSources request
---@return boolean
function Session:supportsLoadedSources()
  return self.capabilities and self.capabilities.supportsLoadedSourcesRequest or false
end

---Fetch all sources currently loaded by the debugged process
---Returns Source entities (deduplicated via get_or_create_source)
---@return string? error, Source[]? sources
function Session:loadedSources()
  if not self:supportsLoadedSources() then
    return "Adapter does not support loadedSources request", nil
  end

  local result, err = neostate.settle(self.client:request("loadedSources", vim.empty_dict()))
  if err then
    return err, nil
  end

  if not result or not result.sources then
    return nil, {}
  end

  -- Convert DAP sources to Source entities (with deduplication)
  local sources = {}
  for _, dap_source in ipairs(result.sources) do
    local source = self:get_or_create_source(dap_source)
    table.insert(sources, source)
  end

  return nil, sources
end

-- =============================================================================
-- BREAKPOINT LOCATIONS
-- =============================================================================

---Check if the debug adapter supports breakpointLocations request
---@return boolean
function Session:supportsBreakpointLocations()
  return self.capabilities and self.capabilities.supportsBreakpointLocationsRequest or false
end

---Get possible breakpoint locations for a source range
---@param source dap.Source|{ path: string }  -- Source to query
---@param pos integer|integer[]                -- Start position (0-indexed line, or {line, col})
---@param end_pos? integer[]                   -- Optional end position {line, col} for range query
---@return string? error, { pos: integer[], end_pos?: integer[] }[]? locations
function Session:breakpointLocations(source, pos, end_pos)
  if not self:supportsBreakpointLocations() then
    return "Adapter does not support breakpointLocations request", nil
  end

  -- Normalize pos to {line, col} (0-indexed)
  local start_line, start_col
  if type(pos) == "number" then
    start_line = pos
    start_col = nil
  else
    start_line = pos[1]
    start_col = pos[2]
  end

  -- Build DAP request (1-indexed)
  local args = {
    source = source,
    line = start_line + 1,  -- Convert to 1-indexed
    column = start_col and (start_col + 1) or nil,
  }

  if end_pos then
    args.endLine = end_pos[1] + 1
    args.endColumn = end_pos[2] and (end_pos[2] + 1) or nil
  end

  local result, err = neostate.settle(self.client:request("breakpointLocations", args))

  if err then
    return err, nil
  end

  if not result or not result.breakpoints then
    return nil, {}
  end

  -- Convert DAP response to vim.Pos (0-indexed)
  local locations = {}
  for _, loc in ipairs(result.breakpoints) do
    local bp_loc = {
      pos = { loc.line - 1, (loc.column or 1) - 1 },  -- Convert to 0-indexed
    }
    if loc.endLine then
      bp_loc.end_pos = { loc.endLine - 1, (loc.endColumn or 1) - 1 }
    end
    table.insert(locations, bp_loc)
  end

  return nil, locations
end

-- =============================================================================
-- RESTART
-- =============================================================================

---Check if the debug adapter supports native restart request
---@return boolean
function Session:supportsRestart()
  return self.capabilities and self.capabilities.supportsRestartRequest == true
end

---Restart the debug session
---For native restart: uses DAP restart request (same session)
---For fallback: disconnects and creates a new session
---@param config? table  -- Optional updated launch/attach arguments
---@return Session new_session, string? error
function Session:restart(config)
  -- Emit restart hook on current session
  self:_emit("restart")

  if self:supportsRestart() then
    local err = self:_restart_native(config)
    return self, err
  else
    return self:_restart_via_new_session(config)
  end
end

---Native restart using DAP restart request (same session)
---@param config? table  -- Optional updated launch/attach arguments
---@return string? error
function Session:_restart_native(config)
  local args = {}
  if config then
    args.arguments = config
  end

  local _, err = neostate.settle(self.client:request("restart", args))
  if err then
    return err
  end

  -- Dispose ephemeral entities but keep session
  self:_dispose_ephemeral()
  self:_emit("restarted")
  return nil
end

---Fallback restart by creating a new session
---@param config? table  -- Optional updated launch/attach arguments
---@return Session new_session, string? error
function Session:_restart_via_new_session(config)
  -- Build restart config from stored launch args
  local restart_config = vim.tbl_deep_extend(
    "force",
    {},
    self._launch_args or {},
    config or {}
  )
  restart_config.__restart = true

  -- Preserve the logical type for the new session
  restart_config.type = self._logical_type

  -- Disconnect current session (this will dispose it)
  self:disconnect()

  -- Create new session via debugger
  local new_session = self.debugger:start(restart_config)

  -- Emit restarted on new session
  new_session:_emit("restarted")

  return new_session, nil
end

---Dispose ephemeral entities (threads, outputs) but keep session alive
---Used for native restart where session object persists
function Session:_dispose_ephemeral()
  -- Collect threads to delete (can't delete while iterating)
  -- Delete all threads for this session
  for thread in self:threads():iter() do
    self.debugger.store:dispose_entity(thread.uri)
  end

  -- Clear outputs
  for output in self:outputs():iter() do
    output:dispose()
  end

  -- Reset session state to running
  self.state:set("running")
end

---Disconnect and terminate session
---Can be called synchronously (fire-and-forget) or from async context
---@param terminate? boolean  -- Terminate debuggee (default: true)
function Session:disconnect(terminate)
  if terminate == nil then terminate = true end

  -- Fire and forget - disconnect doesn't need to wait for response
  self.client:request("disconnect", {
    terminateDebuggee = terminate,
  })
end

-- =============================================================================
-- VIEW API
-- =============================================================================

---Create a View over entities scoped to this session
---The view is pre-filtered by session_id for convenience.
---
---Example:
---  local stopped = session:view("thread"):where("by_state", "stopped")
---  stopped:each(function(thread) print(thread.name) end)
---  stopped:dispose()
---
---@param entity_type string Entity type (e.g., "thread", "frame", "binding")
---@return View View pre-filtered by session_id
function Session:view(entity_type)
  return self.debugger.store:view(entity_type):where("by_session_id", self.id)
end

M.Session = Session

-- Backwards compatibility for create()
function M.create(debugger, adapter_config, parent_session)
  return Session:new(debugger, adapter_config, parent_session)
end

return M
