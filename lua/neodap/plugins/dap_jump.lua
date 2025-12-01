---@class DapJumpConfig
---@field select_jump_window? fun(): number? Function to select a window for jumping (e.g., nvim-window-picker)
---@field strategy? "always_ask"|"ask_on_winfixbuf"|"silent"|"error" Window selection strategy (default: "error")

---@param debugger Debugger
---@param config? DapJumpConfig
---@return function cleanup
return function(debugger, config)
  config = config or {}
  local strategy = config.strategy or "error"

  ---Select a window for jumping, returns nil if cancelled or not possible
  ---@return number? win_id
  local function select_window()
    if not config.select_jump_window then
      return nil
    end

    -- Keep asking until user picks a non-winfixbuf window or cancels
    while true do
      local win = config.select_jump_window()
      if not win then
        return nil -- User cancelled
      end
      if not vim.wo[win].winfixbuf then
        return win
      end
      -- Selected window also has winfixbuf, ask again
    end
  end

  vim.api.nvim_create_user_command("DapJump", function(opts)
    local frame = debugger:resolve_contextual_one(opts.args, "frame"):get()
    if not frame or not frame.source then
      vim.notify("DapJump: Could not resolve " .. opts.args, vim.log.levels.ERROR)
      return
    end

    local win = vim.api.nvim_get_current_win()
    local current_is_fixed = vim.wo[win].winfixbuf

    -- Determine target window based on strategy
    if strategy == "always_ask" then
      local target = select_window()
      if not target then
        return -- User cancelled or no select_jump_window configured
      end
      vim.api.nvim_set_current_win(target)
    elseif current_is_fixed then
      if strategy == "ask_on_winfixbuf" then
        local target = select_window()
        if not target then
          return -- User cancelled or no select_jump_window configured
        end
        vim.api.nvim_set_current_win(target)
      elseif strategy == "silent" then
        return
      else -- "error"
        vim.notify("DapJump: Current window has winfixbuf set", vim.log.levels.ERROR)
        return
      end
    end

    -- Use path for local files, location_uri() for virtual sources
    local edit_target = frame.source.path or frame.source:location_uri()
    vim.cmd.edit(edit_target)
    vim.api.nvim_win_set_cursor(0, { frame.line, (frame.column or 1) - 1 })
  end, { nargs = 1, desc = "Jump to debug frame by URI" })

  return function()
    pcall(vim.api.nvim_del_user_command, "DapJump")
  end
end
