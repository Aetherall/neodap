-- DAP plugin - Debug Adapter Protocol integration for neodap
-- This file contains the core session management and event wiring.
-- Entity methods are split into separate files for maintainability.

local DapSession = require("dap-lua.session")
local entities = require("neodap.entities")
local neoword = require("neoword")
local uri = require("neodap.uri")
local a = require("neodap.async")
local backends = require("neodap.backends")
local log = require("neodap.logger")

-- Import shared context and utilities
local context = require("neodap.plugins.dap.context")
local utils = require("neodap.plugins.dap.utils")

-- Import entity method modules (they attach methods to entity prototypes)
require("neodap.plugins.dap.thread")
require("neodap.plugins.dap.frame")
require("neodap.plugins.dap.scope")
require("neodap.plugins.dap.variable")
require("neodap.plugins.dap.output")
require("neodap.plugins.dap.source")
require("neodap.plugins.dap.breakpoint")
require("neodap.plugins.dap.session")

local Debugger = entities.Debugger

---@class neodap.plugins.dap
local M = {}

-- Local aliases for performance
local get_or_create_source = utils.get_or_create_source
local cleanup_session_bindings = utils.cleanup_session_bindings
local create_exception_filters = utils.create_exception_filters

local dap_sessions = context.dap_sessions
local session_entities = context.session_entities
local output_seqs = context.output_seqs
local next_global_seq = context.next_global_seq

---Find the SourceBinding for a session within a source's bindings, or create one.
---@param graph table The neograph instance
---@param source neodap.entities.Source
---@param session_entity neodap.entities.Session
---@return neodap.entities.SourceBinding binding
---@return boolean created Whether the binding was newly created
local function find_or_create_binding(graph, source, session_entity)
  for b in source.bindings:iter() do
    if b.session:get() == session_entity then
      return b, false
    end
  end
  local binding = entities.SourceBinding.new(graph, {
    uri = uri.sourceBinding(session_entity.sessionId:get(), source.key:get()),
    sourceReference = 0,
  })
  source.bindings:link(binding)
  session_entity.sourceBindings:link(binding)
  return binding, true
end

