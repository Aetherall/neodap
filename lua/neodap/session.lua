-- Core session management for DAP
--
-- Provides session connectivity via:
-- - TCP connection (for server/tcp adapters)
-- - stdio wrapping (for stdio adapters)
--
-- Returns ProcessHandle interface for DAP protocol communication.

local log = require("neodap.logger")

local M = {}

---@class neodap.session.ConnectOpts
---@field process? neodap.ProcessHandle Existing process handle (for stdio adapters)
---@field host? string TCP host (for server/tcp adapters)
---@field port? number TCP port (for server/tcp adapters)
---@field retries? number TCP connection retries (default: 5)
---@field retry_delay? number TCP retry delay in ms (default: 100)
---@field timeout? number TCP timeout in ms (default: 5000)
---@field on_connect? fun(handle: neodap.ProcessHandle) Callback when connected (for async TCP)

---Connect to create a session
---@param opts neodap.session.ConnectOpts
---@return neodap.ProcessHandle?
function M.connect(opts)
  -- stdio mode: wrap existing process handle
  if opts.process then
    return M.connect_stdio(opts.process)
  end

  -- TCP mode: connect to adapter server
  if opts.host and opts.port then
    return M.connect_tcp(opts)
  end

  error("session.connect requires either process or host/port")
end

---Wrap an existing process handle for session communication
---@param process neodap.ProcessHandle
---@return neodap.ProcessHandle
function M.connect_stdio(process)
  -- For stdio, we just forward the process handle
  -- The session uses the same stdio as the adapter
  return process
end

---Connect to adapter via TCP
---@param opts neodap.session.ConnectOpts
---@return neodap.ProcessHandle?
function M.connect_tcp(opts)
  local retries = opts.retries or 5
  local retry_delay = opts.retry_delay or 100
  local timeout_ms = opts.timeout or 5000

  local data_callbacks = {}
  local stderr_callbacks = {}
  local exit_callbacks = {}
  local connected = false
  local closed = false
  local tcp = nil
  local timeout_timer = nil
  local handle = nil

  local function close_timeout()
    if timeout_timer then
      timeout_timer:stop()
      timeout_timer:close()
      timeout_timer = nil
    end
  end

  local function cleanup()
    close_timeout()
    if tcp and not tcp:is_closing() then
      tcp:close()
    end
  end

  local function notify_exit(code)
    if closed then return end
    closed = true
    cleanup()
    vim.schedule(function()
      for _, cb in ipairs(exit_callbacks) do
        cb(code)
      end
    end)
  end

  local function try_connect(attempts_left)
    tcp = vim.uv.new_tcp()

    tcp:connect(opts.host, opts.port, function(err)
      if err then
        tcp:close()
        if attempts_left > 0 and err:match("ECONNREFUSED") then
          local retry_timer = vim.uv.new_timer()
          retry_timer:start(retry_delay, 0, function()
            retry_timer:close()
            try_connect(attempts_left - 1)
          end)
        else
          log:error("TCP connection failed", { host = opts.host, port = opts.port, error = err })
          vim.schedule(function()
            vim.notify("DAP: Connection failed to " .. opts.host .. ":" .. opts.port .. "\n" .. err, vim.log.levels.ERROR)
          end)
          notify_exit(-1)
        end
        return
      end

      connected = true
      close_timeout()
      log:debug("TCP connected", { host = opts.host, port = opts.port })

      tcp:read_start(function(read_err, chunk)
        if chunk then
          -- Schedule to avoid fast event context issues
          vim.schedule(function()
            for _, cb in ipairs(data_callbacks) do
              cb(chunk)
            end
          end)
        elseif read_err then
          notify_exit(-1)
        else
          notify_exit(0)
        end
      end)

      -- Notify async caller if provided
      if opts.on_connect and handle then
        vim.schedule(function()
          opts.on_connect(handle)
        end)
      end
    end)
  end

  -- Build handle (available immediately, TCP connects async)
  handle = {
    write = function(data)
      if tcp and not tcp:is_closing() then
        tcp:write(data)
      end
    end,
    on_data = function(cb)
      table.insert(data_callbacks, cb)
    end,
    on_stderr = function(cb)
      -- TCP connections don't have stderr
      table.insert(stderr_callbacks, cb)
    end,
    on_exit = function(cb)
      if closed then
        vim.schedule(function() cb(-1) end)
      else
        table.insert(exit_callbacks, cb)
      end
    end,
    kill = function()
      notify_exit(0)
    end,
  }

  -- Overall timeout
  timeout_timer = vim.uv.new_timer()
  timeout_timer:start(timeout_ms, 0, function()
    if not connected and not closed then
      log:error("TCP connection timeout", { host = opts.host, port = opts.port, timeout_ms = timeout_ms })
      vim.schedule(function()
        vim.notify("DAP: Connection timeout to " .. opts.host .. ":" .. opts.port, vim.log.levels.ERROR)
      end)
      notify_exit(-1)
    end
  end)

  try_connect(retries)

  return handle
end

return M
