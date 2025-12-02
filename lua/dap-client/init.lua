---@type DebugAdapterProtocol
require("dap-client.protocol")

local M = {}

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
---@field request fun(self: DapClient, command: "initialize", arguments: dap.InitializeRequestArguments, callback?: fun(err: string?, body?: dap.Capabilities))
---@field request fun(self: DapClient, command: "launch", arguments: dap.LaunchRequestArguments, callback?: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "attach", arguments: dap.AttachRequestArguments, callback?: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "configurationDone", arguments?: dap.ConfigurationDoneArguments, callback?: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "disconnect", arguments?: dap.DisconnectArguments, callback?: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "terminate", arguments?: dap.TerminateArguments, callback?: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "restart", arguments?: dap.RestartArguments, callback?: fun(err: string?, body?: nil))
---
--- Breakpoints
---@field request fun(self: DapClient, command: "setBreakpoints", arguments: dap.SetBreakpointsArguments, callback?: fun(err: string?, body?: dap.SetBreakpointsResponseBody))
---@field request fun(self: DapClient, command: "setFunctionBreakpoints", arguments: dap.SetFunctionBreakpointsArguments, callback?: fun(err: string?, body?: dap.SetFunctionBreakpointsResponseBody))
---@field request fun(self: DapClient, command: "setExceptionBreakpoints", arguments: dap.SetExceptionBreakpointsArguments, callback?: fun(err: string?, body?: dap.SetExceptionBreakpointsResponseBody))
---@field request fun(self: DapClient, command: "setDataBreakpoints", arguments: dap.SetDataBreakpointsArguments, callback?: fun(err: string?, body?: dap.SetDataBreakpointsResponseBody))
---@field request fun(self: DapClient, command: "setInstructionBreakpoints", arguments: dap.SetInstructionBreakpointsArguments, callback?: fun(err: string?, body?: dap.SetInstructionBreakpointsResponseBody))
---@field request fun(self: DapClient, command: "breakpointLocations", arguments: dap.BreakpointLocationsArguments, callback?: fun(err: string?, body?: dap.BreakpointLocationsResponseBody))
---@field request fun(self: DapClient, command: "dataBreakpointInfo", arguments: dap.DataBreakpointInfoArguments, callback?: fun(err: string?, body?: dap.DataBreakpointInfoResponseBody))
---
--- Execution control
---@field request fun(self: DapClient, command: "continue", arguments: dap.ContinueArguments, callback?: fun(err: string?, body?: dap.ContinueResponseBody))
---@field request fun(self: DapClient, command: "next", arguments: dap.NextArguments, callback?: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "stepIn", arguments: dap.StepInArguments, callback?: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "stepOut", arguments: dap.StepOutArguments, callback?: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "stepBack", arguments: dap.StepBackArguments, callback?: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "reverseContinue", arguments: dap.ReverseContinueArguments, callback?: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "pause", arguments: dap.PauseArguments, callback?: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "restartFrame", arguments: dap.RestartFrameArguments, callback?: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "goto", arguments: dap.GotoArguments, callback?: fun(err: string?, body?: nil))
---@field request fun(self: DapClient, command: "terminateThreads", arguments: dap.TerminateThreadsArguments, callback?: fun(err: string?, body?: nil))
---
--- Information queries
---@field request fun(self: DapClient, command: "threads", arguments?: nil, callback?: fun(err: string?, body?: dap.ThreadsResponseBody))
---@field request fun(self: DapClient, command: "stackTrace", arguments: dap.StackTraceArguments, callback?: fun(err: string?, body?: dap.StackTraceResponseBody))
---@field request fun(self: DapClient, command: "scopes", arguments: dap.ScopesArguments, callback?: fun(err: string?, body?: dap.ScopesResponseBody))
---@field request fun(self: DapClient, command: "variables", arguments: dap.VariablesArguments, callback?: fun(err: string?, body?: dap.VariablesResponseBody))
---@field request fun(self: DapClient, command: "source", arguments: dap.SourceArguments, callback?: fun(err: string?, body?: dap.SourceResponseBody))
---@field request fun(self: DapClient, command: "loadedSources", arguments?: dap.LoadedSourcesArguments, callback?: fun(err: string?, body?: dap.LoadedSourcesResponseBody))
---@field request fun(self: DapClient, command: "modules", arguments: dap.ModulesArguments, callback?: fun(err: string?, body?: dap.ModulesResponseBody))
---@field request fun(self: DapClient, command: "exceptionInfo", arguments: dap.ExceptionInfoArguments, callback?: fun(err: string?, body?: dap.ExceptionInfoResponseBody))
---
--- Evaluation and modification
---@field request fun(self: DapClient, command: "evaluate", arguments: dap.EvaluateArguments, callback?: fun(err: string?, body?: dap.EvaluateResponseBody))
---@field request fun(self: DapClient, command: "setVariable", arguments: dap.SetVariableArguments, callback?: fun(err: string?, body?: dap.SetVariableResponseBody))
---@field request fun(self: DapClient, command: "setExpression", arguments: dap.SetExpressionArguments, callback?: fun(err: string?, body?: dap.SetExpressionResponseBody))
---
--- Advanced features
---@field request fun(self: DapClient, command: "stepInTargets", arguments: dap.StepInTargetsArguments, callback?: fun(err: string?, body?: dap.StepInTargetsResponseBody))
---@field request fun(self: DapClient, command: "gotoTargets", arguments: dap.GotoTargetsArguments, callback?: fun(err: string?, body?: dap.GotoTargetsResponseBody))
---@field request fun(self: DapClient, command: "completions", arguments: dap.CompletionsArguments, callback?: fun(err: string?, body?: dap.CompletionsResponseBody))
---@field request fun(self: DapClient, command: "readMemory", arguments: dap.ReadMemoryArguments, callback?: fun(err: string?, body?: dap.ReadMemoryResponseBody))
---@field request fun(self: DapClient, command: "writeMemory", arguments: dap.WriteMemoryArguments, callback?: fun(err: string?, body?: dap.WriteMemoryResponseBody))
---@field request fun(self: DapClient, command: "disassemble", arguments: dap.DisassembleArguments, callback?: fun(err: string?, body?: dap.DisassembleResponseBody))