---Subscribe to DapSession events and update Session entity state
---@param session neodap.entities.Session
---@param dap_session DapSession
local function wire_session_events(session, dap_session)
  -- Track if user-initiated termination is in progress
  -- "closing" event fires when dap_session:terminate() or :disconnect() is called
  local user_closing = false

  dap_session:on("stopped", function(body)
    session:update({ state = "stopped" })
    log:info("Session stopped: " .. session.uri:get())

    -- Clear previous hit states for this session's bindings
    session:clearHitBreakpoints()

    -- Mark hit breakpoints from hitBreakpointIds
    if body.hitBreakpointIds and #body.hitBreakpointIds > 0 then
      local hit_set = {}
      for _, id in ipairs(body.hitBreakpointIds) do
        hit_set[id] = true
      end
      session:forEachBreakpointBinding(function(bpb)
        if hit_set[bpb.breakpointId:get()] then
          bpb:update({ hit = true })
          log:info("Breakpoint hit: " .. bpb.uri:get())
        end
      end)
    end

    -- Helper to update thread when found
    local function update_thread_stopped(thread)
      -- Increment stop sequence (new stop = new potential stack)
      thread:update({ state = "stopped", stops = (thread.stops:get() or 0) + 1 })
      log:info("Thread stopped: " .. thread.uri:get())

      -- Auto-fetch stack trace if enabled (default: true)
      if vim.g.neodap__autofetch_stack ~= false then
        thread:fetchStackTrace()
      end
    end

    -- Update thread state if threadId provided
    local thread = nil
    if body.threadId then
      -- Try to update existing thread, or fetch threads first if not found
      thread = session:findThreadById(body.threadId)
      if thread then
        update_thread_stopped(thread)
      else
        -- Thread doesn't exist yet - fetch threads, then update
        a.run(function()
          session:fetchThreads()
          local fetched_thread = session:findThreadById(body.threadId)
          if fetched_thread then
            update_thread_stopped(fetched_thread)
          end
        end)
      end
    end

    -- DAP spec: allThreadsStopped means ALL threads should be marked stopped
    if body.allThreadsStopped then
      for t in session.threads:iter() do
        if t ~= thread and t.state:get() ~= "stopped" then
          update_thread_stopped(t)
        end
      end
    end
  end)

  dap_session:on("continued", function(body)
    session:update({ state = "running" })
    log:info("Session continued: " .. session.uri:get())

    -- Clear hit states when continuing
    session:clearHitBreakpoints()

    -- Update thread state if threadId provided
    if body.threadId then
      local thread = session:findThreadById(body.threadId)
      if thread then
        thread:update({ state = "running" })
        log:info("Thread continued: " .. thread.uri:get())
      end
    end

    -- DAP spec: allThreadsContinued means ALL threads should be marked running
    if body.allThreadsContinued then
      for thread in session.threads:iter() do
        if thread.state:get() ~= "running" then
          thread:update({ state = "running" })
          log:info("Thread continued (all): " .. thread.uri:get())
        end
      end
    end
  end)

  ---Handle session end (shared by terminated and exited events)
  ---@param reason string "terminated" or "exited"
  local function handle_session_end(reason)
    session:update({ state = "terminated" })
    log:info("Session " .. reason .. ": " .. session.uri:get())
    -- Clear focus if this was the focused session
    local debugger = session.debugger:get()
    if debugger then
      local focused = debugger.ctx.session:get()
      if focused == session then
        debugger.ctx:focus("")
      end
    end
    -- Update Config state (may become terminated if all sessions are done)
    local cfg = session.config:get()
    if cfg then
      cfg:updateState()
    end
    -- Clean up all bindings for this session
    cleanup_session_bindings(session)
    -- Auto-close transport if adapter ended unexpectedly (not user-initiated)
    if not user_closing and dap_session.client and not dap_session.client.is_closing() then
      dap_session.client:close()
    end
  end

  dap_session:on("terminated", function() handle_session_end("terminated") end)
  dap_session:on("exited", function() handle_session_end("exited") end)

  -- Closing event fires when disconnect/terminate is called, before actual disconnect
  -- This ensures focus is cleared even if adapter doesn't send terminated event
  dap_session:on("closing", function()
    user_closing = true
    local debugger = session.debugger:get()
    if debugger then
      local focused = debugger.ctx.session:get()
      if focused == session then
        debugger.ctx:focus("")
      end
    end
    -- Kill terminal processes only on terminate (not disconnect, which keeps processes alive)
    if context.terminating_sessions[dap_session] then
      context.terminating_sessions[dap_session] = nil
      context.kill_terminal_tasks(session)
    end
    -- Stop the supervisor process tree immediately.
    -- This fires before the disconnect request is sent, so the adapter gets killed
    -- and the TCP connection drops — unblocking any pending requests.
    -- Without this, the disconnect request can hang if the adapter doesn't respond.
    context.stop_supervisor(session)
    -- Clean up bindings as safety net (in case terminated/exited not received)
    cleanup_session_bindings(session)
  end)

  dap_session:on("process", function(body)
    if body.systemProcessId then
      session:update({ pid = body.systemProcessId })
      log:info("Process started: " .. (body.name or "?") .. " (pid " .. body.systemProcessId .. ")")
    end
  end)

  dap_session:on("thread", function(body)
    local graph = session._graph
    local thread_id = body.threadId

    if body.reason == "exited" then
      local thread = session:findThreadById(thread_id)
      if thread then
        log:info("Thread exited: " .. thread.uri:get())
        thread:update({ state = "exited" })
      end
      return
    end

    if body.reason ~= "started" then return end
    if session:findThreadById(thread_id) then return end

    -- Fetch full thread info from adapter
    local session_id = session.sessionId:get()
    dap_session.client:request("threads", {}, function(err, threads_body)
      if err then return end
      -- Race guard: thread may have been created by a concurrent stopped event
      if session:findThreadById(thread_id) then return end

      for _, thread_data in ipairs(threads_body.threads or {}) do
        if thread_data.id == thread_id then
          local thread = entities.Thread.new(graph, {
            uri = uri.thread(session_id, thread_data.id),
            threadId = thread_data.id,
            name = thread_data.name,
            state = "running",
            stops = 0,
          })
          -- IMPORTANT: Only call the forward link (session.threads:link) — neograph-native
          -- creates the inverse automatically. Calling inverse first would not notify
          -- forward edge subscribers (neograph-native limitation).
          vim.schedule(function()
            session.threads:link(thread)
            log:info("Thread created: " .. thread.uri:get())
          end)
          break
        end
      end
    end)
  end)

  dap_session:on("loadedSource", function(body)
    local graph = session._graph

    -- Get debugger for source storage
    local debugger = session.debugger:get()
    if not debugger then return end

    local dap_source = body.source
    if not dap_source then return end

    -- Get or create the Source entity
    local source = get_or_create_source(graph, debugger, dap_source, session)
    if not source then return end

    -- Find or create SourceBinding for this session
    local source_ref = dap_source.sourceReference or 0
    local binding, created = find_or_create_binding(graph, source, session)
    binding:update({ sourceReference = source_ref })

    -- Sync any existing breakpoints to a newly created binding
    if created and (source.breakpointCount:get() or 0) > 0 then
      binding:syncBreakpoints()
    end
  end)

  dap_session:on("breakpoint", function(body)
    -- Find the BreakpointBinding by breakpointId and update it
    -- Note: Some adapters (js-debug) may return the same id for multiple breakpoints,
    -- so we find the best match by comparing the event's line to each binding's original breakpoint line
    local bp_data = body.breakpoint
    if not bp_data or not bp_data.id then return end

    local best_binding = nil
    local best_distance = math.huge

    -- Search through all breakpointBindings to find the best match
    session:forEachBreakpointBinding(function(bpBinding)
      if bpBinding.breakpointId:get() == bp_data.id then
        local bp = bpBinding.breakpoint:get()
        local bp_line = bp and bp.line:get()

        if bp_line and bp_data.line then
          local distance = math.abs(bp_line - bp_data.line)
          if distance < best_distance then
            best_distance = distance
            best_binding = bpBinding
          end
        elseif not best_binding then
          best_binding = bpBinding
        end
      end
    end)

    if best_binding then
      best_binding:update({
        verified = bp_data.verified or false,
        message = bp_data.message,
        actualLine = bp_data.line,
        actualColumn = bp_data.column,
      })
    end
  end)

  -- Handle child sessions (e.g., js-debug startDebugging)
  -- Note: Session entity was created in onSessionCreated, breakpoints synced in beforeConfigurationDone
  dap_session:on("child", function(child_dap_session)
    local child_session = session_entities[child_dap_session]
    if child_session then
      -- Child initialization complete, mark as running
      child_session:update({ state = "running" })
    end
  end)

  -- DAP spec: invalidated event signals stale data that should be refetched
  dap_session:on("invalidated", function(body)
    local areas = body.areas or {}
    local thread_id = body.threadId

    -- If specific areas are listed, only refetch those
    local refetch_stacks = #areas == 0  -- no areas = refetch everything
    local refetch_variables = #areas == 0
    for _, area in ipairs(areas) do
      if area == "stacks" then refetch_stacks = true end
      if area == "variables" then refetch_variables = true end
      if area == "all" then
        refetch_stacks = true
        refetch_variables = true
      end
    end

    if refetch_stacks then
      -- Refetch stack traces for affected threads
      if thread_id then
        local thread = session:findThreadById(thread_id)
        if thread and thread.state:get() == "stopped" then
          thread:fetchStackTrace()
        end
      else
        -- Refetch for all stopped threads (uses indexed collection)
        for thread in session.stoppedThreads:iter() do
          thread:fetchStackTrace()
        end
      end
    end

    if refetch_variables then
      log:debug("Invalidated event: variables area (refetch on next expand)")
      -- Variables will be refetched on next scope expand/variable expand
      -- No proactive refetch needed since the tree view lazily fetches on expand
    end
  end)

  -- Initialize output sequence for this session
  output_seqs[session] = 0

  dap_session:on("output", function(body)
    local text = (body.output or ""):gsub("\n", "\\n"):sub(1, 100)
    log:debug("Output event: " .. session.sessionId:get() .. " [" .. (body.category or "?") .. "] " .. text)

    local graph = session._graph
    local session_id = session.sessionId:get()

    output_seqs[session] = (output_seqs[session] or 0) + 1
    local seq = output_seqs[session]

    -- visible = false for telemetry, true otherwise (used by console view filtering)
    local is_visible = body.category ~= "telemetry"

    local output = entities.Output.new(graph, {
      uri = uri.output(session_id, seq),
      seq = seq,
      globalSeq = next_global_seq(),
      text = body.output,
      category = body.category,
      group = body.group,
      line = body.line,
      column = body.column,
      variablesReference = body.variablesReference,
      visible = is_visible,
      matched = true,
    })

    session.outputs:link(output)

    -- Append to log file on disk (skip telemetry)
    local log_dir = session.logDir:get()
    if log_dir and body.output and is_visible then
      local log_file = log_dir .. "/output.log"
      local f = io.open(log_file, "a")
      if f then
        f:write(body.output)
        f:close()
      end
    end

    -- Link to allOutputs for this session, propagate to ancestors and descendants
    session.allOutputs:link(output)
    -- Propagate upward to all ancestor sessions
    local ancestor = session.parent and session.parent:get()
    while ancestor do
      ancestor.allOutputs:link(output)
      ancestor = ancestor.parent and ancestor.parent:get()
    end
    -- Propagate downward to all descendant sessions
    local function propagate_to_descendants(sess)
      for child in sess.children:iter() do
        child.allOutputs:link(output)
        propagate_to_descendants(child)
      end
    end
    propagate_to_descendants(session)

    -- Link to source if provided
    if body.source then
      local debugger_entity = session.debugger:get()
      if debugger_entity then
        local source = get_or_create_source(graph, debugger_entity, body.source, session)
        if source then
          source.outputs:link(output)
        end
      end
    end
  end)
