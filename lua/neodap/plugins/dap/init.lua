-- DAP plugin - Debug Adapter Protocol integration for neodap
-- This file contains the core session management and event wiring.
-- Entity methods are split into separate files for maintainability.

local dap = require("dap-lua")
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
    for source_binding in session.sourceBindings:iter() do
      for bp_binding in source_binding.breakpointBindings:iter() do
        if bp_binding.hit:get() then
          bp_binding:update({ hit = false })
        end
      end
    end

    -- Mark hit breakpoints from hitBreakpointIds
    if body.hitBreakpointIds then
      for source_binding in session.sourceBindings:iter() do
        for bp_binding in source_binding.breakpointBindings:iter() do
          local bp_id = bp_binding.breakpointId:get()
          for _, hit_id in ipairs(body.hitBreakpointIds) do
            if bp_id == hit_id then
              bp_binding:update({ hit = true })
              log:info("Breakpoint hit: " .. bp_binding.uri:get())
              break
            end
          end
        end
      end
    end

    -- Update thread state if threadId provided
    if body.threadId then
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

      -- Try to update existing thread, or fetch threads first if not found
      local thread = session:findThreadById(body.threadId)
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
  end)

  dap_session:on("continued", function(body)
    session:update({ state = "running" })
    log:info("Session continued: " .. session.uri:get())

    -- Clear hit states when continuing
    for source_binding in session.sourceBindings:iter() do
      for bp_binding in source_binding.breakpointBindings:iter() do
        if bp_binding.hit:get() then
          bp_binding:update({ hit = false })
        end
      end
    end

    -- Update thread state if threadId provided
    if body.threadId then
      local thread = session:findThreadById(body.threadId)
      if thread then
        thread:update({ state = "running" })
        log:info("Thread continued: " .. thread.uri:get())
      end
    end
  end)

  dap_session:on("terminated", function(body)
    session:update({ state = "terminated" })
    log:info("Session terminated: " .. session.uri:get())
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
    -- This causes breakpoint signs to update (verified -> unverified)
    cleanup_session_bindings(session)
    -- Auto-close transport if adapter terminated unexpectedly (not user-initiated)
    -- Skip if user called terminate/disconnect (user_closing = true) since
    -- those methods handle client cleanup themselves
    if not user_closing and dap_session.client and not dap_session.client.is_closing() then
      dap_session.client:close()
    end
  end)

  dap_session:on("exited", function(body)
    session:update({ state = "terminated" })
    log:info("Session exited: " .. session.uri:get())
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
    -- Auto-close transport if debuggee exited unexpectedly (not user-initiated)
    -- Skip if user called terminate/disconnect (user_closing = true) since
    -- those methods handle client cleanup themselves
    if not user_closing and dap_session.client and not dap_session.client.is_closing() then
      dap_session.client:close()
    end
  end)

  -- Closing event fires when disconnect/terminate is called, before actual disconnect
  -- This ensures focus is cleared even if adapter doesn't send terminated event
  dap_session:on("closing", function()
    -- Mark that user initiated termination so we don't auto-close in terminated/exited handlers
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
    -- Clean up bindings as safety net (in case terminated/exited not received)
    cleanup_session_bindings(session)
  end)

  dap_session:on("thread", function(body)
    local graph = session._graph
    local thread_id = body.threadId

    if body.reason == "started" then
      -- Check if thread already exists
      local existing = session:findThreadById(thread_id)

      if not existing then
        -- Create new thread - fetch full info from adapter
        local session_id = session.sessionId:get()
        dap_session.client:request("threads", {}, function(err, threads_body)
          if err then return end

          for _, thread_data in ipairs(threads_body.threads or {}) do
            if thread_data.id == thread_id then
              local thread = entities.Thread.new(graph, {
                uri = uri.thread(session_id, thread_data.id),
                threadId = thread_data.id,
                name = thread_data.name,
                state = "running",
                stops = 0,
              })
              -- Use vim.schedule to ensure edge callbacks fire in the main loop
              -- IMPORTANT: Only call the forward link (session.threads:link) - neograph-native
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
      end

    elseif body.reason == "exited" then
      -- Find and update thread state
      local thread = session:findThreadById(thread_id)
      if thread then
        log:info("Thread exited: " .. thread.uri:get())
        thread:update({ state = "exited" })
      end
    end
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

    -- Create SourceBinding for this session if sourceReference is present
    local source_ref = dap_source.sourceReference or 0

    -- Check if binding already exists
    local binding_exists = false
    for binding in source.bindings:iter() do
      local bound_session = binding.session:get()
      if bound_session == session then
        -- Update existing binding
        binding:update({ sourceReference = source_ref })
        binding_exists = true
        break
      end
    end

    if not binding_exists then
      -- Create new SourceBinding
      local binding = entities.SourceBinding.new(graph, {
        uri = uri.sourceBinding(session.sessionId:get(), source.key:get()),
        sourceReference = source_ref,
      })
      source.bindings:link(binding)
      session.sourceBindings:link(binding)

      -- Sync any existing breakpoints to this new binding
      local has_breakpoints = source.breakpoints:iter()() ~= nil
      if has_breakpoints then
        binding:syncBreakpoints()
      end
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

    -- Search through all sourceBindings to find the best matching breakpointBinding
    for sourceBinding in session.sourceBindings:iter() do
      for bpBinding in sourceBinding.breakpointBindings:iter() do
        if bpBinding.breakpointId:get() == bp_data.id then
          -- Get the original breakpoint line for this binding
          local bp = bpBinding.breakpoint:get()
          local bp_line = bp and bp.line:get()

          if bp_line and bp_data.line then
            -- Find binding whose breakpoint line is closest to the event's line
            local distance = math.abs(bp_line - bp_data.line)
            if distance < best_distance then
              best_distance = distance
              best_binding = bpBinding
            end
          elseif not best_binding then
            -- Fallback: use first match if no line info available
            best_binding = bpBinding
          end
        end
      end
    end

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
---@param opts { adapter?: table, config: table, handlers?: table, config_entity?: table, parent_task_id?: number }
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

  -- Track adapter task for the current session being created
  local current_adapter_task_id = nil

  -- Build handlers with backend integration
  local handlers = vim.tbl_extend("force", opts.handlers or {}, {
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

    -- Called when backend spawns/connects adapter process
    onAdapterProcess = function(process)
      current_adapter_task_id = process.task_id
    end,

    -- Called when a dap_session is created (before initialization)
    -- This fires for ALL sessions (root and child)
    onSessionCreated = function(dap_session)
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

      local new_session = entities.Session.new(graph, {
        uri = uri.session(new_sessionId),
        sessionId = new_sessionId,
        name = dap_session.config.name or dap_session.config.type or (parent_session and "child" or "session"),
        state = "starting",
        leaf = true,
        adapterTaskId = current_adapter_task_id,
        logDir = log_dir,
        fallbackFiletype = fallback_ft,
      })

      -- Reset for next session
      current_adapter_task_id = nil

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

      log:info("Session created: " .. new_session.uri:get())

      -- Store root session for return value
      if not parent_session then
        root_session = new_session
      end
    end,

    -- Sync breakpoints before configurationDone
    beforeConfigurationDone = function(dap_session, done)
      local function sync_breakpoints()
        -- Session ALWAYS exists (created in onSessionCreated)
        local current_session = session_entities[dap_session]
        local current_sessionId = current_session.sessionId:get()

        -- Create exception filters from capabilities (now available)
        create_exception_filters(graph, self, current_session, dap_session.capabilities)

        -- Collect sources that have breakpoints
        local sources_with_breakpoints = {}
        for source in self.sources:iter() do
          for _ in source.breakpoints:iter() do
            table.insert(sources_with_breakpoints, source)
            break
          end
        end

        if #sources_with_breakpoints == 0 then
          return
        end

        -- Sync each source's breakpoints to the session in parallel
        -- Uses SourceBinding:syncBreakpoints() which handles all the sync logic
        a.wait_all(vim.tbl_map(function(source)
          return a.run(function()
            -- Find or create SourceBinding for this session
            local binding = nil
            for b in source.bindings:iter() do
              if b.session:get() == current_session then
                binding = b
                break
              end
            end

            if not binding then
              binding = entities.SourceBinding.new(graph, {
                uri = uri.sourceBinding(current_sessionId, source.key:get()),
                sourceReference = 0,
              })
              source.bindings:link(binding)
              current_session.sourceBindings:link(binding)
            end

            binding:syncBreakpoints()
          end)
        end, sources_with_breakpoints), "beforeConfigurationDone:sync")
      end
      a.fn(sync_breakpoints)()
      done()
    end,
  })

  -- Start DAP session with backend for process management
  -- The backend handles stdio, tcp, and server adapters uniformly
  DapSession.create({
    adapter = adapter,
    config = opts.config,
    handlers = handlers,
    backend = backend,
  }, function(err, dap_session)
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
  end)

  return root_session
end

---Plugin entry point
---@param debugger neodap.entities.Debugger
---@return neodap.plugins.dap
return function(debugger)
  return M
end
