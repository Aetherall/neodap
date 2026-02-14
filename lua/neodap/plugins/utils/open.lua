-- Shared utility for split dispatch when opening URIs/paths
local M = {}

local split_cmds = {
  horizontal = "split",
  vertical = "vsplit",
  tab = "tabedit",
}

---Open a URI or path with the appropriate split command
---@param uri string The URI or file path to open
---@param opts? { split?: "horizontal"|"vertical"|"tab" }
function M.open(uri, opts)
  opts = opts or {}
  local cmd = split_cmds[opts.split] or "edit"
  vim.cmd(cmd .. " " .. vim.fn.fnameescape(uri))
end

return M
