-- Navigation utilities for jumping to source locations

local M = {}

---Get buffer for a file path
---@param path string
---@return number? bufnr
function M.get_buffer_for_path(path)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local buf_path = vim.api.nvim_buf_get_name(bufnr)
      if buf_path == path then
        return bufnr
      end
    end
  end
  return nil
end

---Get buffer URI and location from a frame (supports virtual sources)
---@param frame any Frame entity
---@return string? uri, number line, number column
function M.frame_location(frame)
  if not frame then return nil, 1, 0 end
  local loc = frame:location()
  if not loc then return nil, 1, 0 end
  return loc.path, loc.line or 1, loc.column or 0
end

---Jump to a file location in current window
---@param path string File path
---@param line number Line number
---@param column? number Column number (0-indexed)
function M.goto_location(path, line, column)
  column = column or 0
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  vim.api.nvim_win_set_cursor(0, { line, math.max(0, column) })
  vim.cmd("normal! zz")
end

---Jump to a frame's source location in current window
---@param frame any Frame entity
---@return boolean success
function M.goto_frame(frame)
  local path, line, column = M.frame_location(frame)
  if not path then return false end
  M.goto_location(path, line, column)
  return true
end

return M
