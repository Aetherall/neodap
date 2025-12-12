--- Theme resolver for neodap tree UI.
---
--- A theme is a partial config table (highlights, var_type_icons, icons, etc.)
--- that gets merged between defaults and user config:
---   defaults (link-based) → theme → user config
---
--- Usage:
---   neodap.use("neodap.plugins.tree_buffer", { theme = "catppuccin" })
---   neodap.use("neodap.plugins.tree_buffer", { theme = require("my-theme") })
---   neodap.use("neodap.plugins.tree_buffer", { theme = false })  -- no theme
---
--- Creating a theme:
---   return {
---     highlights = {
---       DapTreeIconSession = { fg = "#89b4fa" },
---       DapVarIconString = { fg = "#a6e3a1" },
---       -- ...
---     },
---     -- Optional: override icons, var_type_icons, icon_highlights, etc.
---   }

local M = {}

--- Resolve a theme spec to a config table.
---@param spec string|table|false|nil Theme specification
---@return table theme Partial config table (empty table if no theme)
function M.resolve(spec)
  if spec == nil or spec == false then
    return {}
  end
  if type(spec) == "table" then
    return spec
  end
  if type(spec) == "string" then
    local ok, theme = pcall(require, "neodap.themes." .. spec)
    if ok and type(theme) == "table" then
      return theme
    end
    -- Try as a full module path (for external themes like "neodap-gruvbox")
    ok, theme = pcall(require, spec)
    if ok and type(theme) == "table" then
      return theme
    end
    vim.notify(
      string.format("[neodap] Theme %q not found. Using defaults.", spec),
      vim.log.levels.WARN
    )
    return {}
  end
  return {}
end

return M
