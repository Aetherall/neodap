local M = {}
M.__index = M

function M.new()
  local self = setmetatable({
    bufnr = nil,
    winid = nil,
    config = {
      relative = "editor",
      width = 60,
      height = 20,
      col = vim.o.columns - 65,
      row = 5,
      style = "minimal",
      border = "rounded",
      title = " Call Stack ",
      title_pos = "center",
    }
  }, M)
  
  return self
end

function M:create_buffer()
  if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
    return self.bufnr
  end
  
  self.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(self.bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(self.bufnr, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(self.bufnr, "filetype", "neodap-callstack")
  vim.api.nvim_buf_set_option(self.bufnr, "modifiable", false)
  
  return self.bufnr
end

function M:open()
  if self:is_open() then
    return
  end
  
  self:create_buffer()
  
  self.winid = vim.api.nvim_open_win(self.bufnr, false, self.config)
  
  vim.api.nvim_win_set_option(self.winid, "cursorline", true)
  vim.api.nvim_win_set_option(self.winid, "wrap", false)
  vim.api.nvim_win_set_option(self.winid, "number", false)
  vim.api.nvim_win_set_option(self.winid, "relativenumber", false)
  vim.api.nvim_win_set_option(self.winid, "signcolumn", "no")
  
  self:setup_keymaps()
  self:setup_highlights()
end

function M:close()
  if self.winid and vim.api.nvim_win_is_valid(self.winid) then
    vim.api.nvim_win_close(self.winid, true)
  end
  self.winid = nil
end

function M:is_open()
  return self.winid and vim.api.nvim_win_is_valid(self.winid)
end

function M:clear()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end
  
  vim.api.nvim_buf_set_option(self.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, {})
  vim.api.nvim_buf_set_option(self.bufnr, "modifiable", false)
end

function M:set_lines(lines)
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end
  
  vim.api.nvim_buf_set_option(self.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(self.bufnr, "modifiable", false)
end

function M:add_highlight(line, col_start, col_end, hl_group)
  if not self.bufnr then
    return
  end
  
  vim.api.nvim_buf_add_highlight(
    self.bufnr,
    -1,
    hl_group,
    line,
    col_start,
    col_end
  )
end

function M:clear_namespace(ns_id)
  if not self.bufnr then
    return
  end
  
  vim.api.nvim_buf_clear_namespace(self.bufnr, ns_id, 0, -1)
end

function M:setup_keymaps()
  local opts = { buffer = self.bufnr, nowait = true }
  
  vim.keymap.set("n", "q", function() self:close() end, opts)
  vim.keymap.set("n", "<Esc>", function() self:close() end, opts)
  vim.keymap.set("n", "<CR>", function() self:on_select() end, opts)
  vim.keymap.set("n", "o", function() self:on_select() end, opts)
end

function M:on_select()
  local cursor = vim.api.nvim_win_get_cursor(self.winid)
  local line = cursor[1]
  
  if self.on_select_callback then
    self.on_select_callback(line)
  end
end

function M:set_on_select(callback)
  self.on_select_callback = callback
end

function M:setup_highlights()
  vim.cmd([[
    highlight default NeodapCallStackCurrent guifg=#ff9e64 gui=bold
    highlight default NeodapCallStackFrame guifg=#7aa2f7
    highlight default NeodapCallStackSource guifg=#565f89
    highlight default NeodapCallStackLineNumber guifg=#bb9af7
    highlight default link NeodapCallStackSelected CursorLine
  ]])
end

function M:get_winid()
  return self.winid
end

function M:get_bufnr()
  return self.bufnr
end

return M