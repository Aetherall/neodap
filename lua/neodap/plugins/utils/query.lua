-- Query utilities for entity lookups

local M = {}

---Query entities by URL or fall back to a default
---@param debugger any Debugger instance
---@param url? string Optional URL to query
---@param default_fn? fun(): any? Function returning default entity (called when no url)
---@return any[] entities Array of entities (may be empty)
function M.query_or_default(debugger, url, default_fn)
  if url and url ~= "" then
    return debugger:queryAll(url)
  end
  if default_fn then
    local entity = default_fn()
    return entity and { entity } or {}
  end
  return {}
end

---Query entities by URL or fall back to current quickfix item
---@param debugger any Debugger instance
---@param url? string Optional URL to query
---@return any[] entities Array of entities (may be empty)
function M.query_or_quickfix(debugger, url)
  if url and url ~= "" then
    return debugger:queryAll(url)
  end

  local items = vim.fn.getqflist()
  if #items == 0 then return {} end

  -- If cursor is in the quickfix window, use the visual cursor line (1-indexed)
  -- so that :DapRemove/Enable/Disable operate on the item under the cursor
  -- rather than the last <CR>-confirmed position.
  local idx
  local qf_winid = vim.fn.getqflist({ winid = 0 }).winid
  if qf_winid ~= 0 and vim.api.nvim_get_current_win() == qf_winid then
    idx = vim.fn.line(".")
  else
    local qf = vim.fn.getqflist({ idx = 0 })
    idx = qf.idx
  end

  if not idx or idx == 0 or idx > #items then return {} end
  local item = items[idx]

  if item and item.user_data and item.user_data.uri then
    local entity = debugger:query(item.user_data.uri)
    return entity and { entity } or {}
  end

  return {}
end

return M
