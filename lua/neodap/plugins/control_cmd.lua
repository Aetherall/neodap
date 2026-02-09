-- Plugin: Debug control commands
--
-- Session commands:
--   :DapContinue                           - continue focused thread
--   :DapContinue @session/threads          - continue all threads in session
--   :DapPause                              - pause focused thread
--   :DapPause sessions/threads             - pause all threads
--   :DapTerminate                          - terminate focused session
--   :DapTerminate sessions                 - terminate all sessions
--   :DapDisconnect                         - disconnect from focused session (keeps debuggee running)
--   :DapDisconnect sessions                - disconnect from all sessions
--   :DapRestart                            - restart focused session (if adapter supports it)
--
-- Config commands:
--   :DapTerminateConfig                    - terminate all sessions in focused Config
--   :DapRestartConfig                      - restart focused Config (terminate and relaunch all)
--   :DapRestartRoot                        - restart root session of focused session (within same Config)

local query = require("neodap.plugins.utils.query")
local log = require("neodap.logger")

---@param debugger neodap.entities.Debugger
---@return table api Plugin API
return function(debugger)
  local api = {}

  ---Continue execution of threads
  ---@param url? string Optional URL to query threads
  ---@return boolean success
  function api.continue(url)
    local entities = query.query_or_default(debugger, url, function()
      return debugger.ctx.thread:get()
    end)

    if #entities == 0 then
      log:warn("DapContinue: No thread found")
      return false
    end

    local count = 0
    for _, entity in ipairs(entities) do
      if entity:type() == "Thread" and entity.continue then
        entity:continue()
        count = count + 1
      end
    end

    if count > 0 then
      log:info("Continued: " .. (debugger.ctx.session:get() and debugger.ctx.session:get().uri:get() or "all threads"))
      return true
    else
      log:warn("DapContinue: No threads to continue")
      return false
    end
  end

  ---Pause execution of threads
  ---@param url? string Optional URL to query threads
  ---@return boolean success
  function api.pause(url)
    local entities = query.query_or_default(debugger, url, function()
      return debugger.ctx.thread:get()
    end)

    if #entities == 0 then
      log:warn("DapPause: No thread found")
      return false
    end

    local count = 0
    for _, entity in ipairs(entities) do
      if entity:type() == "Thread" and entity.pause then
        entity:pause()
        count = count + 1
      end
    end

    if count > 0 then
      log:info("Paused: " .. (debugger.ctx.session:get() and debugger.ctx.session:get().uri:get() or "all threads"))
      return true
    else
      log:warn("DapPause: No threads to pause")
      return false
    end
  end

  ---Terminate sessions
  ---@param url? string Optional URL to query sessions
  ---@return boolean success
  function api.terminate(url)
    local entities = query.query_or_default(debugger, url, function()
      return debugger.ctx.session:get()
    end)

    if #entities == 0 then
      log:warn("DapTerminate: No session found")
      return false
    end

    local count = 0
    for _, entity in ipairs(entities) do
      if entity:type() == "Session" and entity.terminate then
        entity:terminate()
        count = count + 1
      end
    end

    if count > 0 then
      log:info("Terminated sessions")
      return true
    else
      log:warn("DapTerminate: No sessions to terminate")
      return false
    end
  end

  ---Disconnect from sessions (keeps debuggee running)
  ---@param url? string Optional URL to query sessions
  ---@return boolean success
  function api.disconnect(url)
    local entities = query.query_or_default(debugger, url, function()
      return debugger.ctx.session:get()
    end)

    if #entities == 0 then
      log:warn("DapDisconnect: No session found")
      return false
    end

    local count = 0
    for _, entity in ipairs(entities) do
      if entity:type() == "Session" and entity.disconnect then
        entity:disconnect()
        count = count + 1
      end
    end

    if count > 0 then
      log:info("Disconnected from sessions")
      return true
    else
      log:warn("DapDisconnect: No sessions to disconnect")
      return false
    end
  end

  ---Restart sessions (if adapter supports it)
  ---@param url? string Optional URL to query sessions
  ---@return boolean success
  function api.restart(url)
    local entities = query.query_or_default(debugger, url, function()
      return debugger.ctx.session:get()
    end)

    if #entities == 0 then
      log:warn("DapRestart: No session found")
      return false
    end

    local count, skipped = 0, 0
    for _, entity in ipairs(entities) do
      if entity:type() == "Session" then
        if entity.supportsRestart and entity:supportsRestart() then
          entity:restart()
          count = count + 1
        else
          skipped = skipped + 1
        end
      end
    end

    if count > 0 then
      log:info("Restarted sessions")
      return true
    elseif skipped > 0 then
      log:warn("DapRestart: Adapter does not support restart")
      return false
    else
      log:warn("DapRestart: No sessions to restart")
      return false
    end
  end

  ---Terminate Config (all sessions in the Config)
  ---@return boolean success
  function api.terminate_config()
    local session = debugger.ctx.session:get()
    if not session then
      log:warn("DapTerminateConfig: No focused session")
      return false
    end

    local cfg = session.config:get()
    if not cfg then
      log:warn("DapTerminateConfig: Session has no Config")
      return false
    end

    cfg:terminate()
    log:info("Terminated Config: " .. cfg:displayName())
    return true
  end

  ---Restart Config (terminate and relaunch all)
  ---@return boolean success
  function api.restart_config()
    local session = debugger.ctx.session:get()
    if not session then
      log:warn("DapRestartConfig: No focused session")
      return false
    end

    local cfg = session.config:get()
    if not cfg then
      log:warn("DapRestartConfig: Session has no Config")
      return false
    end

    cfg:restart()
    log:info("Restarting Config: " .. cfg:displayName())
    return true
  end

  ---Restart the root session of the focused session (within same Config)
  ---@return boolean success
  function api.restart_root()
    local session = debugger.ctx.session:get()
    if not session then
      log:warn("DapRestartRoot: No focused session")
      return false
    end

    session:restartRoot()
    return true
  end

  ---Terminate all Configs (all debug sessions)
  ---@return number count Number of Configs terminated
  function api.terminate_all()
    local count = 0
    for cfg in debugger.activeConfigs:iter() do
      cfg:terminate()
      count = count + 1
    end
    if count > 0 then
      log:info("Terminated " .. count .. " Config(s)")
    else
      log:info("No active Configs to terminate")
    end
    return count
  end

  local thread_completions = {
    "@session/threads",
    "@session/threads(state=stopped)",
    "@session/threads(state=running)",
    "sessions/threads",
    "sessions/threads(state=stopped)",
  }

  local session_completions = {
    "@session",
    "sessions",
    "sessions(state=running)",
  }

  vim.api.nvim_create_user_command("DapContinue", function(opts)
    local url = opts.args ~= "" and opts.args or nil
    api.continue(url)
  end, {
    nargs = "?",
    desc = "Continue thread execution",
    complete = function(arglead)
      return vim.tbl_filter(function(p)
        return p:match("^" .. vim.pesc(arglead))
      end, thread_completions)
    end,
  })

  vim.api.nvim_create_user_command("DapPause", function(opts)
    local url = opts.args ~= "" and opts.args or nil
    api.pause(url)
  end, {
    nargs = "?",
    desc = "Pause thread execution",
    complete = function(arglead)
      return vim.tbl_filter(function(p)
        return p:match("^" .. vim.pesc(arglead))
      end, thread_completions)
    end,
  })

  vim.api.nvim_create_user_command("DapTerminate", function(opts)
    local url = opts.args ~= "" and opts.args or nil
    api.terminate(url)
  end, {
    nargs = "?",
    desc = "Terminate debug session",
    complete = function(arglead)
      return vim.tbl_filter(function(p)
        return p:match("^" .. vim.pesc(arglead))
      end, session_completions)
    end,
  })

  vim.api.nvim_create_user_command("DapDisconnect", function(opts)
    local url = opts.args ~= "" and opts.args or nil
    api.disconnect(url)
  end, {
    nargs = "?",
    desc = "Disconnect from debug session (keeps debuggee running)",
    complete = function(arglead)
      return vim.tbl_filter(function(p)
        return p:match("^" .. vim.pesc(arglead))
      end, session_completions)
    end,
  })

  vim.api.nvim_create_user_command("DapRestart", function(opts)
    local url = opts.args ~= "" and opts.args or nil
    api.restart(url)
  end, {
    nargs = "?",
    desc = "Restart debug session (if adapter supports it)",
    complete = function(arglead)
      return vim.tbl_filter(function(p)
        return p:match("^" .. vim.pesc(arglead))
      end, session_completions)
    end,
  })

  vim.api.nvim_create_user_command("DapTerminateConfig", function()
    api.terminate_config()
  end, {
    desc = "Terminate all sessions in the focused Config",
  })

  vim.api.nvim_create_user_command("DapRestartConfig", function()
    api.restart_config()
  end, {
    desc = "Restart the focused Config (terminate and relaunch all)",
  })

  vim.api.nvim_create_user_command("DapRestartRoot", function()
    api.restart_root()
  end, {
    desc = "Restart the root session of the focused session (within same Config)",
  })

  vim.api.nvim_create_user_command("DapTerminateAll", function()
    api.terminate_all()
  end, {
    desc = "Terminate all Configs (all debug sessions)",
  })

  function api.cleanup()
    pcall(vim.api.nvim_del_user_command, "DapContinue")
    pcall(vim.api.nvim_del_user_command, "DapPause")
    pcall(vim.api.nvim_del_user_command, "DapTerminate")
    pcall(vim.api.nvim_del_user_command, "DapDisconnect")
    pcall(vim.api.nvim_del_user_command, "DapRestart")
    pcall(vim.api.nvim_del_user_command, "DapTerminateConfig")
    pcall(vim.api.nvim_del_user_command, "DapRestartConfig")
    pcall(vim.api.nvim_del_user_command, "DapRestartRoot")
    pcall(vim.api.nvim_del_user_command, "DapTerminateAll")
  end

  return api
end
