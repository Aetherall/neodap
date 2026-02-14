-- Plugin: Automatically jump to source when a thread stops
-- Opens the file and positions cursor at the stopped frame location

local a = require("neodap.async")
local navigate = require("neodap.plugins.utils.navigate")
local log = require("neodap.logger")

---@class JumpStopConfig
---@field enabled? boolean Initial enabled state (default: true)
---@field pick_window? fun(path: string, line: number, column: number): number? Full override for window selection (return nil to skip jump)
---@field create_window? fun(): number Fallback when no suitable window exists (default: vsplit)

local default_config = {
  enabled = true,
  pick_window = nil, -- nil = use default logic (find existing window with buffer, or non-DAP window)
  create_window = nil, -- nil = use vsplit
}

---@param debugger neodap.entities.Debugger
---@param config? JumpStopConfig
---@return table api Plugin API
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local api = {}
  local enabled = config.enabled

  -- Scoped subscriptions - cleanup is automatic via debugger:use()
  debugger.sessions:each(function(session)
    -- Watch threads using onStopped lifecycle hook
    session.threads:each(function(thread)
      -- onStopped runs in async context when thread enters "stopped"
      thread:onStopped(function()
        if not enabled then return end

        -- Only jump for threads in the focused session context
        local thread_session = thread.session:get()
        if thread_session and not debugger.ctx:isInFocusedContext(thread_session) then return end

        -- Load stack and jump to top frame
        local stack = thread:loadCurrentStack()
        if not stack then return end

        local frame = debugger.ctx:focusThread(thread)
        if frame then
          a.wait(a.main, "jump_stop:schedule")
          navigate.goto_frame(frame, {
            pick_window = config.pick_window,
            create_window = config.create_window,
          })
        end
      end)
    end)

    -- Auto-fetch threads when session stops with no threads
    session.state:useOnMain(function(state)
      if not enabled then return end
      if state ~= "stopped" then return end

      local has_threads = session.firstThread:get() ~= nil
      if not has_threads then
        session:fetchThreads()
      end
    end)
  end)

  ---Enable auto-jump
  function api.enable()
    enabled = true
  end

  ---Disable auto-jump
  function api.disable()
    enabled = false
  end

  ---Toggle auto-jump
  function api.toggle()
    enabled = not enabled
    return enabled
  end

  ---Check if enabled
  function api.is_enabled()
    return enabled
  end

  -- Toggle command
  vim.api.nvim_create_user_command("DapJumpStop", function(opts)
    local arg = opts.args:lower()
    if arg == "on" then
      api.enable()
      log:info("DapJumpStop: enabled")
    elseif arg == "off" then
      api.disable()
      log:info("DapJumpStop: disabled")
    elseif arg == "status" then
      log:info("DapJumpStop", { enabled = enabled })
    else
      local is_enabled = api.toggle()
      log:info("DapJumpStop", { enabled = is_enabled })
    end
  end, {
    nargs = "?",
    desc = "Toggle auto-jump on stopped threads",
    complete = function()
      return { "on", "off", "status" }
    end,
  })

  return api
end
