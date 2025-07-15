local Class = require("neodap.tools.class")

---@class neodap.ui.WindowConfig
---@field title string?
---@field size table?
---@field position table?
---@field border string?
---@field enter boolean?
---@field focusable boolean?
---@field keymaps table?
---@field win_options table?

---@class neodap.ui.Window
---@field new Constructor<neodap.ui.WindowConfig>
---@field popup any nui.nvim Popup instance
---@field config neodap.ui.WindowConfig
local Window = Class()

---Create a new Window instance
---@param config neodap.ui.WindowConfig
function Window:new(config)
  -- Try to require nui.nvim, provide graceful fallback
  local ok, Popup = pcall(require, "nui.popup")
  if not ok then
    error("nui.nvim is required for UI components. Please install MunifTanjim/nui.nvim")
  end

  self.config = config or {}
  
  -- Set up default configuration
  local popup_config = {
    enter = self.config.enter ~= false, -- Default to true
    focusable = self.config.focusable ~= false, -- Default to true
    border = {
      style = self.config.border or "rounded",
      text = self.config.title and { top = self.config.title } or nil,
    },
    position = self.config.position or "50%",
    size = self.config.size or { width = "80%", height = "60%" },
    win_options = vim.tbl_extend("force", {
      cursorline = true,
      wrap = false,
      number = false,
      relativenumber = false,
      signcolumn = "no",
    }, self.config.win_options or {})
  }
  
  self.popup = Popup(popup_config)
  
  -- Set up keymaps if provided
  if self.config.keymaps then
    self:setup_keymaps(self.config.keymaps)
  end
  
  return self
end

---Set up keymaps for the window
---@param keymaps table
function Window:setup_keymaps(keymaps)
  for key, action in pairs(keymaps) do
    self.popup:map("n", key, action, { noremap = true, silent = true })
  end
end

---Show the window
function Window:show()
  self.popup:mount()
end

---Hide the window
function Window:hide()
  if self.popup then
    self.popup:unmount()
  end
end

---Check if window is open
---@return boolean
function Window:is_open()
  return self.popup and self.popup.winid and vim.api.nvim_win_is_valid(self.popup.winid)
end

---Get the buffer number
---@return number?
function Window:get_bufnr()
  return self.popup and self.popup.bufnr
end

---Get the window id
---@return number?
function Window:get_winid()
  return self.popup and self.popup.winid
end

---Set buffer lines
---@param lines table
function Window:set_lines(lines)
  if not self.popup or not self.popup.bufnr then
    return
  end
  
  local bufnr = self.popup.bufnr
  local was_modifiable = vim.bo[bufnr].modifiable
  
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = was_modifiable
end

---Clear buffer content
function Window:clear()
  if not self.popup or not self.popup.bufnr then
    return
  end
  
  local bufnr = self.popup.bufnr
  local was_modifiable = vim.bo[bufnr].modifiable
  
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
  vim.bo[bufnr].modifiable = was_modifiable
end

---Add highlight to buffer
---@param line number 0-indexed line number
---@param col_start number
---@param col_end number
---@param hl_group string
---@param namespace number?
function Window:add_highlight(line, col_start, col_end, hl_group, namespace)
  if not self.popup or not self.popup.bufnr then
    return
  end
  
  vim.api.nvim_buf_add_highlight(
    self.popup.bufnr,
    namespace or -1,
    hl_group,
    line,
    col_start,
    col_end
  )
end

---Clear highlights in namespace
---@param namespace number
function Window:clear_highlights(namespace)
  if not self.popup or not self.popup.bufnr then
    return
  end
  
  vim.api.nvim_buf_clear_namespace(self.popup.bufnr, namespace, 0, -1)
end

---Set cursor position
---@param line number 1-indexed line number
---@param col number 0-indexed column number
function Window:set_cursor(line, col)
  if not self:is_open() then
    return
  end
  
  vim.api.nvim_win_set_cursor(self.popup.winid, { line, col or 0 })
end

---Get cursor position
---@return number, number line (1-indexed), col (0-indexed)
function Window:get_cursor()
  if not self:is_open() then
    return 1, 0
  end
  
  local pos = vim.api.nvim_win_get_cursor(self.popup.winid)
  return pos[1], pos[2]
end

return Window