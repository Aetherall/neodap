-- Plugin: DapContinue command for resuming debug sessions

local neostate = require("neostate")

---@param debugger Debugger
---@return function cleanup
return function(debugger)
  vim.api.nvim_create_user_command("DapContinue", function()
    -- Get context session
    local session = debugger:resolve_contextual_one("@session", "session"):get()
    if not session then
      vim.notify("No active debug session", vim.log.levels.WARN)
      return
    end

    -- Continue execution
    neostate.void(function()
      session:continue()
    end)()
  end, {
    nargs = 0,
    desc = "Continue debug session execution",
  })

  -- Cleanup on debugger dispose
  debugger:on_dispose(function()
    pcall(vim.api.nvim_del_user_command, "DapContinue")
  end)

  -- Return manual cleanup function
  return function()
    pcall(vim.api.nvim_del_user_command, "DapContinue")
  end
end
