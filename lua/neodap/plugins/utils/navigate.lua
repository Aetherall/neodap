-- Navigation utilities for jumping to source locations

local M = {}

-- DAP buffer filetypes that should not be used for source jumps
local dap_filetypes = {
  ["dap-tree"] = true,
  ["dap-repl"] = true,
  ["dap-var"] = true,
  ["dap-input"] = true,
}

---Check if a window contains a DAP buffer
---@param win number Window ID
---@return boolean
local function is_dap_window(win)
  local bufnr = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[bufnr].filetype
  return dap_filetypes[ft] or false
end

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

---Find a window displaying a specific buffer
---@param bufnr number Buffer number
---@return number? win Window ID or nil
local function find_window_with_buffer(bufnr)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end
  return nil
end

---Default fallback: create a vertical split
---@return number win Window ID
local function default_create_window()
  vim.cmd("vsplit")
  return vim.api.nvim_get_current_win()
end

---Find or create a window suitable for opening source files
---Priority: 1) window already showing buffer, 2) non-DAP window, 3) create window
---@param path string File path to open
---@param create_window? fun(): number Fallback to create a window when none found
---@return number|{win: number, focus: boolean}|nil Window ID, table with focus flag, or nil to skip jump
local function default_pick_window(path, create_window)
  local current = vim.api.nvim_get_current_win()
  local in_dap_window = is_dap_window(current)

  -- First: check if file is already open in a window
  local bufnr = M.get_buffer_for_path(path)
  if bufnr then
    local win = find_window_with_buffer(bufnr)
    if win then
      -- If in DAP window, don't steal focus
      if in_dap_window then
        return { win = win, focus = false }
      end
      return win
    end
  end

  -- Second: try current window if it's not a DAP buffer
  if not in_dap_window then
    return current
  end

  -- We're in a DAP window, find or create a non-DAP window but don't focus it
  -- Third: find any non-DAP window
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= current and not is_dap_window(win) then
      return { win = win, focus = false }
    end
  end

  -- Last resort: create a window using the fallback
  local new_win = (create_window or default_create_window)()
  -- Return to original DAP window after creating
  vim.api.nvim_set_current_win(current)
  return { win = new_win, focus = false }
end

---@class NavigateOptions
---@field pick_window? fun(path: string, line: number, column: number): number|{win: number, focus: boolean}|nil Full override for window selection
---@field create_window? fun(): number Fallback when no suitable window exists (default: vsplit)

---Jump to a file location
---@param path string File path
---@param line number Line number
---@param column? number Column number (0-indexed)
---@param options? NavigateOptions|fun(path: string, line: number, column: number): number? Options or legacy pick_window function
function M.goto_location(path, line, column, options)
  column = column or 0

  -- Support legacy API: plain function as pick_window
  local pick_window, create_window
  if type(options) == "function" then
    pick_window = options
  elseif type(options) == "table" then
    pick_window = options.pick_window
    create_window = options.create_window
  end

  local result
  if pick_window then
    result = pick_window(path, line, column)
  else
    result = default_pick_window(path, create_window)
  end

  -- nil means skip the jump
  if not result then return end

  -- Handle both plain window ID and table with focus flag
  local win, should_focus
  if type(result) == "table" then
    win = result.win
    should_focus = result.focus ~= false -- default to true if not specified
  else
    win = result
    should_focus = true
  end

  local current_win = vim.api.nvim_get_current_win()

  -- Open file in target window
  vim.api.nvim_set_current_win(win)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  vim.api.nvim_win_set_cursor(win, { line, math.max(0, column) })
  vim.cmd("normal! zz")

  -- Restore focus if we shouldn't focus the target window
  if not should_focus then
    vim.api.nvim_set_current_win(current_win)
  end
end

---Jump to a frame's source location
---@param frame any Frame entity
---@param options? NavigateOptions|fun(path: string, line: number, column: number): number? Options or legacy pick_window function
---@return boolean success
function M.goto_frame(frame, options)
  local path, line, column = M.frame_location(frame)
  if not path then return false end
  M.goto_location(path, line, column, options)
  return true
end

return M
