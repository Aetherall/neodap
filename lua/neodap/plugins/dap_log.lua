-- Plugin: DAP protocol logger
-- Logs all DAP communication to session-specific log files in /tmp
--
-- Each session gets its own log file: /tmp/neodap-dap/<session_id>.log
-- Format: [timestamp] direction type: json
--
-- Example:
--   [2024-01-25 10:30:15.123] --> request initialize: {"clientID":"dap-lua",...}
--   [2024-01-25 10:30:15.456] <-- response initialize: {"supportsConfigurationDoneRequest":true,...}
--   [2024-01-25 10:30:15.789] <-- event initialized: {}

local context = require("neodap.plugins.dap.context")
local log = require("neodap.logger")

-- All known DAP events to subscribe to
local DAP_EVENTS = {
  "initialized", "stopped", "continued", "exited", "terminated",
  "thread", "output", "breakpoint", "module", "loadedSource",
  "process", "capabilities", "progressStart", "progressUpdate",
  "progressEnd", "invalidated", "memory",
}

---@class neodap.DapLogConfig
---@field log_dir? string Directory for log files (default: /tmp/neodap-dap)
---@field pretty? boolean Pretty-print JSON (default: false)

---@param debugger neodap.entities.Debugger
---@param config? neodap.DapLogConfig
return function(debugger, config)
  config = config or {}
  local log_dir = config.log_dir or "/tmp/neodap-dap"
  local pretty = config.pretty or false

  -- Create log directory
  vim.fn.mkdir(log_dir, "p")

  -- Track log files and wrapped clients per session
  local session_logs = {} -- session_id -> { file, wrapped }

  ---Get timestamp with milliseconds
  ---@return string
  local function timestamp()
    local sec, usec = vim.uv.gettimeofday()
    local ms = math.floor(usec / 1000)
    return os.date("%Y-%m-%d %H:%M:%S", sec) .. string.format(".%03d", ms)
  end

  ---Encode data to JSON
  ---@param data any
  ---@return string
  local function encode(data)
    if pretty then
      -- Use vim.inspect for readable format
      return vim.inspect(data, { newline = " ", indent = "" })
    else
      local ok, json = pcall(vim.json.encode, data)
      return ok and json or tostring(data)
    end
  end

  ---Write a log entry
  ---@param session_id string
  ---@param direction string "--> " for outgoing, "<-- " for incoming
  ---@param msg_type string "request", "response", "event", etc.
  ---@param command string The command or event name
  ---@param data any The message body/arguments
  local function write_log(session_id, direction, msg_type, command, data)
    local state = session_logs[session_id]
    if not state or not state.file then return end

    local line = string.format("[%s] %s %s %s: %s\n",
      timestamp(), direction, msg_type, command, encode(data))
    state.file:write(line)
    state.file:flush()
  end

  ---Set up logging for a session
  ---@param session neodap.entities.Session
  local function setup_session_logging(session)
    local session_id = session.sessionId:get()
    if session_logs[session_id] then return end -- Already set up

    local dap_session = context.get_dap_session(session)
    if not dap_session or not dap_session.client then
      -- Session not ready yet, retry later
      vim.defer_fn(function()
        if not session_logs[session_id] then
          setup_session_logging(session)
        end
      end, 100)
      return
    end

    -- Create log file
    local log_path = log_dir .. "/" .. session_id .. ".log"
    local file = io.open(log_path, "w")
    if not file then
      log:warn("Failed to create DAP log file: " .. log_path)
      return
    end

    -- Write header
    local config_name = session.name:get() or "unknown"
    file:write(string.format("-- DAP Log for session %s (%s)\n", session_id, config_name))
    file:write(string.format("-- Started: %s\n", timestamp()))
    file:write(string.format("-- Log file: %s\n\n", log_path))
    file:flush()

    session_logs[session_id] = { file = file, wrapped = true }

    local client = dap_session.client

    -- Wrap the request method to log requests and responses
    local original_request = client.request
    client.request = function(self, command, arguments, callback)
      write_log(session_id, "-->", "request", command, arguments)

      -- Wrap callback to log response
      local wrapped_callback = callback and function(err, body)
        if err then
          write_log(session_id, "<--", "error", command, { error = err, body = body })
        else
          write_log(session_id, "<--", "response", command, body)
        end
        callback(err, body)
      end

      return original_request(self, command, arguments, wrapped_callback)
    end

    -- Subscribe to all events and log them
    for _, event in ipairs(DAP_EVENTS) do
      dap_session:on(event, function(body)
        write_log(session_id, "<--", "event", event, body)
      end)
    end

    -- Log reverse requests (runInTerminal, startDebugging)
    local original_on_request = client.on_request
    client.on_request = function(self, command, handler)
      local wrapped_handler = function(arguments, respond)
        write_log(session_id, "<--", "reverse-request", command, arguments)

        local wrapped_respond = function(response_body, err)
          if err then
            write_log(session_id, "-->", "reverse-error", command, { error = err })
          else
            write_log(session_id, "-->", "reverse-response", command, response_body)
          end
          respond(response_body, err)
        end

        return handler(arguments, wrapped_respond)
      end

      return original_on_request(self, command, wrapped_handler)
    end

    log:info("DAP logging enabled for session " .. session_id, { path = log_path })
  end

  ---Clean up logging for a session
  ---@param session_id string
  local function cleanup_session_logging(session_id)
    local state = session_logs[session_id]
    if state and state.file then
      state.file:write(string.format("\n-- Session ended: %s\n", timestamp()))
      state.file:close()
    end
    session_logs[session_id] = nil
  end

  -- Watch for new sessions
  debugger.sessions:each(function(session)
    setup_session_logging(session)

    -- Clean up when session is terminated
    session.state:use(function(state)
      if state == "terminated" then
        local session_id = session.sessionId:get()
        cleanup_session_logging(session_id)
      end
    end)
  end)

  -- API
  local api = {}

  ---Get log file path for a session
  ---@param session neodap.entities.Session
  ---@return string?
  function api.get_log_path(session)
    local session_id = session.sessionId:get()
    return log_dir .. "/" .. session_id .. ".log"
  end

  ---Open log file for a session in a buffer
  ---@param session neodap.entities.Session
  function api.open(session)
    local path = api.get_log_path(session)
    if path and vim.fn.filereadable(path) == 1 then
      vim.cmd("edit " .. vim.fn.fnameescape(path))
    else
      vim.notify("No DAP log file for this session", vim.log.levels.WARN)
    end
  end

  -- Command to open log for focused session
  vim.api.nvim_create_user_command("DapLog", function()
    local session = debugger.ctx.session:get()
    if not session then
      vim.notify("No focused session", vim.log.levels.WARN)
      return
    end
    api.open(session)
  end, { desc = "Open DAP protocol log for focused session" })

  function api.cleanup()
    pcall(vim.api.nvim_del_user_command, "DapLog")
  end

  return api
end
