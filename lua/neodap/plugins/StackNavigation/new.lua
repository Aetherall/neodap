local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local Location = require("neodap.api.Location")
local NvimAsync = require("neodap.tools.async")

---@class neodap.plugin.StackNavigationProps
---@field api Api
---@field logger Logger

---@class neodap.plugin.StackNavigation: neodap.plugin.StackNavigationProps
---@field new Constructor<neodap.plugin.StackNavigationProps>
local StackNavigation = Class()

StackNavigation.name = "StackNavigation"
StackNavigation.description = "Navigate through call stacks with cursor awareness"

function StackNavigation.plugin(api)
  local logger = Logger.get()

  return StackNavigation:new({
    api = api,
    logger = logger,
  })
end

---@param location api.Location?
---@return api.Frame?
function StackNavigation:getClosestFrame(location)
  local target = location or Location.fromCursor()

  local closest = nil
  local closest_distance = math.huge
  
  -- Find frame closest to cursor across all sessions and threads
  for session in self.api:eachSession() do
    for thread in session:eachThread({ filter = 'stopped' }) do
      local stack = thread:stack()
      if stack then
        for frame in stack:eachFrame({ sourceId = target.sourceId }) do
          local location = frame:location()
          if location then
            local distance = location:distance(target)
            if distance < closest_distance then
              closest_distance = distance
              closest = frame
            end
          end
        end
      end
    end
  end

  self.logger:debug("Closest frame is ", closest and closest:location().key, " at distance ", closest_distance)
  return closest
end

---Navigate up the call stack (towards caller)
function StackNavigation:up()
  NvimAsync.run(function()
    local closest = self:getClosestFrame()
    local parent = closest and closest:up()
    if parent then parent:jump() end 
  end)
end

---Navigate down the call stack (towards callee)
function StackNavigation:down()
  NvimAsync.run(function()
    local closest = self:getClosestFrame()
    local child = closest and closest:down()
    if child then child:jump() end 
  end)
end

---Navigate to top frame (most recent call)
function StackNavigation:top()
  NvimAsync.run(function()
    local closest = self:getClosestFrame()
    local top = closest and closest.stack:top()
    if top then top:jump() end
  end)
end

return StackNavigation