---@class Transport
---@field write fun(chunk: string)
---@field close fun()

---@param transport Transport
---@param opts? { on_close?: fun() }
---@return DapClient
local function create_client(transport, opts)
  opts = opts or {}
  local seq = 1
  local callbacks = {}        -- seq -> callback
  local event_handlers = {}   -- event -> handler
  local request_handlers = {} -- command -> handler
  local is_closing = false

  local function encode_msg(msg)
    local json = vim.json.encode(msg)
    return string.format("Content-Length: %d\r\n\r\n%s", #json, json)
  end

  local function handle_body(body)
    -- Schedule processing on the main thread to allow handlers to use Vim API
    vim.schedule(function()
      local ok, msg = pcall(vim.json.decode, body)
      if not ok then
        vim.notify("[DAP] Failed to decode message: " .. tostring(msg), vim.log.levels.WARN)
        return
      end

      if msg.type == "response" then
        local cb = callbacks[msg.request_seq]
        if cb then
          callbacks[msg.request_seq] = nil
          if msg.success then
            cb(nil, msg.body)
          else
            cb(msg.message or "Error", msg.body)
          end
        end
      elseif msg.type == "event" then
        local h = event_handlers[msg.event]
        if h then h(msg.body) end
      elseif msg.type == "request" then
        local h = request_handlers[msg.command]
        if h then
          local response_body, err = h(msg.arguments)
          local response = {
            type = "response",
            seq = seq,
            request_seq = msg.seq,
            command = msg.command,
            success = not err,
            message = err,
            body = response_body
          }
          seq = seq + 1
          transport.write(encode_msg(response))
        end
      end
    end)
  end

  local read_loop = vim.lsp.rpc.create_read_loop(handle_body, function(code, signal)
    -- on exit - cleanup and notify
    if not is_closing then
      is_closing = true
      if opts.on_close then
        pcall(opts.on_close)
      end
    end
  end, function(err)
    -- on error - log internally
    vim.schedule(function()
      vim.notify("[DAP] RPC error: " .. tostring(err), vim.log.levels.WARN)
    end)
  end)

  return {
    request = function(_, command, arguments, callback)
      local co, is_plenary_async
      if not callback then
        co = coroutine.running()
        if co then
          -- Yield a callback function for plenary.async compatibility
          -- plenary.async expects us to yield a function(callback) that will call the callback when done
          local yielded = coroutine.yield(function(done)
            is_plenary_async = true
            callback = function(err, body)
              -- Guard against calling done after async context is torn down
              if done then
                done(err, body)
              end
            end

            local id = seq
            seq = seq + 1

            local msg = {
              seq = id,
              type = "request",
              command = command,
              arguments = arguments
            }

            callbacks[id] = callback

            -- Add internal timeout (30 seconds)
            vim.defer_fn(function()
              if callbacks[id] then
                callbacks[id] = nil
                pcall(callback, "Request timeout after 30s", nil)
              end
            end, 30000)

            transport.write(encode_msg(msg))
          end)

          -- If we're here, it means regular coroutine (not plenary.async)
          -- The yield returned, so we got resumed with actual values
          if not is_plenary_async then
            return yielded
          end
        end
      end

      -- Regular callback or no coroutine mode
      local id = seq
      seq = seq + 1

      local msg = {
        seq = id,
        type = "request",
        command = command,
        arguments = arguments
      }

      if callback then
        callbacks[id] = callback

        -- Add internal timeout (30 seconds)
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
    on_request = function(_, command, handler)
      request_handlers[command] = handler
    end,
    close = function(_)
      if not is_closing then
        is_closing = true
        transport.close()
      end
    end,
    is_closing = function(_)
      return is_closing
    end,
    -- Internal use
    on_read = read_loop
  }
end

--- Start a RPC client via stdio
--- @param cmd string
--- @param args? string[]
--- @param opts? { cwd?: string, on_close?: fun() }
--- @return DapClient
function M.start(cmd, args, opts)
  opts = opts or {}

  local client
  local sys_obj = vim.system({ cmd, unpack(args or {}) }, {
    cwd = opts.cwd,
    stdin = true,
    stdout = function(err, data)
      if err then
        vim.schedule(function()
          vim.notify("[DAP] stdout error: " .. tostring(err), vim.log.levels.WARN)
        end)
      end
      if data then
        client.on_read(err, data)
      end
    end,
    stderr = function(err, data)
      -- Log stderr at DEBUG level (can be enabled via vim.log.levels)
      if data then
        vim.schedule(function()
          vim.notify("[DAP STDERR] " .. tostring(data), vim.log.levels.DEBUG)
        end)
      end
    end
  }, function(out)
    -- Process exited - log at DEBUG level
    -- Normal exit (code 0) is expected, non-zero could indicate issues
    if out.code ~= 0 then
      vim.schedule(function()
        vim.notify(
          string.format("[DAP] Process exited with code %d, signal %d", out.code, out.signal),
          vim.log.levels.DEBUG
        )
      end)
    end
  end)

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
    end
  }

  client = create_client(transport, { on_close = opts.on_close })
  return client