end

---Start a debug session using the backend for process management
---@param self neodap.entities.Debugger
---@param opts { adapter?: table, config: table, handlers?: table, config_entity?: table, parent_task_id?: number, process_handle?: table, child_adapter?: table, _supervisor_handle?: table }
---@return neodap.entities.Session
function Debugger:debug(opts)
  log:info("debug() called", { name = opts.config and opts.config.name, type = opts.config and opts.config.type })
  local graph = self._graph
  local debugger = self
  local backend = backends.get_backend()

  -- Auto-resolve adapter from config.type if not provided
  local adapter = opts.adapter
  if not adapter then
    local type_name = opts.config and opts.config.type
    if type_name then
      local neodap = require("neodap")
      adapter = neodap.config.adapters[type_name]
      if not adapter then
        error(string.format("No adapter configured for type '%s'. Add it to neodap.setup({ adapters = { ... } })", type_name))
      end
      -- Call function adapters to get the actual config
      if type(adapter) == "function" then
        adapter = adapter(opts.config)
      end
      -- Allow adapter to transform config before launch
      if adapter.on_config then
        opts.config = adapter.on_config(opts.config) or opts.config
      end
    else
      error("opts.adapter or opts.config.type required")
    end
  end

  -- Session will be created in onSessionCreated hook
  local root_session = nil

  -- Track the most recently created dap_session so onAdapterProcess can find its entity.
  -- onSessionCreated always fires BEFORE onAdapterProcess in dap-lua's M.create():
  --   1. session object created (line 85)
  --   2. onSessionCreated(session) fires (line 114)
  --   3. backend.spawn() / backend.connect() runs (line 424+)
  --   4. onAdapterProcess(process) fires (line 434/486)
  -- So by the time onAdapterProcess runs, the entity already exists in session_entities.
  local last_dap_session = nil

  -- Build handlers with backend integration
  -- Declare before assignment so closures inside can reference it
  local handlers
  handlers = vim.tbl_extend("force", opts.handlers or {}, {
    -- runInTerminal using backend
    runInTerminal = function(dap_session, args, callback)
      local task = backend.run_in_terminal({
        args = args.args or {},
        cwd = args.cwd,
        env = args.env,
        kind = args.kind,
        title = args.title,
      })
      -- Store terminal buffer on session entity for console_buffer to use
      local session_entity = session_entities[dap_session]
      if session_entity then
        if task.bufnr then
          session_entity:update({ terminalBufnr = task.bufnr })
        end
        -- Store task handle so we can kill the process on session terminate
        context.add_terminal_task(session_entity, task)
      end
      callback(nil, { processId = task.pid })
    end,

    -- Called when backend spawns/connects adapter process (AFTER onSessionCreated)
    onAdapterProcess = function(process)
      -- Update the session entity that was just created by onSessionCreated.
      -- For stdio/server adapters: process.pid is the adapter PID.
      -- For tcp adapters (child sessions): process.pid is nil (TCP socket, not a process),
      -- so we skip the update — children inherit adapterPid from parent in onSessionCreated.
      if process.pid then
        local session_entity = last_dap_session and session_entities[last_dap_session]
        if session_entity then
          session_entity:update({
            adapterTaskId = process.task_id,
            adapterPid = process.pid,
          })
        end
      end
    end,

    -- Called when a dap_session is created (before initialization)
    -- This fires for ALL sessions (root and child)
    onSessionCreated = function(dap_session)
      last_dap_session = dap_session
      local parent_session = dap_session.parent and session_entities[dap_session.parent]

      local new_sessionId = neoword.generate()
      -- Store session ID on dap_session so backend can use it for buffer URIs
      dap_session.neodap_session_id = new_sessionId

      -- Create temp directory for session logs
      local log_dir = vim.fn.tempname() .. "-neodap-" .. new_sessionId
      vim.fn.mkdir(log_dir, "p")

      -- Get fallbackFiletype from adapter config (for virtual sources)
      local fallback_ft = adapter and adapter.fallbackFiletype
      -- Child sessions inherit from parent if not set
      if not fallback_ft and parent_session then
        fallback_ft = parent_session.fallbackFiletype:get()
      end

      -- Resolve adapterPid:
      -- 1. Supervisor path: handlers._supervisor_handle has the shim PID
      -- 2. Child sessions: inherit from parent
      -- 3. Backend path: set later by onAdapterProcess
      local sup = handlers._supervisor_handle
      local adapter_pid = (sup and sup.pid)
        or (parent_session and parent_session.adapterPid:get())
        or nil

      local new_session = entities.Session.new(graph, {
        uri = uri.session(new_sessionId),
        sessionId = new_sessionId,
        name = dap_session.config.name or dap_session.config.type or (parent_session and "child" or "session"),
        state = "starting",
        leaf = true,
        adapterPid = adapter_pid,
        logDir = log_dir,
        fallbackFiletype = fallback_ft,
      })

      -- Create Stdio intermediate node for outputs
      local stdio = entities.Stdio.new(graph, {
        uri = uri.stdio(new_sessionId),
      })
      new_session.stdios:link(stdio)

      -- Create Threads intermediate node for threads (UI grouping)
      local threadGroup = entities.Threads.new(graph, {
        uri = uri.threads(new_sessionId),
      })
      new_session.threadGroups:link(threadGroup)

      -- Maintain parent/children edges for hierarchy
      if parent_session then
        -- Update parent leaf status BEFORE linking child to sessions
        -- This ensures leafSessionCount never double-counts
        parent_session:update({ leaf = false })
        parent_session.children:link(new_session)

        -- Copy parent's allOutputs to child session so child can see ancestor outputs
        for output in parent_session.allOutputs:iter() do
          new_session.allOutputs:link(output)
        end

        -- Inherit Config from parent (propagation)
        local parent_config = parent_session.config:get()
        if parent_config then
          parent_config.sessions:link(new_session)
          -- isConfigRoot stays false (default) for child sessions
        end
      else
        -- Root sessions also go in rootSessions (for tree display)
        debugger.rootSessions:link(new_session)

        -- Link to Config entity if provided (root sessions are config roots)
        if opts.config_entity then
          new_session:update({ isConfigRoot = true })
          opts.config_entity.sessions:link(new_session)
        end
      end

      -- All sessions go in debugger.sessions (SDK consistency)
      debugger.sessions:link(new_session)
      dap_sessions[new_session] = dap_session
      session_entities[dap_session] = new_session
      wire_session_events(new_session, dap_session)

      -- Store supervisor handle for lifecycle management.
      -- Root sessions get it from handlers._supervisor_handle.
      -- Child sessions inherit from parent so that disconnecting any session
      -- in the tree will stop the supervisor (kill the adapter process group).
      local sup_handle = handlers._supervisor_handle
        or (parent_session and context.supervisor_handles[parent_session])
      if sup_handle then
        context.set_supervisor_handle(new_session, sup_handle)
      end

      log:info("Session created: " .. new_session.uri:get())

      -- Store root session for return value
      if not parent_session then
        root_session = new_session
      end
    end,

    -- Sync breakpoints before configurationDone
    beforeConfigurationDone = function(dap_session, done)
      -- Session ALWAYS exists (created in onSessionCreated)
      local current_session = session_entities[dap_session]
      local current_sessionId = current_session.sessionId:get()

      -- Create exception filters from capabilities (now available)
      create_exception_filters(graph, self, current_session, dap_session.capabilities)

      -- Collect sources that have breakpoints
      local sources_with_breakpoints = {}
      for source in self.sources:iter() do
        if (source.breakpointCount:get() or 0) > 0 then
          table.insert(sources_with_breakpoints, source)
        end
      end

      if #sources_with_breakpoints == 0 then
        done()  -- No breakpoints, signal done immediately
        return
      end

      -- Sync breakpoints async, then signal done
      a.run(function()
        a.wait_all(vim.tbl_map(function(source)
          return a.run(function()
            local binding = find_or_create_binding(graph, source, current_session)
            binding:syncBreakpoints()
          end)
        end, sources_with_breakpoints), "beforeConfigurationDone:sync")
        done()
      end)
    end,
  })

  -- Common callback for DapSession.create
  local function on_session_created(err, dap_session)
    if err then
      log:error(err)
      if root_session then
        root_session:update({ state = "terminated" })
      end
      return
    end

    -- Session is ready (mappings and events already wired in onSessionCreated)
    if root_session then
      root_session:update({ state = "running" })
      log:info("Session started: " .. root_session.uri:get())
    end
  end

  -- Pre-made process handle path: caller already spawned the adapter and connected.
  -- Used by compound launches where the compound supervisor manages the process tree.
  if opts.process_handle then
    -- Store supervisor handle if provided
    if opts._supervisor_handle then
      handlers._supervisor_handle = opts._supervisor_handle
    end

    DapSession.create({
      process_handle = opts.process_handle,
      config = opts.config,
      handlers = handlers,
      child_adapter = opts.child_adapter,
      backend = backend,
    }, on_session_created)

    return root_session
  end

  -- Server adapters: use supervisor for process group management.
  -- The supervisor spawns the adapter in a shell shim that owns a process group,
  -- redirects stdout/stderr to files, and provides signal-based lifecycle control.
  -- Once the adapter announces its port, we connect via TCP and create the DAP session.
  if adapter.type == "server" and adapter.command then
    local supervisor = require("neodap.supervisor")
    local session_name = opts.config.name or opts.config.type or "debug"

    supervisor.launch_config({
      name = session_name,
      command = adapter.command,
      args = adapter.args,
      env = adapter.env,
      cwd = adapter.cwd,
      connect_condition = adapter.connect_condition,
    }, function(err, sup_handle, port, host)
      if err then
        log:error("Supervisor launch failed: " .. tostring(err))
        return
      end

      host = host or adapter.host or "127.0.0.1"
      log:info("Supervisor: adapter ready", { name = session_name, pid = sup_handle.pid, port = port, host = host })

      -- Store supervisor handle on the handlers for access during session lifecycle
      handlers._supervisor_handle = sup_handle

      -- Connect to adapter via TCP, then create DAP session.
      -- Pass child_adapter so startDebugging children connect to the same server.
      local tcp_handle = require("neodap.session").connect_tcp({
        host = host,
        port = port,
        retries = 5,
        retry_delay = 100,
      })

      -- When TCP connection closes, stop the supervisor (kills process group)
      tcp_handle.on_exit(function()
        sup_handle.stop()
      end)

      DapSession.create({
        process_handle = tcp_handle,
        config = opts.config,
        handlers = handlers,
        child_adapter = { type = "tcp", host = host, port = port },
        backend = backend,
      }, on_session_created)
    end)

    return root_session
  end

  -- Non-server adapters: use existing backend path (stdio, tcp)
  DapSession.create({
    adapter = adapter,
    config = opts.config,
    handlers = handlers,
    backend = backend,
  }, on_session_created)

  return root_session
end

---Plugin entry point
---@param debugger neodap.entities.Debugger
---@return neodap.plugins.dap
return function(debugger)
  return M
end
