---@type DebugAdapterProtocol
require("dap-lua.protocol")

-- Pre-load vim.lsp.rpc to avoid loading in fast event context
local _ = vim.lsp.rpc

local log = require("neolog").new("dap-lua")

local M = {}

-- Check if setpriv with pdeathsig is available (Linux only)
local has_pdeathsig = vim.fn.has("linux") == 1 and vim.fn.executable("setpriv") == 1

--- Wrap command to die when parent dies (Linux only)
--- Uses setpriv --pdeathsig=KILL to ensure child processes are killed
--- when the parent nvim process dies unexpectedly
---@param command string
---@param args string[]?
---@return string command
---@return string[] args
local function wrap_pdeathsig(command, args)
  if not has_pdeathsig then
    return command, args or {}
  end
  local new_args = { "--pdeathsig=KILL", command }
  for _, arg in ipairs(args or {}) do
    table.insert(new_args, arg)
  end
  return "setpriv", new_args
end

--- DAP client for Debug Adapter Protocol communication.
---@class DapClient
---@field on_request fun(command: string, handler: fun(arguments: table): table?, string?)
---@field close fun()
---@field is_closing fun(): boolean
---
--- Type-safe event listener with overloads for all DAP events.
---
---@field on fun(self: DapClient, event: "initialized", handler: fun(body: {}))
---@field on fun(self: DapClient, event: "stopped", handler: fun(body: dap.StoppedEventBody))
---@field on fun(self: DapClient, event: "continued", handler: fun(body: dap.ContinuedEventBody))
---@field on fun(self: DapClient, event: "exited", handler: fun(body: dap.ExitedEventBody))
---@field on fun(self: DapClient, event: "terminated", handler: fun(body: dap.TerminatedEventBody))
---@field on fun(self: DapClient, event: "thread", handler: fun(body: dap.ThreadEventBody))
---@field on fun(self: DapClient, event: "output", handler: fun(body: dap.OutputEventBody))
---@field on fun(self: DapClient, event: "breakpoint", handler: fun(body: dap.BreakpointEventBody))
---@field on fun(self: DapClient, event: "module", handler: fun(body: dap.ModuleEventBody))
---@field on fun(self: DapClient, event: "loadedSource", handler: fun(body: dap.LoadedSourceEventBody))
---@field on fun(self: DapClient, event: "process", handler: fun(body: dap.ProcessEventBody))
---@field on fun(self: DapClient, event: "capabilities", handler: fun(body: dap.CapabilitiesEventBody))
---@field on fun(self: DapClient, event: "progressStart", handler: fun(body: dap.ProgressStartEventBody))
---@field on fun(self: DapClient, event: "progressUpdate", handler: fun(body: dap.ProgressUpdateEventBody))
---@field on fun(self: DapClient, event: "progressEnd", handler: fun(body: dap.ProgressEndEventBody))
---@field on fun(self: DapClient, event: "invalidated", handler: fun(body: dap.InvalidatedEventBody))
---@field on fun(self: DapClient, event: "memory", handler: fun(body: dap.MemoryEventBody))
---
--- Type-safe request method with overloads for all DAP commands.
---@field request fun(self: DapClient, command: "initialize", arguments: dap.InitializeRequestArguments, callback: fun(err: string?, body?: dap.Capabilities))
---@field request fun(self: DapClient, command: "launch", arguments: dap.LaunchRequestArguments, callback: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "attach", arguments: dap.AttachRequestArguments, callback: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "configurationDone", arguments?: dap.ConfigurationDoneArguments, callback: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "disconnect", arguments?: dap.DisconnectArguments, callback: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "terminate", arguments?: dap.TerminateArguments, callback: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "restart", arguments?: dap.RestartArguments, callback: fun(err: string?, body?: nil))
---
--- Breakpoints
---@field request fun(self: DapClient, command: "setBreakpoints", arguments: dap.SetBreakpointsArguments, callback: fun(err: string?, body?: dap.SetBreakpointsResponseBody))
---@field request fun(self: DapClient, command: "setFunctionBreakpoints", arguments: dap.SetFunctionBreakpointsArguments, callback: fun(err: string?, body?: dap.SetFunctionBreakpointsResponseBody))
---@field request fun(self: DapClient, command: "setExceptionBreakpoints", arguments: dap.SetExceptionBreakpointsArguments, callback: fun(err: string?, body?: dap.SetExceptionBreakpointsResponseBody))
---@field request fun(self: DapClient, command: "setDataBreakpoints", arguments: dap.SetDataBreakpointsArguments, callback: fun(err: string?, body?: dap.SetDataBreakpointsResponseBody))
---@field request fun(self: DapClient, command: "setInstructionBreakpoints", arguments: dap.SetInstructionBreakpointsArguments, callback: fun(err: string?, body?: dap.SetInstructionBreakpointsResponseBody))
---@field request fun(self: DapClient, command: "breakpointLocations", arguments: dap.BreakpointLocationsArguments, callback: fun(err: string?, body?: dap.BreakpointLocationsResponseBody))
---@field request fun(self: DapClient, command: "dataBreakpointInfo", arguments: dap.DataBreakpointInfoArguments, callback: fun(err: string?, body?: dap.DataBreakpointInfoResponseBody))
---
--- Execution control
---@field request fun(self: DapClient, command: "continue", arguments: dap.ContinueArguments, callback: fun(err: string?, body?: dap.ContinueResponseBody))
---@field request fun(self: DapClient, command: "next", arguments: dap.NextArguments, callback: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "stepIn", arguments: dap.StepInArguments, callback: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "stepOut", arguments: dap.StepOutArguments, callback: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "stepBack", arguments: dap.StepBackArguments, callback: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "reverseContinue", arguments: dap.ReverseContinueArguments, callback: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "pause", arguments: dap.PauseArguments, callback: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "restartFrame", arguments: dap.RestartFrameArguments, callback: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "goto", arguments: dap.GotoArguments, callback: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "terminateThreads", arguments: dap.TerminateThreadsArguments, callback: fun(err: string?, body?: nil))
---
--- Information queries
---@field request fun(self: DapClient, command: "threads", arguments?: nil, callback: fun(err: string?, body?: dap.ThreadsResponseBody))
---@field request fun(self: DapClient, command: "stackTrace", arguments: dap.StackTraceArguments, callback: fun(err: string?, body?: dap.StackTraceResponseBody))
---@field request fun(self: DapClient, command: "scopes", arguments: dap.ScopesArguments, callback: fun(err: string?, body?: dap.ScopesResponseBody))
---@field request fun(self: DapClient, command: "variables", arguments: dap.VariablesArguments, callback: fun(err: string?, body?: dap.VariablesResponseBody))
---@field request fun(self: DapClient, command: "source", arguments: dap.SourceArguments, callback: fun(err: string?, body?: dap.SourceResponseBody))
---@field request fun(self: DapClient, command: "loadedSources", arguments?: dap.LoadedSourcesArguments, callback: fun(err: string?, body?: dap.LoadedSourcesResponseBody))
---@field request fun(self: DapClient, command: "modules", arguments: dap.ModulesArguments, callback: fun(err: string?, body?: dap.ModulesResponseBody))
---@field request fun(self: DapClient, command: "exceptionInfo", arguments: dap.ExceptionInfoArguments, callback: fun(err: string?, body?: dap.ExceptionInfoResponseBody))
---
--- Evaluation and modification
---@field request fun(self: DapClient, command: "evaluate", arguments: dap.EvaluateArguments, callback: fun(err: string?, body?: dap.EvaluateResponseBody))
---@field request fun(self: DapClient, command: "setVariable", arguments: dap.SetVariableArguments, callback: fun(err: string?, body?: dap.SetVariableResponseBody))
---@field request fun(self: DapClient, command: "setExpression", arguments: dap.SetExpressionArguments, callback: fun(err: string?, body?: dap.SetExpressionResponseBody))
---
--- Advanced features
---@field request fun(self: DapClient, command: "stepInTargets", arguments: dap.StepInTargetsArguments, callback: fun(err: string?, body?: dap.StepInTargetsResponseBody))
---@field request fun(self: DapClient, command: "gotoTargets", arguments: dap.GotoTargetsArguments, callback: fun(err: string?, body?: dap.GotoTargetsResponseBody))
---@field request fun(self: DapClient, command: "completions", arguments: dap.CompletionsArguments, callback: fun(err: string?, body?: dap.CompletionsResponseBody))
---@field request fun(self: DapClient, command: "readMemory", arguments: dap.ReadMemoryArguments, callback: fun(err: string?, body?: dap.ReadMemoryResponseBody))
---@field request fun(self: DapClient, command: "writeMemory", arguments: dap.WriteMemoryArguments, callback: fun(err: string?, body?: dap.WriteMemoryResponseBody))
---@field request fun(self: DapClient, command: "disassemble", arguments: dap.DisassembleArguments, callback: fun(err: string?, body?: dap.DisassembleResponseBody))

