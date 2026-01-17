-- Plugin: Stack navigation commands
--
-- Provides convenience aliases for navigating the call stack:
--   :DapUp   - Focus caller frame (up the stack)
--   :DapDown - Focus callee frame (down the stack)
--   :DapTop  - Focus top of stack (most recent frame)

---@param debugger neodap.entities.Debugger
---@return table api Plugin API
return function(debugger)
  local api = {}

  ---Focus a frame by URL, with error handling
  ---@param url string
  ---@param desc string Human-readable description for errors
  ---@return boolean success
  local function focus_frame(url, desc)
    local frame = debugger:query(url)
    if not frame then
      vim.notify("No " .. desc .. " frame", vim.log.levels.WARN)
      return false
    end
    debugger.ctx:focus(frame.uri:get())
    return true
  end

  ---Focus the caller frame (up the stack)
  ---@return boolean success
  function api.up()
    return focus_frame("@frame+1", "caller")
  end

  ---Focus the callee frame (down the stack)
  ---@return boolean success
  function api.down()
    return focus_frame("@frame-1", "callee")
  end

  ---Focus the top of stack (most recent frame)
  ---@return boolean success
  function api.top()
    return focus_frame("@thread/stack/frames[0]", "top")
  end

  vim.api.nvim_create_user_command("DapUp", function() api.up() end, {
    desc = "Focus caller frame (up the stack)",
  })

  vim.api.nvim_create_user_command("DapDown", function() api.down() end, {
    desc = "Focus callee frame (down the stack)",
  })

  vim.api.nvim_create_user_command("DapTop", function() api.top() end, {
    desc = "Focus top of stack",
  })

  function api.cleanup()
    pcall(vim.api.nvim_del_user_command, "DapUp")
    pcall(vim.api.nvim_del_user_command, "DapDown")
    pcall(vim.api.nvim_del_user_command, "DapTop")
  end

  return api
end
