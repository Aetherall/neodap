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
local apply_to_entities = require("neodap.plugins.utils.apply_to_entities")
local log = require("neodap.logger")

---@param debugger neodap.entities.Debugger
---@return table api Plugin API
return function(debugger)
  local api = {}

  ---Query entities, apply method, log result
  ---@param url? string Optional URL to query
  ---@param default_fn fun(): table? Fallback entity if no URL
  ---@param type_name string Entity type to match
  ---@param method string Method to call
  ---@param cmd_name string Command name for log messages
  ---@return boolean success
  local function query_and_apply(url, default_fn, type_name, method, cmd_name)
    local entities = query.query_or_default(debugger, url, default_fn)
    if #entities == 0 then
      log:warn(cmd_name .. ": No " .. type_name:lower() .. " found")
      return false
    end
    local count = apply_to_entities(entities, type_name, method)
    if count > 0 then
      return true
    else
      log:warn(cmd_name .. ": No " .. type_name:lower() .. "s matched")
      return false
    end
  end

  local function default_thread() return debugger.ctx.thread:get() end
  local function default_session() return debugger.ctx.session:get() end

  function api.continue(url)  return query_and_apply(url, default_thread, "Thread", "continue", "DapContinue") end
  function api.pause(url)     return query_and_apply(url, default_thread, "Thread", "pause", "DapPause") end
  function api.terminate(url) return query_and_apply(url, default_session, "Session", "terminate", "DapTerminate") end
  function api.disconnect(url) return query_and_apply(url, default_session, "Session", "disconnect", "DapDisconnect") end

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
    local cfg = debugger.ctx:focusedConfig()
    if not cfg then log:warn("DapTerminateConfig: No focused Config"); return false end
    cfg:terminate()
    log:info("Terminated Config: " .. cfg:displayName())
    return true
  end

  ---Restart Config (terminate and relaunch all)
  ---@return boolean success
  function api.restart_config()
    local cfg = debugger.ctx:focusedConfig()
    if not cfg then log:warn("DapRestartConfig: No focused Config"); return false end
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
