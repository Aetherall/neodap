local dap = require("dap-lua")
local log = require("neolog").new("dap-lua")

local M = {}

---@class DapSession
---@field client DapClient
---@field parent DapSession? Parent session (nil for root sessions)
---@field children DapSession[] Child sessions spawned via startDebugging
---@field depth number Session depth (0 for root, increments for children)
---@field capabilities dap.Capabilities
---@field config table
---@field on fun(self: DapSession, event: string, handler: fun(...))
---@field disconnect fun(self: DapSession, callback?: fun(err: string?))
---@field terminate fun(self: DapSession, callback?: fun(err: string?))

---@class DapSessionOpts
---@field adapter DapAdapter|{ type: "stdio"|"tcp"|"server", command?: string, args?: string[], cwd?: string, env?: table, host?: string, port?: number, connect_condition?: fun(chunk: string): number?, string? }
---@field config { request: "launch"|"attach", [string]: any }
---@field handlers? { runInTerminal?: fun(session: DapSession, args: dap.RunInTerminalRequestArguments, callback: fun(err: string?, response: dap.RunInTerminalResponse?)), onAdapterProcess?: fun(process: neodap.ProcessHandle) }
---@field parent? DapSession Parent session (internal, set automatically for child sessions)
---@field client? DapClient Pre-created client (bypasses adapter:connect())
---@field process_handle? neodap.ProcessHandle Backend process handle (creates client from process)
---@field backend? neodap.TaskBackend Backend for process management (uses backend instead of dap-lua adapters)

--- Default runInTerminal handler using vim.system
---@param session DapSession The session that requested the terminal
---@param args dap.RunInTerminalRequestArguments
---@param callback fun(err: string?, response: dap.RunInTerminalResponse?)
local function default_run_in_terminal(session, args, callback)
  local cmd = args.args or {}
  local cwd = args.cwd
  local env = args.env

  -- Build environment table
  local env_table = nil
  if env then
    env_table = vim.tbl_extend("force", vim.fn.environ(), env)
  end

  local handle = vim.system(cmd, {
    cwd = cwd,
    env = env_table,
    detach = true,
  }, function() end)

  -- vim.system doesn't expose PID directly, return nil
  -- The adapter will use other means to track the process
  vim.schedule(function()
    callback(nil, { processId = handle.pid })
  end)
end

-- Maximum depth for child sessions to prevent infinite recursion
local MAX_SESSION_DEPTH = 5