---@class DapTransport
---@field write fun(chunk: string)
---@field close fun()

---@param transport DapTransport
---@param opts? { on_close?: fun() }
---@return DapClient
local function create_client(transport, opts)
  opts = opts or {}
  local seq = 1
  local callbacks = {}
  local event_handlers = {}
  local request_handlers = {}
  local is_closing = false

  local function encode_msg(msg)
    local json = vim.json.encode(msg)
    return string.format("Content-Length: %d\r\n\r\n%s", #json, json)
  end

  local function handle_body(body)
    local ok, msg = pcall(vim.json.decode, body)
    if not ok then
      return
    end

    if msg.type == "response" then
      local cb = callbacks[msg.request_seq]
      if cb then
        callbacks[msg.request_seq] = nil
        -- Schedule callback to avoid deep call stacks
        vim.schedule(function()
          if msg.success then
            cb(nil, msg.body)
          else
            -- Extract error message: prefer msg.message, fallback to body.error.format
            local err_msg = msg.message
            if (not err_msg or err_msg == "") and msg.body and msg.body.error then
              err_msg = msg.body.error.format
            end
            cb(err_msg or "Unknown error", msg.body)
          end
        end)
      end
    elseif msg.type == "event" then
      local h = event_handlers[msg.event]
      if h then
        vim.schedule(function()
          h(msg.body)
        end)
      end
    elseif msg.type == "request" then
      local h = request_handlers[msg.command]
      if h then
        local response_sent = false

        local function send_response(response_body, err)
          if response_sent then return end
          response_sent = true
          local response = {
            type = "response",
            seq = seq,
            request_seq = msg.seq,
            command = msg.command,
            success = not err,
            message = err,
            body = response_body,
          }
          seq = seq + 1
          transport.write(encode_msg(response))
        end

        -- Handler can return synchronously or call respond callback async
        local response_body, err = h(msg.arguments, send_response)
        if response_body ~= nil or err ~= nil then
          -- Synchronous response
          send_response(response_body, err)
        end
        -- If both are nil, handler will call send_response async
      end
    end
  end

  local read_loop = vim.lsp.rpc.create_read_loop(handle_body, function()
    if not is_closing then
      is_closing = true
      if opts.on_close then
        pcall(opts.on_close)
      end
    end
  end, function() end)

  return {
    request = function(_, command, arguments, callback)
      local id = seq
      seq = seq + 1

      local msg = {
        seq = id,
        type = "request",
        command = command,
        arguments = arguments,
      }

      if callback then
        callbacks[id] = callback

        vim.defer_fn(function()
          if callbacks[id] then
            callbacks[id] = nil
            pcall(callback, "Request timeout after 30s", nil)
          end
        end, 30000)
      end

      transport.write(encode_msg(msg))
    end,
    on = function(_, event, handler)
      event_handlers[event] = handler
    end,
    --- Register a reverse request handler.
    --- Handler can be sync (return body, err) or async (call respond callback).
    ---@param command string
    ---@param handler fun(arguments: table, respond?: fun(body: table?, err: string?)): table?, string?
    on_request = function(_, command, handler)
      request_handlers[command] = handler
    end,
    close = function()
      if not is_closing then
        is_closing = true
        transport.close()
      end
    end,
    is_closing = function()
      return is_closing
    end,
    _on_read = read_loop,
  }
end

--- Create a DAP client from a transport (exported for backend integration)
---@param transport DapTransport
---@param opts? { on_close?: fun() }
---@return DapClient
function M.create_client(transport, opts)
  return create_client(transport, opts)
end

--- Create a DAP client from a ProcessHandle (backend abstraction)
--- This allows using backend-managed processes with the DAP client
---@param process_handle neodap.ProcessHandle
---@param opts? { on_close?: fun() }
---@return DapClient
function M.create_client_from_process(process_handle, opts)
  opts = opts or {}
  local client

  local transport = {
    write = function(chunk)
      process_handle.write(chunk)
    end,
    close = function()
      process_handle.kill()
    end,
  }

  client = create_client(transport, { on_close = opts.on_close })

  -- Wire up process data to client's read loop
  process_handle.on_data(function(data)
    client._on_read(nil, data)
  end)

  -- Log stderr from the process
  process_handle.on_stderr(function(data)
    vim.schedule(function()
      vim.notify("[DAP stderr] " .. data, vim.log.levels.WARN)
    end)
  end)

  return client
end

--- Start a client via stdio
---@param cmd string
---@param args? string[]
---@param opts? { cwd?: string, on_close?: fun() }
---@return DapClient
local function start_stdio(cmd, args, opts)
  opts = opts or {}

  local client
  local sys_obj = vim.system({ cmd, unpack(args or {}) }, {
    cwd = opts.cwd,
    stdin = true,
    stdout = function(err, data)
      if data then
        client._on_read(err, data)
      end
    end,
    stderr = function(err, data)
      if data then
        vim.schedule(function()
          vim.notify("[DAP stderr] " .. data, vim.log.levels.WARN)
        end)
      end
    end,
  }, function() end)

  local transport = {
    write = function(chunk)
      if not sys_obj:is_closing() then
        sys_obj:write(chunk)
      end
    end,
    close = function()
      if not sys_obj:is_closing() then
        sys_obj:kill("SIGTERM")
      end
    end,
  }

  client = create_client(transport, { on_close = opts.on_close })
  return client
end

--- Connect to a server via TCP
---@param host string
---@param port number
---@param opts? { on_close?: fun(), retries?: number, retry_delay?: number }
---@param callback fun(err: string?, client: DapClient?)
local function connect_tcp(host, port, opts, callback)
  opts = opts or {}
  local retries = opts.retries or 5
  local retry_delay = opts.retry_delay or 100
  local connected = false
  local callback_fired = false
  local tcp
  local client
  local timeout
  local timeout_closed = false

  local function close_timeout()
    if timeout_closed then return end
    timeout_closed = true
    if timeout then
      timeout:stop()
      timeout:close()
      timeout = nil
    end
  end

  local function cleanup()
    close_timeout()
    if tcp and not tcp:is_closing() then
      tcp:close()
    end
  end

  local function try_connect(attempts_left)
    tcp = vim.uv.new_tcp()

    local transport = {
      write = function(chunk)
        if tcp and not tcp:is_closing() then
          tcp:write(chunk)
        end
      end,
      close = function()
        if tcp and not tcp:is_closing() then
          tcp:close()
        end
      end,
    }

    client = create_client(transport, { on_close = opts.on_close })

    tcp:connect(host, port, function(err)
      if err then
        tcp:close()
        if attempts_left > 0 and err:match("ECONNREFUSED") then
          -- Server not ready yet, retry after delay
          local retry_timer = vim.uv.new_timer()
          retry_timer:start(retry_delay, 0, function()
            retry_timer:close()
            try_connect(attempts_left - 1)
          end)
        else
          if not callback_fired then
            callback_fired = true
            cleanup()
            callback("Connection failed: " .. tostring(err), nil)
          end
        end
        return
      end

      connected = true
      callback_fired = true
      close_timeout()

      tcp:read_start(function(read_err, chunk)
        if chunk then
          client._on_read(read_err, chunk)
        end
      end)

      callback(nil, client)
    end)
  end

  -- Overall timeout
  timeout = vim.uv.new_timer()
  timeout:start(5000, 0, function()
    if not connected and not callback_fired then
      callback_fired = true
      cleanup()
      vim.schedule(function()
        callback("Connection timeout", nil)
      end)
    end
  end)

  try_connect(retries)
end

---@class DapAdapter
---@field connect fun(callback: fun(err: string?, client: DapClient?))

local adapters = {}

---@param opts { command: string, args?: string[], cwd?: string }
---@return DapAdapter
function adapters.stdio(opts)
  return {
    connect = function(_, callback)
      local client = start_stdio(opts.command, opts.args, { cwd = opts.cwd })
      vim.schedule(function()
        callback(nil, client)
      end)
    end,
  }
end

---@param opts { host: string, port: number }
---@return DapAdapter
function adapters.tcp(opts)
  return {
    connect = function(_, callback)
      connect_tcp(opts.host, opts.port, {}, callback)
    end,
  }
end

---@param opts { command: string, args?: string[], cwd?: string, env?: table, host?: string, connect_condition: fun(chunk: string): number?, string? }
---@return DapAdapter
function adapters.server(opts)
  local server = {
    obj = nil,
    host = opts.host or "127.0.0.1",
    port = nil,
    active_connections = 0,
  }

  local function terminate_if_no_connections()
    if server.active_connections <= 0 and server.obj then
      if server.obj.stdout and not server.obj.stdout:is_closing() then
        server.obj.stdout:close()
      end
      if server.obj.handle and not server.obj.handle:is_closing() then
        server.obj.handle:kill("sigterm")
      end
      server.obj = nil
      server.port = nil
    end
  end

  ---@param callback fun(err: string?)
  local function start_server(callback)
    if server.obj then
      callback(nil)
      return
    end

    local port_found = false
    local uv = vim.uv

    local stdout_pipe = uv.new_pipe(false)
    local stderr_pipe = uv.new_pipe(false)
    local spawn_cmd, spawn_args = wrap_pdeathsig(opts.command, opts.args)
    local handle, pid = uv.spawn(spawn_cmd, {
      args = spawn_args,
      cwd = opts.cwd,
      env = opts.env,
      stdio = { nil, stdout_pipe, stderr_pipe },
    }, function(code, signal)
      server.obj = nil
      server.port = nil
      server.active_connections = 0
    end)

    if not handle then
      callback("Failed to spawn server process")
      return
    end

    server.obj = { handle = handle, stdout = stdout_pipe, stderr = stderr_pipe }

    -- Log stderr from the adapter process (standalone/fallback path)
    stderr_pipe:read_start(function(err, data)
      if data then
        log:warn("Adapter stderr (standalone)", { command = opts.command, data = data })
      end
    end)

    -- Timeout timer with safe close
    local timeout = uv.new_timer()
    local timeout_closed = false

    local function close_timeout()
      if timeout_closed then return end
      timeout_closed = true
      timeout:stop()
      timeout:close()
    end

    timeout:start(10000, 0, function()
      if not port_found then
        close_timeout()
        vim.schedule(function()
          callback("Timeout waiting for server port")
        end)
      end
    end)

    stdout_pipe:read_start(function(err, data)
      if data and opts.connect_condition and not port_found then
        local p, h = opts.connect_condition(data)
        if p then
          server.port = p
          if h then
            server.host = h
          end
          port_found = true
          close_timeout()
          vim.schedule(function()
            callback(nil)
          end)
        end
      end
    end)
  end

  return {
    connect = function(_, callback)
      start_server(function(err)
        if err then
          callback(err, nil)
          return
        end

        server.active_connections = server.active_connections + 1

        connect_tcp(server.host, server.port, {
          on_close = function()
            server.active_connections = server.active_connections - 1
            terminate_if_no_connections()
          end,
        }, callback)
      end)
    end,
  }
end

--- Create a DAP adapter
---@param opts { type: "stdio"|"tcp"|"server", command?: string, args?: string[], cwd?: string, env?: table, host?: string, port?: number, connect_condition?: fun(chunk: string): number?, string? }
---@return DapAdapter
function M.adapter(opts)
  local adapter_type = opts.type or "stdio"
  local adapter_fn = adapters[adapter_type]

  if adapter_fn then
    return adapter_fn(opts)
  else
    error("Unknown adapter type: " .. tostring(adapter_type))
  end
end

return M
