-- Plugin: Automatically jump to source when a thread stops
-- Jumps to the top frame's location on breakpoint hits, stepping, or exceptions

local neostate = require("neostate")

---@class JumpStopConfig
---@field enabled? boolean Initial enabled state (default: true)
---@field scope? "context"|"all" Which sessions to jump for (default: "context")

---@param debugger Debugger
---@param config? JumpStopConfig
---@return function cleanup
return function(debugger, config)
  config = config or {}
  local enabled = config.enabled ~= false  -- Default true
  local scope = config.scope or "context"

  ---Check if we should jump for this thread based on scope config
  ---@param thread Thread
  ---@return boolean
  local function should_jump(thread)
    if scope ~= "context" then return true end

    -- Get context session
    local ctx_session = debugger:resolve_contextual_one("@session", "session"):get()
    if not ctx_session then return true end  -- No context set, allow jump

    return thread.session.id == ctx_session.id
  end

  ---Jump to a frame's source location
  ---@param frame Frame
  local function jump_to_frame(frame)
    if not frame or not frame.source then return end

    local edit_target = frame.source.path or frame.source:location_uri()
    vim.cmd.edit(edit_target)
    vim.api.nvim_win_set_cursor(0, { frame.line, (frame.column or 1) - 1 })
  end

  -- Listen to all threads and their stop events
  local unsubscribe = debugger:onThread(function(thread)
    return thread:onStopped(function()
      if not enabled then return end
      if not should_jump(thread) then return end

      vim.schedule(function()
        neostate.void(function()
          local stack = thread:stack()
          if not stack then return end

          local top = stack:top()
          jump_to_frame(top)
        end)()
      end)
    end)
  end)

  -- Toggle command
  vim.api.nvim_create_user_command("DapJumpStop", function(opts)
    local arg = opts.args:lower()
    if arg == "on" then
      enabled = true
      vim.notify("DapJumpStop: enabled")
    elseif arg == "off" then
      enabled = false
      vim.notify("DapJumpStop: disabled")
    elseif arg == "status" then
      vim.notify("DapJumpStop: " .. (enabled and "enabled" or "disabled"))
    else
      enabled = not enabled
      vim.notify("DapJumpStop: " .. (enabled and "enabled" or "disabled"))
    end
  end, {
    nargs = "?",
    desc = "Toggle auto-jump on stopped threads",
    complete = function()
      return { "on", "off", "status" }
    end,
  })

  -- Cleanup on debugger dispose
  debugger:on_dispose(function()
    pcall(vim.api.nvim_del_user_command, "DapJumpStop")
  end)

  -- Return manual cleanup function
  return function()
    unsubscribe()
    pcall(vim.api.nvim_del_user_command, "DapJumpStop")
  end
end