---@param opts DapSessionOpts
---@param callback fun(err: string?, session: DapSession?)
---@param depth? number Internal: current session depth
function M.create(opts, callback, depth)
  depth = depth or 0
  if depth > MAX_SESSION_DEPTH then
    callback("Maximum session depth exceeded", nil)
    return
  end

  -- Keep original adapter config for backend path
  local adapter = opts.adapter
  local adapter_config = nil
  if type(adapter) == "table" and adapter.type then
    -- It's a config - save it for backend path before converting
    adapter_config = adapter
  end

  -- For child sessions: may be updated to TCP adapter after server connects
  local child_adapter = adapter
  local config = opts.config
  local handlers = opts.handlers or {}
  local parent = opts.parent

  -- Event handlers (defined early so session:on is available in onSessionCreated)
  local event_handlers = {}

  -- Session state
  local session = {
    client = nil,
    parent = parent,
    children = {},
    capabilities = nil,
    config = config,
    depth = depth,
    adapter_task_id = nil,  -- Overseer task ID for visual hierarchy
  }

  ---@param event string
  ---@param handler fun(...)
  function session:on(event, handler)
    event_handlers[event] = event_handlers[event] or {}
    table.insert(event_handlers[event], handler)
  end

  local function emit(event, ...)
    local hs = event_handlers[event]
    if hs then
      for _, h in ipairs(hs) do
        h(...)
      end
    end
  end

  -- Call onSessionCreated hook before initialization starts
  -- This allows callers to set up state (e.g., create neodap Session entity)
  -- session:on is available at this point for registering event handlers
  if handlers.onSessionCreated then
    handlers.onSessionCreated(session)
  end

  -- Forward client events to session
  local function forward_client_events(client)
    local client_events = {
      "initialized", "stopped", "continued", "exited", "terminated",
      "thread", "output", "breakpoint", "module", "loadedSource",
      "process", "capabilities", "progressStart", "progressUpdate",
      "progressEnd", "invalidated", "memory",
    }
    for _, event in ipairs(client_events) do
      client:on(event, function(body)
        emit(event, body)
      end)
    end
  end

  -- Handle startDebugging reverse request
  local function handle_start_debugging(args, respond)
    -- Create child session with the provided configuration
    local child_config = args.configuration or {}
    local child_request = args.request or child_config.request or "launch"
    child_config.request = child_request

    -- Child reuses same adapter (for server adapters, this is a TCP adapter to same server)
    -- Pass depth + 1 to track recursion depth, and set parent for hierarchy
    -- Child sessions inherit adapter_task_id for Overseer visual grouping
    M.create({
      adapter = child_adapter,
      config = child_config,
      handlers = handlers,
      parent = session,
      backend = opts.backend,  -- Pass backend to child sessions
      parent_task_id = session.adapter_task_id,  -- Children grouped under same adapter
    }, function(err, child_session)
      if err then
        respond({ success = false, message = err })
        return
      end

      table.insert(session.children, child_session)
      emit("child", child_session)
      respond({ success = true })
    end, depth + 1)
  end

  -- Handle runInTerminal reverse request
  local function handle_run_in_terminal(args, respond)
    local handler = handlers.runInTerminal or default_run_in_terminal
    -- Pass session as first argument so handler can track terminal buffer
    handler(session, args, function(err, response)
      if err then
        respond(nil, err)
      else
        respond(response, nil)
      end
    end)
  end

  -- Disconnect session and children
  function session:disconnect(cb)
    emit("closing")

    local pending = 1 + #self.children

    local function done()
      pending = pending - 1
      if pending == 0 then
        emit("closed")
        if cb then cb(nil) end
      end
    end

    -- Disconnect children first
    for _, child in ipairs(self.children) do
      child:disconnect(function()
        done()
      end)
    end

    -- Disconnect self
    if self.client then
      self.client:request("disconnect", { terminateDebuggee = false }, function()
        self.client:close()
        done()
      end)
    else
      done()
    end
  end

  -- Terminate session and children
  function session:terminate(cb)
    emit("closing")

    local pending = 1 + #self.children

    local function done()
      pending = pending - 1
      if pending == 0 then
        emit("closed")
        if cb then cb(nil) end
      end
    end

    -- Terminate children first
    for _, child in ipairs(self.children) do
      child:terminate(function()
        done()
      end)
    end

    -- Terminate self
    if self.client then
      self.client:request("terminate", {}, function()
        self.client:request("disconnect", { terminateDebuggee = true }, function()
          self.client:close()
          done()
        end)
      end)
    else
      done()
    end
  end

  -- Get or create client
  local function setup_client(client)
    session.client = client
    forward_client_events(client)

    -- Register reverse request handlers
    client:on_request("runInTerminal", function(args, respond)
      handle_run_in_terminal(args, function(resp, err_msg)
        respond(resp, err_msg)
      end)
      -- Return nil to indicate async response
      return nil, nil
    end)

    client:on_request("startDebugging", function(args, respond)
      handle_start_debugging(args, function(resp)
        respond(resp, resp and not resp.success and resp.message or nil)
      end)
      -- Return nil to indicate async response
      return nil, nil
    end)

    -- Track state for coordinating async operations
    local initialized = false
    local config_done_sent = false
    local launch_response = nil
    local launch_error = nil
    local session_started = false

    -- Function to check if session is ready and call callback
    local function try_complete()
      if session_started then return end
      -- Session is ready when we have launch response (success or error)
      -- and configurationDone has been sent (which happens after initialized)
      if launch_response ~= nil and config_done_sent then
        session_started = true
        if launch_error then
          client:close()
          callback(launch_error, nil)
        else
          emit("ready")
          callback(nil, session)
        end
      end
    end

    -- Register initialized handler - sends configurationDone when received
    client:on("initialized", function(body)
      if initialized then return end -- Already handled
      initialized = true
      emit("initialized", body)

      -- Function to send configurationDone
      local function send_configuration_done()
        -- Send configurationDone (use vim.empty_dict() to ensure {} not [])
        client:request("configurationDone", vim.empty_dict(), function(config_err)
          if config_err and not session_started then
            session_started = true
            client:close()
            callback("configurationDone failed: " .. tostring(config_err), nil)
            return
          end
          config_done_sent = true
          try_complete()
        end)
      end

      -- Call beforeConfigurationDone handler if provided (allows setting breakpoints)
      local before_config = handlers.beforeConfigurationDone
      if before_config then
        before_config(session, function()
          send_configuration_done()
        end)
      else
        send_configuration_done()
      end
    end)

    -- Send initialize request
    client:request("initialize", {
      clientID = "dap-lua",
      clientName = "dap-lua",
      adapterID = config.type or "unknown",
      pathFormat = "path",
      linesStartAt1 = true,
      columnsStartAt1 = true,
      supportsRunInTerminalRequest = true,
      supportsStartDebuggingRequest = true,
      supportsVariableType = true,
      supportsVariablePaging = true,
      supportsProgressReporting = true,
      supportsInvalidatedEvent = true,
      supportsMemoryEvent = true,
      supportsANSIStyling = true,
    }, function(init_err, capabilities)
      if init_err then
        client:close()
        callback("Initialize failed: " .. tostring(init_err), nil)
        return
      end

      session.capabilities = capabilities or {}

      -- Send launch/attach request immediately after initialize
      -- Some adapters (debugpy) only send 'initialized' after receiving launch
      -- Some adapters (js-debug) send 'initialized' before launch
      -- By sending launch early, we support both patterns
      local request_type = config.request or "launch"
      client:request(request_type, config, function(req_err)
        if req_err then
          launch_error = request_type .. " failed: " .. tostring(req_err)
        end
        launch_response = true
        try_complete()
      end)

      -- Timeout for the whole session startup
      local timeout = vim.uv.new_timer()
      local timeout_closed = false

      local function close_timeout()
        if timeout_closed then return end
        timeout_closed = true
        timeout:stop()
        timeout:close()
      end

      timeout:start(30000, 0, function()
        if not session_started then
          session_started = true
          close_timeout()
          client:close()
          vim.schedule(function()
            callback("Session startup timeout", nil)
          end)
        end
      end)

      -- Clean up timeout when session starts
      local orig_try_complete = try_complete
      try_complete = function()
        close_timeout()
        orig_try_complete()
      end
    end)
  end

  -- If client is pre-provided, use it directly
  if opts.client then
    setup_client(opts.client)
    return
  end

  -- If process_handle is provided, create client from it
  if opts.process_handle then
    local client = dap.create_client_from_process(opts.process_handle, {
      on_close = handlers.on_close,
    })
    setup_client(client)
    return
  end

  -- If backend is provided, use it for process management
  local backend = opts.backend
  if backend and adapter_config then
    local adapter_type = adapter_config.type or "stdio"

    ---Helper to create client from process handle and set up
    ---@param process neodap.ProcessHandle
    local function connect_with_process(process)
      -- Notify caller of adapter process (for task tracking)
      if handlers.onAdapterProcess then
        handlers.onAdapterProcess(process)
      end
      local client = dap.create_client_from_process(process, {
        on_close = handlers.on_close,
      })
      setup_client(client)
    end

    if adapter_type == "stdio" then
      -- Spawn adapter process, then create session wrapping it
      local session_name = config.name or config.type or "debug"
      local adapter_process = backend.spawn({
        command = adapter_config.command,
        args = adapter_config.args,
        cwd = adapter_config.cwd,
        env = adapter_config.env,
        name = session_name .. " (adapter)",
        parent_task_id = opts.parent_task_id,
      })

      -- Notify caller of adapter process
      if handlers.onAdapterProcess then
        handlers.onAdapterProcess(adapter_process)
      end

      -- Track adapter task ID for child session inheritance
      session.adapter_task_id = adapter_process.task_id

      -- Create session task wrapping the adapter's stdio
      -- Use original parent_task_id so session is sibling of adapter (not grandchild)
      -- Overseer's list_tasks only shows one level of children
      local session_handle = backend.connect({
        process = adapter_process,
        session_id = session.neodap_session_id,
        name = session_name,
        parent_task_id = opts.parent_task_id,
      })
      connect_with_process(session_handle)
      return

    elseif adapter_type == "tcp" then
      -- Connect to TCP adapter, creates session task
      local session_name = config.name or config.type or "debug"

      -- Inherit adapter task ID from parent (TCP is used for child sessions)
      session.adapter_task_id = opts.parent_task_id

      local session_handle = backend.connect({
        host = adapter_config.host or "127.0.0.1",
        port = adapter_config.port,
        retries = adapter_config.retries,
        retry_delay = adapter_config.retry_delay,
        session_id = session.neodap_session_id,
        name = session_name,
        parent_task_id = opts.parent_task_id,
      })
      connect_with_process(session_handle)
      return

    elseif adapter_type == "server" then
      -- Server adapter: spawn server, wait for port, then connect
      local session_name = config.name or config.type or "debug"
      local server_process = backend.spawn({
        command = adapter_config.command,
        args = adapter_config.args,
        cwd = adapter_config.cwd,
        env = adapter_config.env,
        name = session_name .. " (adapter)",
        parent_task_id = opts.parent_task_id,
        -- Server process doesn't get session_id - it's the adapter, not the session
      })

      -- Notify caller of server process
      if handlers.onAdapterProcess then
        handlers.onAdapterProcess(server_process)
      end

      -- Track adapter task ID for child session inheritance
      session.adapter_task_id = server_process.task_id

      local port_found = false
      local timed_out = false

      -- Set up timeout for port detection
      local timeout = vim.uv.new_timer()
      timeout:start(10000, 0, function()
        if not port_found then
          timed_out = true
          timeout:stop()
          timeout:close()
          server_process.kill()
          vim.schedule(function()
            callback("Timeout waiting for server port", nil)
          end)
        end
      end)

      -- Listen for server output to detect port
      server_process.on_data(function(data)
        if not port_found and not timed_out and adapter_config.connect_condition then
          local p, h = adapter_config.connect_condition(data)
          if p then
            port_found = true
            timeout:stop()
            timeout:close()

            local host = h or adapter_config.host or "127.0.0.1"

            -- Update child_adapter to TCP so children connect to same server
            child_adapter = { type = "tcp", host = host, port = p }

            -- Schedule connect outside of fast event context
            vim.schedule(function()
              -- Connect to the server, creates session task
              -- Use original parent_task_id so session is sibling of adapter (not grandchild)
              -- Overseer's list_tasks only shows one level of children
              local session_handle = backend.connect({
                host = host,
                port = p,
                retries = 5,
                retry_delay = 100,
                session_id = session.neodap_session_id,
                name = session_name,
                parent_task_id = opts.parent_task_id,
                on_close = function()
                  -- When connection closes, kill server if no other connections
                  -- For now, just kill the server (single session per server)
                  server_process.kill()
                end,
              })

              local client = dap.create_client_from_process(session_handle, {
                on_close = handlers.on_close,
              })
              setup_client(client)
            end)
          end
        end
      end)

      -- Log stderr from adapter (via backend)
      server_process.on_stderr(function(data)
        log:warn("Adapter stderr (server)", { name = session_name, data = data })
      end)

      -- Handle server process exit
      server_process.on_exit(function(code)
        if not port_found and not timed_out then
          timed_out = true
          timeout:stop()
          timeout:close()
          vim.schedule(function()
            callback("Server process exited before port was detected", nil)
          end)
        end
      end)

      return
    end
    -- Fall through to dap-lua adapter for unknown types
  end

  -- Fallback: Connect using dap-lua's adapter system
  -- Convert adapter config to dap.adapter if needed
  if adapter_config then
    adapter = dap.adapter(adapter_config)
  end
  adapter:connect(function(err, client)
    if err then
      vim.schedule(function()
        vim.notify("Adapter connection failed: " .. tostring(err), vim.log.levels.ERROR)
      end)
      callback(err, nil)
      return
    end
    setup_client(client)
  end)
end

return M
