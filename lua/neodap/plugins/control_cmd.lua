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
local E = require("neodap.error")

---@param debugger neodap.entities.Debugger
---@return table api Plugin API
return function(debugger)
  local api = {}

  ---Query entities, apply method, throw on failure.
  ---Errors are caught by E.create_command and reported via E.report().
  ---@param url? string Optional URL to query
  ---@param default_fn fun(): table? Fallback entity if no URL
  ---@param type_name string Entity type to match
  ---@param method string Method to call
  ---@param cmd_name string Command name for error messages
  local function query_and_apply(url, default_fn, type_name, method, cmd_name)
    local entities = query.query_or_default(debugger, url, default_fn)
    if #entities == 0 then
      error(E.warn(cmd_name .. ": No " .. type_name:lower() .. " found"), 0)
    end
    local count = apply_to_entities(entities, type_name, method)
    if count == 0 then
      error(E.warn(cmd_name .. ": No " .. type_name:lower() .. "s matched"), 0)
    end
  end

  local function default_thread() return debugger.ctx.thread:get() end
  local function default_session() return debugger.ctx.session:get() end

  function api.continue(url) query_and_apply(url, default_thread, "Thread", "continue", "DapContinue") end
  function api.pause(url)    query_and_apply(url, default_thread, "Thread", "pause", "DapPause") end
  function api.terminate(url)
    local ok, err = pcall(query_and_apply, url, default_session, "Session", "terminate", "DapTerminate")
    if ok then return end
    -- Safety net: if no URL was given and no focused session was found,
    -- terminate all remaining sessions (user clearly wants to stop debugging)
    if not url and api.terminate_all() > 0 then return end
    error(err, 0) -- re-throw
  end
  function api.disconnect(url) query_and_apply(url, default_session, "Session", "disconnect", "DapDisconnect") end

  ---Restart sessions (if adapter supports it).
  ---Throws on failure (caught by E.create_command).
  ---@param url? string Optional URL to query sessions
  function api.restart(url)
    local entities = query.query_or_default(debugger, url, function()
      return debugger.ctx.session:get()
    end)

    if #entities == 0 then
      error(E.warn("DapRestart: No session found"), 0)
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
      return
    end
    if skipped > 0 then
      error(E.warn("DapRestart: Adapter does not support restart"), 0)
    end
    error(E.warn("DapRestart: No sessions to restart"), 0)
  end

  ---Terminate Config (all sessions in the Config).
  ---Throws on failure (caught by E.create_command).
  function api.terminate_config()
    local cfg = debugger.ctx:focusedConfig()
    if not cfg then error(E.warn("DapTerminateConfig: No focused Config"), 0) end
    cfg:terminate()
    log:info("Terminated Config: " .. cfg:displayName())
  end

  ---Restart Config (terminate and relaunch all).
  ---Throws on failure (caught by E.create_command).
  function api.restart_config()
    local cfg = debugger.ctx:focusedConfig()
    if not cfg then error(E.warn("DapRestartConfig: No focused Config"), 0) end
    cfg:restart()
    log:info("Restarting Config: " .. cfg:displayName())
  end

  ---Restart the root session of the focused session (within same Config).
  ---Throws on failure (caught by E.create_command).
  function api.restart_root()
    local session = debugger.ctx.session:get()
    if not session then
      error(E.warn("DapRestartRoot: No focused session"), 0)
    end
    session:restartRoot()
  end

  ---Terminate all Configs (all debug sessions)
  ---@return number count Number of Configs terminated
  function api.terminate_all()
    local count = 0
    for cfg in debugger.activeConfigs:iter() do
      cfg:terminate()
      count = count + 1
    end
    if count == 0 then
      log:debug("DapTerminateAll: no active configs")
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

  E.create_command("DapContinue", function(opts)
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

  E.create_command("DapPause", function(opts)
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

  E.create_command("DapTerminate", function(opts)
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

  E.create_command("DapDisconnect", function(opts)
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

  E.create_command("DapRestart", function(opts)
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

  E.create_command("DapTerminateConfig", function()
    api.terminate_config()
  end, {
    desc = "Terminate all sessions in the focused Config",
  })

  E.create_command("DapRestartConfig", function()
    api.restart_config()
  end, {
    desc = "Restart the focused Config (terminate and relaunch all)",
  })

  E.create_command("DapRestartRoot", function()
    api.restart_root()
  end, {
    desc = "Restart the root session of the focused session (within same Config)",
  })

  E.create_command("DapTerminateAll", function()
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
