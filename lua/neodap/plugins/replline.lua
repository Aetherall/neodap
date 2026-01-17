-- Plugin: Floating 1-line REPL input at cursor position
-- Provides quick inline expression evaluation
--
-- Usage:
--   :DapReplLine          - Open floating REPL at cursor
--   Lua: require("neodap").use(replline).open()

---@class ReplLineConfig
---@field border? string Border style: "none", "single", "rounded", "double", "solid", "shadow"
---@field width? number Override width (nil = current window width)

local default_config = {
  border = "none",
  width = nil,
}

---@param debugger neodap.entities.Debugger
---@param config? ReplLineConfig
return function(debugger, config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local group = vim.api.nvim_create_augroup("neodap-replline", { clear = true })
  local current_win = nil -- Track current floating window

  ---Close the current replline window if open
  local function close()
    if current_win and vim.api.nvim_win_is_valid(current_win) then
      vim.api.nvim_win_close(current_win, true)
    end
    current_win = nil
  end

  ---Open the floating REPL line at cursor position
  local function open()
    -- Close existing replline first
    close()

    local cur_win = vim.api.nvim_get_current_win()
    local cursor = vim.api.nvim_win_get_cursor(cur_win)
    local win_width = vim.api.nvim_win_get_width(cur_win)
    local win_height = vim.api.nvim_win_get_height(cur_win)

    -- Calculate dimensions
    local width = config.width or win_width
    local initial_height = 1
    local max_height = math.floor(win_height / 2) -- Don't grow past half the window

    -- Position at cursor line (0-indexed)
    -- Adjust if at bottom of window to keep visible
    local row = cursor[1] - 1
    if row >= win_height - 2 then
      row = win_height - 3 -- Keep room for border
    end
    local col = 0

    -- Create scratch buffer first, then load dap-eval URI via :edit
    -- Note: bufadd/bufload don't trigger BufReadCmd, so we use :edit
    local scratch = vim.api.nvim_create_buf(false, true)

    -- Open floating window with scratch buffer
    local win = vim.api.nvim_open_win(scratch, true, {
      relative = "win",
      win = cur_win,
      row = row,
      col = col,
      width = width,
      height = initial_height,
      style = "minimal",
      border = config.border,
      zindex = 50,
    })
    current_win = win

    -- Window options
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = false

    -- Load dap://input buffer via :edit (triggers BufReadCmd for proper setup)
    -- Note: Don't use closeonsubmit so the result stays visible
    local uri = "dap://input/@frame"
    vim.cmd.edit(uri)
    local bufnr = vim.api.nvim_get_current_buf()

    -- Delete the scratch buffer only if edit created a new buffer
    if scratch ~= bufnr and vim.api.nvim_buf_is_valid(scratch) then
      vim.api.nvim_buf_delete(scratch, { force = true })
    end

    -- Only set up keymaps and autocmds if we have a valid buffer
    if not vim.api.nvim_buf_is_valid(bufnr) then
      close()
      return
    end

    -- Resize window to fit content
    local function resize_to_content()
      if not current_win or not vim.api.nvim_win_is_valid(current_win) then
        return
      end
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      local line_count = vim.api.nvim_buf_line_count(bufnr)
      local new_height = math.max(1, math.min(line_count, max_height))
      local current_config = vim.api.nvim_win_get_config(current_win)

      if current_config.height ~= new_height then
        vim.api.nvim_win_set_config(current_win, {
          relative = current_config.relative,
          win = current_config.win,
          row = current_config.row,
          col = current_config.col,
          width = current_config.width,
          height = new_height,
        })
      end
    end

    -- Resize on text changes
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer = bufnr,
      group = group,
      callback = resize_to_content,
    })

    -- Close on Escape (only in normal mode - allows normal editing with Escape)
    vim.keymap.set("n", "<Esc>", function()
      close()
    end, { buffer = bufnr, nowait = true })

    -- Close on focus lost
    vim.api.nvim_create_autocmd("WinLeave", {
      buffer = bufnr,
      group = group,
      once = true,
      callback = function()
        -- Defer to allow submit to process first
        vim.defer_fn(function()
          close()
        end, 10)
      end,
    })
  end

  -- Create command
  vim.api.nvim_create_user_command("DapReplLine", function()
    open()
  end, { desc = "Open floating REPL input at cursor" })

  -- Return public API
  return {
    open = open,
    close = close,
  }
end