end

--- Connect to a RPC server via TCP
--- @param host string
--- @param port number
--- @param opts? { on_close?: fun() }
--- @return DapClient
function M.connect(host, port, opts)
  opts = opts or {}
  local tcp = vim.uv.new_tcp()

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
    end
  }

  local client = create_client(transport, { on_close = opts.on_close })

  -- Add connection timeout
  local timeout = vim.uv.new_timer()
  timeout:start(5000, 0, function()
    if not tcp:is_closing() then
      vim.schedule(function()
        vim.notify(
          string.format("[DAP] Connection timeout to %s:%d", host, port),
          vim.log.levels.ERROR
        )
      end)
      tcp:close()
    end
    timeout:close()
  end)

  tcp:connect(host, port, function(err)
    timeout:stop()
    timeout:close()

    if err then
      vim.schedule(function()
        vim.notify(
          string.format("[DAP] Connection failed to %s:%d: %s", host, port, err),
          vim.log.levels.ERROR
        )
      end)
      tcp:close()
      return
    end

    tcp:read_start(function(err, chunk)
      if err then
        vim.schedule(function()
          vim.notify("[DAP] Read error: " .. tostring(err), vim.log.levels.WARN)
        end)
      end
      if chunk then
        client.on_read(err, chunk)
      end
    end)
  end)

  return client
