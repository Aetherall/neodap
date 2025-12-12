-- Shared utility for opening URIs/paths with a caller-controlled position

local M = {}

---@alias neodap.OpenPosition "replace"|"split"|"hsplit"|"vsplit"|"tab"|"float"

local SPLIT_CMDS = {
  replace = "edit",
  split   = "split",
  hsplit  = "split",
  vsplit  = "vsplit",
  tab     = "tabedit",
}

---Open a URI or file path in a floating window centered on the editor
---@param uri string
local function open_float(uri)
  local width  = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines   * 0.8)
  local row    = math.floor((vim.o.lines   - height) / 2)
  local col    = math.floor((vim.o.columns - width)  / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = "rounded",
  })

  -- Open the URI inside the float
  vim.api.nvim_win_call(win, function()
    vim.cmd("edit " .. vim.fn.fnameescape(uri))
  end)
end

---Open a URI or path with the given position
---@param uri string The URI or file path to open
---@param opts? { split?: neodap.OpenPosition }
function M.open(uri, opts)
  opts = opts or {}
  local pos = opts.split

  if pos == "float" then
    open_float(uri)
    return
  end

  local cmd = SPLIT_CMDS[pos] or "edit"
  vim.cmd(cmd .. " " .. vim.fn.fnameescape(uri))
end

return M
