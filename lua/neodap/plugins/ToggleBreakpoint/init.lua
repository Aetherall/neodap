local BasePlugin = require("neodap.plugins.BasePlugin")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local Location = require("neodap.api.Location")

---@class neodap.plugin.ToggleBreakpoint: BasePlugin
---@field breakpointApi BreakpointApiPlugin
local ToggleBreakpoint = BasePlugin:extend()

ToggleBreakpoint.name = "ToggleBreakpoint"
ToggleBreakpoint.description = "Plugin to toggle breakpoints in Neodap"

-- Smart Adjustment System
function ToggleBreakpoint.plugin(api)
  return BasePlugin.createPlugin(api, ToggleBreakpoint, {
    breakpointApi = api:getPluginInstance(BreakpointApi),
  })
end

function ToggleBreakpoint:setupCommands()
  self:registerCommands({
    {"NeodapToggleBreakpoint", function(args) self:Toggle() end, {desc = "Toggle a breakpoint at the current cursor position"}}
  })
end

---Find the best location for a breakpoint across all sessions
---@param location api.Location
---@return api.Location
function ToggleBreakpoint:adjust(location)
  -- Default to column 0 if not specified
  local loc = location:adjusted({ column = 0 })

  -- Check all sessions for the best breakpoint location
  for session in self.api:eachSession() do
    local source = session:getSource(location)

    if source then
      for candidate in source:breakpointLocations({ line = location.line }) do
        if candidate:distance(location) < loc:distance(location) then
          loc = candidate
        end
      end
    end
  end

  return loc
end

---@param location api.Location?
function ToggleBreakpoint:toggle(location)
  local target = location or Location.fromCursor()

  local adjusted = self:adjust(target)

  local existingBreakpoint = self.breakpointApi.getBreakpoints():atLocation(adjusted):first()
  if existingBreakpoint then
    self.breakpointApi.removeBreakpoint(existingBreakpoint)
    self.logger:info("Removed existing breakpoint at", adjusted.key)
    return
  end

  self.breakpointApi.setBreakpoint(adjusted)
  self.logger:info("Set breakpoint at", adjusted.key)
end

-- Auto-wrapped version for vim context boundaries
function ToggleBreakpoint:Toggle(location)
  return self:toggle(location)
end

function ToggleBreakpoint:destroy()
  -- Clean up any resources if needed
  self.logger:info("Destroying ToggleBreakpoint plugin")
  vim.api.nvim_del_user_command("NeodapToggleBreakpoint")
end

return ToggleBreakpoint