end

--- @class Adapter
--- @field connect fun(): DapClient

local adapters = {}

function adapters.stdio(opts)
  return {
    connect = function()
      return M.start(opts.command, opts.args, { cwd = opts.cwd })
    end
  }
end

function adapters.tcp(opts)
  return {
    connect = function()
      return M.connect(opts.host, opts.port)
    end
  }
end

function adapters.server(opts)
  local server = {
    obj = nil,
    host = opts.host or "127.0.0.1",
    port = nil,
    active_connections = 0
  }

  local function start_server()
    if server.obj then return true end

    local port_found = false
    local env = opts.env or vim.fn.environ()
    -- Debug: show if nix-profile is in PATH
    local path = env.PATH or ""
    vim.schedule(function()
      vim.notify("[DAP] PATH has nix-profile: " .. tostring(path:find("nix-profile", 1, true) ~= nil), vim.log.levels.INFO)
    end)
    server.obj = vim.system({ opts.command, unpack(opts.args or {}) }, {
      cwd = opts.cwd,
      env = env,
      stdout = function(_, data)
        if data then
          -- Always log server output for debugging
          vim.schedule(function()
            vim.notify("[DAP Server] " .. tostring(data), vim.log.levels.DEBUG)
          end)

          if opts.connect_condition and not port_found then
            local p, h = opts.connect_condition(data)
            if p then
              server.port = p
              if h then server.host = h end
              port_found = true
            end
          end
        end
      end,
      stderr = function(_, data)
        if data then
          vim.schedule(function()
            vim.notify("[DAP Server] " .. tostring(data), vim.log.levels.DEBUG)
          end)
        end
      end
    }, function(out)
      -- Server exited
      if out.code ~= 0 then
        vim.schedule(function()
          vim.notify(
            string.format("[DAP Server] Exited with code %d", out.code),
            vim.log.levels.WARN
          )
        end)
      end
      server.obj = nil
      server.port = nil
      server.active_connections = 0
    end)

    vim.wait(5000, function() return port_found end)
    return port_found
  end

  local function terminate_if_no_connections()
    if server.active_connections <= 0 and server.obj then
      vim.schedule(function()
        vim.notify("[DAP Server] No active connections, shutting down server", vim.log.levels.INFO)
      end)
      if not server.obj:is_closing() then
        server.obj:kill("SIGTERM")
      end
      server.obj = nil
      server.port = nil
    end
  end

  return {
    connect = function()
      if not start_server() then
        error("Failed to start DAP server or find port")
      end

      -- Track connection
      server.active_connections = server.active_connections + 1

      local client = M.connect(server.host, server.port, {
        on_close = function()
          -- Decrement connection count and auto-shutdown if needed
          server.active_connections = server.active_connections - 1
          terminate_if_no_connections()
        end
      })

      -- Expose connection info
      client.host = server.host
      client.port = server.port

      return client
    end
  }
end

--- Create a unified DAP adapter
--- @param opts { type: "stdio"|"tcp"|"server", command?: string, args?: string[], cwd?: string, env?: table, host?: string, port?: number, connect_condition?: fun(chunk: string): number? }
--- @return Adapter
function M.create_adapter(opts)
  opts = opts or {}
  local type = opts.type or "stdio"
  local adapter_fn = adapters[type]

  if adapter_fn then
    return adapter_fn(opts)
  else
    error("Unknown adapter type: " .. tostring(type))
  end
end

return M
