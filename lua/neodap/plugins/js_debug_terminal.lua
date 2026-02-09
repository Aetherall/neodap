-- Plugin: js-debug Terminal
-- Creates a special terminal where Node.js processes are automatically debugged.
-- Similar to VS Code's "JavaScript Debug Terminal".
-- Requires js-debug (vscode-js-debug) to be installed.

local log = require("neodap.logger")

---Get the path to the bootloader.js file
---@return string
local function get_bootloader_path()
  local source = debug.getinfo(1, "S").source:sub(2)
  local dir = source:match("(.*/)")
  return dir .. "js_debug_terminal/bootloader.js"
end

---@class neodap.plugins.js_debug_terminal.Config
---@field adapter? table DAP adapter config for attaching (default: pwa-node from js-debug)
---@field shell? string Shell to use in terminal (default: vim.o.shell)
---@field stopOnEntry? boolean Pause immediately when debugger attaches (default: true)
---@field jsDebugCommand? string Command to start js-debug (default: "js-debug")

---@param debugger neodap.entities.Debugger
---@param config? neodap.plugins.js_debug_terminal.Config
return function(debugger, config)
  config = config or {}

  local bootloader_path = get_bootloader_path()
  local shell = config.shell or vim.o.shell
  local js_debug_command = config.jsDebugCommand or "js-debug"

  -- Track active server and terminals
  local server = nil
  local server_port = nil
  local terminals = {} -- bufnr -> { jobid, ... }
  local pending_connections = {} -- client -> { buffer, ... }

  ---Handle incoming connection from bootloader
  ---@param client userdata uv_tcp_t client socket
  local function handle_client(client)
    local buffer = ""

    pending_connections[client] = { buffer = "" }

    client:read_start(function(err, data)
      if err then
        log:error("Client read error", { error = err })
        client:close()
        pending_connections[client] = nil
        return
      end

      if not data then
        -- Client disconnected
        client:close()
        pending_connections[client] = nil
        return
      end

      -- Accumulate data until we get a newline (JSON message)
      buffer = buffer .. data
      local newline_pos = buffer:find("\n")

      if not newline_pos then
        return -- Wait for more data
      end

      local json_str = buffer:sub(1, newline_pos - 1)
      buffer = buffer:sub(newline_pos + 1)

      -- Parse JSON payload
      local ok, payload = pcall(vim.json.decode, json_str)
      if not ok then
        log:error("Failed to parse bootloader payload", { raw = json_str })
        client:close()
        pending_connections[client] = nil
        return
      end

      log:info("js-debug terminal: Node process connected", {
        pid = payload.pid,
        port = payload.inspectorPort,
      })

      -- Schedule DAP attach on main thread
      vim.schedule(function()
        -- Build adapter config for js-debug
        local adapter = config.adapter or {
          type = "server",
          command = js_debug_command,
          args = { "0" }, -- Use port 0 for random port
          connect_condition = function(output)
            -- js-debug outputs: "Debug server listening at ::1:PORT" or "127.0.0.1:PORT"
            local port = output:match("listening at %[?::1%]?:(%d+)")
              or output:match("listening at 127%.0%.0%.1:(%d+)")
              or output:match("listening at [^:]+:(%d+)")
            if port then
              -- Return ::1 for IPv6 or 127.0.0.1 for IPv4
              -- Check which one js-debug is listening on
              if output:match("::1") then
                return tonumber(port), "::1"
              else
                return tonumber(port), "127.0.0.1"
              end
            end
          end,
        }

        -- Build launch config
        local launch_config = {
          type = "pwa-node",
          request = "attach",
          name = "js-debug terminal: " .. (payload.pid or "?"),
          port = payload.inspectorPort,
          host = "127.0.0.1",
          -- Pause immediately so user can set breakpoints
          stopOnEntry = config.stopOnEntry ~= false,
          -- Skip internal Node.js files
          skipFiles = { "<node_internals>/**" },
        }

        -- Start debug session
        local session = debugger:debug({
          adapter = adapter,
          config = launch_config,
        })

        if session then
          log:info("js-debug terminal: Session started", { session = session.uri:get() })

          -- Wait for session to be running before signaling bootloader
          -- This ensures js-debug has connected to the Node inspector
          local signaled = false
          session.state:use(function(state)
            if signaled then return end
            if state == "running" or state == "stopped" then
              signaled = true
              log:info("js-debug terminal: Session running, signaling bootloader")
              pcall(function()
                client:write("attached\n")
                client:close()
              end)
              pending_connections[client] = nil
            elseif state == "terminated" then
              signaled = true
              log:error("js-debug terminal: Session terminated before running")
              pcall(function()
                client:write("error\n")
                client:close()
              end)
              pending_connections[client] = nil
            end
          end)
        else
          log:error("js-debug terminal: Failed to start debug session")
          client:write("error\n")
          client:close()
          pending_connections[client] = nil
        end
      end)
    end)
  end

  ---Start the TCP server for bootloader connections
  ---@return boolean success
  local function start_server()
    if server then
      return true -- Already running
    end

    server = vim.uv.new_tcp()
    if not server then
      log:error("js-debug terminal: Failed to create TCP server")
      return false
    end

    -- Bind to random port on localhost
    local ok, bind_err = server:bind("127.0.0.1", 0)
    if not ok then
      log:error("js-debug terminal: Failed to bind server", { error = bind_err })
      server:close()
      server = nil
      return false
    end

    -- Get assigned port
    local sockname = server:getsockname()
    if not sockname then
      log:error("js-debug terminal: Failed to get server address")
      server:close()
      server = nil
      return false
    end
    server_port = sockname.port

    -- Start listening
    ok, bind_err = server:listen(128, function(err)
      if err then
        log:error("js-debug terminal: Listen error", { error = err })
        return
      end

      local client = vim.uv.new_tcp()
      server:accept(client)
      handle_client(client)
    end)

    if not ok then
      log:error("js-debug terminal: Failed to listen", { error = bind_err })
      server:close()
      server = nil
      server_port = nil
      return false
    end

    log:info("js-debug terminal: Server started", { port = server_port })
    return true
  end

  ---Create a debug terminal
  ---@return number? bufnr Buffer number of the terminal, or nil on failure
  local function create_terminal()
    -- Ensure server is running
    if not start_server() then
      vim.notify("[neodap] Failed to start js-debug terminal server", vim.log.levels.ERROR)
      return nil
    end

    -- Create terminal buffer in a split
    local current_win = vim.api.nvim_get_current_win()
    vim.cmd("belowright split")
    local win = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, bufnr)

    -- Configure buffer
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].buflisted = true

    -- Configure window
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"

    -- Build environment with NODE_OPTIONS
    local env = {
      NODE_OPTIONS = "--require=" .. bootloader_path,
      NEODAP_DEBUG_PORT = tostring(server_port),
    }

    -- Start shell in terminal
    local jobid
    vim.api.nvim_buf_call(bufnr, function()
      local termopen_fn = vim.fn.has("nvim-0.11") == 1 and vim.fn.jobstart or vim.fn.termopen
      local term_opts = {
        env = env,
        on_exit = function(_, code)
          log:debug("js-debug terminal exited", { bufnr = bufnr, code = code })
          terminals[bufnr] = nil
        end,
      }
      -- nvim 0.11+ needs term=true for jobstart to create terminal
      if vim.fn.has("nvim-0.11") == 1 then
        term_opts.term = true
      end
      jobid = termopen_fn(shell, term_opts)
    end)

    -- Set buffer name
    pcall(vim.api.nvim_buf_set_name, bufnr, "[dap-js-debug-terminal] " .. bufnr)

    -- Track terminal
    terminals[bufnr] = {
      jobid = jobid,
      win = win,
    }

    -- Enter insert mode in terminal
    vim.api.nvim_set_current_win(win)
    vim.cmd("startinsert")

    log:info("js-debug terminal created", { bufnr = bufnr, port = server_port })

    return bufnr
  end

  ---Enable js-debug in an existing terminal by exporting env vars
  ---@param bufnr? number Buffer number of the terminal (default: current buffer)
  ---@return boolean success
  local function enable_in_terminal(bufnr)
    -- Ensure server is running
    if not start_server() then
      vim.notify("[neodap] Failed to start js-debug terminal server", vim.log.levels.ERROR)
      return false
    end

    bufnr = bufnr or vim.api.nvim_get_current_buf()

    -- Check if it's a terminal buffer
    if vim.bo[bufnr].buftype ~= "terminal" then
      vim.notify("[neodap] Buffer is not a terminal", vim.log.levels.ERROR)
      return false
    end

    -- Get the terminal job ID
    local jobid = vim.b[bufnr].terminal_job_id
    if not jobid then
      vim.notify("[neodap] Could not get terminal job ID", vim.log.levels.ERROR)
      return false
    end

    -- Build the export command
    local export_cmd = string.format(
      'export NODE_OPTIONS="--require=%s" NEODAP_DEBUG_PORT=%d\n',
      bootloader_path,
      server_port
    )

    -- Send to terminal
    vim.fn.chansend(jobid, export_cmd)

    log:info("js-debug enabled in terminal", { bufnr = bufnr, port = server_port })

    return true
  end

  ---Stop the server and clean up
  local function cleanup()
    -- Close pending connections
    for client, _ in pairs(pending_connections) do
      pcall(function() client:close() end)
    end
    pending_connections = {}

    -- Stop terminals
    for bufnr, term in pairs(terminals) do
      if term.jobid then
        pcall(vim.fn.jobstop, term.jobid)
      end
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    terminals = {}

    -- Close server
    if server then
      server:close()
      server = nil
      server_port = nil
      log:info("js-debug terminal: Server stopped")
    end
  end

  -- Register user commands
  vim.api.nvim_create_user_command("DapJsDebugTerminal", function()
    create_terminal()
  end, {
    desc = "Create a js-debug terminal for automatic Node.js debugging",
  })

  vim.api.nvim_create_user_command("DapJsDebugTerminalEnable", function()
    enable_in_terminal()
  end, {
    desc = "Enable js-debug in the current terminal",
  })

  -- Return API
  return {
    create_terminal = create_terminal,
    enable_in_terminal = enable_in_terminal,
    cleanup = cleanup,
    get_port = function() return server_port end,
  }
end
