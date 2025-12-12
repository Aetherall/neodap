--- Icon set resolver for neodap tree UI.
---
--- An icon set is a partial config table containing `icons` and/or
--- `var_type_icons` keys. It gets merged into the config alongside themes:
---   defaults → theme → icon_set → user config
---
--- Usage:
---   neodap.use("neodap.plugins.tree_buffer", { icon_set = "emoji" })
---   neodap.use("neodap.plugins.tree_buffer", { icon_set = require("my-icons") })
---
--- Built-in icon sets:
---   "nerd"  - Nerd Font icons (default, requires a patched font)
---   "emoji" - Emoji icons (no special font required)

local M = {}

--- Resolve an icon set spec to a config table.
---@param spec string|table|false|nil Icon set specification
---@return table icon_set Partial config table (empty if no override)
function M.resolve(spec)
  if spec == nil or spec == false then
    return {}
  end
  if type(spec) == "table" then
    return spec
  end
  if type(spec) == "string" then
    -- "nerd" is the default, no override needed
    if spec == "nerd" then return {} end
    local ok, icons = pcall(require, "neodap.icons." .. spec)
    if ok and type(icons) == "table" then
      return icons
    end
    -- Try as a full module path
    ok, icons = pcall(require, spec)
    if ok and type(icons) == "table" then
      return icons
    end
    vim.notify(
      string.format("[neodap] Icon set %q not found. Using defaults.", spec),
      vim.log.levels.WARN
    )
    return {}
  end
  return {}
end

return M
