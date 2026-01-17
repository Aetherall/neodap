-- Plugin: Automatically jump to source when a thread stops
-- Opens the file and positions cursor at the stopped frame location

local a = require("neodap.async")
local navigate = require("neodap.plugins.utils.navigate")

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

        -- Check if this thread's session is focused (or no focus set)
        local focused_session = debugger.ctx.session:get()
        local thread_session = thread.session:get()

        if focused_session and thread_session and focused_session ~= thread_session then
          return -- Different session is focused, don't steal focus
        end

        -- Load stack and jump to top frame
        local stack = thread:loadCurrentStack()
        if not stack then return end

        local top_frame = stack.topFrame:get()
        if top_frame then
          a.wait(a.main, "jump_stop:schedule")
          navigate.goto_frame(top_frame, {
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
      vim.notify("DapJumpStop: enabled")
    elseif arg == "off" then
      api.disable()
      vim.notify("DapJumpStop: disabled")
    elseif arg == "status" then
      vim.notify("DapJumpStop: " .. (enabled and "enabled" or "disabled"))
    else
      local is_enabled = api.toggle()
      vim.notify("DapJumpStop: " .. (is_enabled and "enabled" or "disabled"))
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
