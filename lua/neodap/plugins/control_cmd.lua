-- Plugin: DapContinue, DapPause, and DapTerminate commands
--
-- Usage:
--   :DapContinue                           - continue focused thread
--   :DapContinue @session/threads          - continue all threads in session
--   :DapPause                              - pause focused thread
--   :DapPause sessions/threads             - pause all threads
--   :DapTerminate                          - terminate focused session
--   :DapTerminate sessions                 - terminate all sessions

local query = require("neodap.plugins.utils.query")

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
      vim.notify("DapContinue: No thread found", vim.log.levels.WARN)
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
      return true
    else
      vim.notify("DapContinue: No threads to continue", vim.log.levels.WARN)
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
      vim.notify("DapPause: No thread found", vim.log.levels.WARN)
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
      return true
    else
      vim.notify("DapPause: No threads to pause", vim.log.levels.WARN)
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
      vim.notify("DapTerminate: No session found", vim.log.levels.WARN)
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
      return true
    else
      vim.notify("DapTerminate: No sessions to terminate", vim.log.levels.WARN)
      return false
    end
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

  function api.cleanup()
    pcall(vim.api.nvim_del_user_command, "DapContinue")
    pcall(vim.api.nvim_del_user_command, "DapPause")
    pcall(vim.api.nvim_del_user_command, "DapTerminate")
  end

  return api
end
