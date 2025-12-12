-- Shared treesitter expression extraction utilities
--
-- Used by hover.lua and expression_edit.lua to get the expression
-- at a given buffer position using treesitter with fallback scanning.

local M = {}

-- Base expression node types recognized by treesitter
local base_expr_types = {
  -- JavaScript/TypeScript
  identifier = true,
  member_expression = true,
  subscript_expression = true,
  -- Lua
  dot_index_expression = true,
  bracket_index_expression = true,
  -- Python
  attribute = true,
  -- General
  property_identifier = true,
  field_expression = true,
}

---Get expression at buffer position using treesitter with fallback
---@param bufnr number Buffer number
---@param row number 0-indexed row
---@param col number 0-indexed column
---@param opts? { include_calls?: boolean, dotted_fallback?: boolean }
---@return string?
function M.get_expression_at_position(bufnr, row, col, opts)
  opts = opts or {}

  -- Try treesitter first
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { row, col } })
  if ok and node then
    local expr_types = vim.tbl_extend("force", base_expr_types, {})
    if opts.include_calls then
      expr_types.call_expression = true
    end

    local current = node
    local best = nil

    -- Find the largest expression node containing cursor
    while current do
      local node_type = current:type()
      if expr_types[node_type] then
        best = current
      end
      -- Stop if we hit a statement or declaration
      if node_type:match("statement") or node_type:match("declaration") then
        break
      end
      current = current:parent()
    end

    if best then
      local text = vim.treesitter.get_node_text(best, bufnr)
      if text and text ~= "" then
        return text
      end
    end
  end

  -- Fallback: scan text at position
  local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)
  if not lines[1] then return nil end

  local line = lines[1]
  local start_col = col
  local end_col = col

  if opts.dotted_fallback then
    -- Scan for dotted/bracket expressions (e.g., foo.bar[0])
    local function is_expr_char(c)
      return c:match("[%w_%.%[%]'\"]")
    end

    while start_col > 0 and is_expr_char(line:sub(start_col, start_col)) do
      start_col = start_col - 1
    end
    start_col = start_col + 1

    while end_col <= #line and is_expr_char(line:sub(end_col + 1, end_col + 1)) do
      end_col = end_col + 1
    end

    local expr = line:sub(start_col, end_col)
    if expr and expr ~= "" then
      return expr
    end

    -- Last fallback: word under cursor
    return vim.fn.expand("<cword>")
  else
    -- Simple word scanning (identifiers only)
    local function is_word_char(c)
      return c:match("[%w_]")
    end

    while start_col > 0 and is_word_char(line:sub(start_col, start_col)) do
      start_col = start_col - 1
    end
    start_col = start_col + 1

    while end_col <= #line and is_word_char(line:sub(end_col + 1, end_col + 1)) do
      end_col = end_col + 1
    end

    local word = line:sub(start_col, end_col)
    return word ~= "" and word or nil
  end
end

---Get expression at current cursor position
---@param opts? { include_calls?: boolean, dotted_fallback?: boolean }
---@return string?
function M.get_expression_at_cursor(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  return M.get_expression_at_position(bufnr, row, col, opts)
end

---Get visual selection text
---@return string?
function M.get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_row, start_col = start_pos[2], start_pos[3]
  local end_row, end_col = end_pos[2], end_pos[3]

  if start_row ~= end_row then
    local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
    return table.concat(lines, "\n")
  end

  local line = vim.api.nvim_buf_get_lines(0, start_row - 1, start_row, false)[1]
  if line then
    return line:sub(start_col, end_col)
  end
  return nil
end

return M
