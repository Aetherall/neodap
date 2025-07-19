local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local Location = require("neodap.api.Location")
local NvimAsync = require("neodap.tools.async")

---@class neodap.plugin.ToggleBreakpointProps
---@field api Api
---@field breakpointApi BreakpointApiPlugin
---@field logger Logger

---@class neodap.plugin.ToggleBreakpoint: neodap.plugin.ToggleBreakpointProps
---@field new Constructor<neodap.plugin.ToggleBreakpointProps>
local ToggleBreakpoint = Class()

ToggleBreakpoint.name = "ToggleBreakpoint"
ToggleBreakpoint.description = "Plugin to toggle breakpoints in Neodap"

-- Smart Adjustment System
function ToggleBreakpoint.plugin(api)
  local logger = Logger.get("Plugin:ToggleBreakpoint")

  return ToggleBreakpoint:new({
    api = api,
    logger = logger,
    breakpointApi = api:getPluginInstance(BreakpointApi),
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

return ToggleBreakpoint
