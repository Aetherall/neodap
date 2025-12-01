-- SDK Layer - For plugin developers
-- Tracks all debugger instances reactively

local neostate = require('neostate')

---@class SDK : Class
local SDK = neostate.Class("SDK")

function SDK:init()
    -- Reactive list of all debugger instances
    self.debuggers = self:list("debuggers")
end

---Create a new debugger instance
---@return Debugger
function SDK:create_debugger()
    local Debugger = require("neodap.sdk.debugger.init")
    local debugger = Debugger:new()

    -- Add to reactive list (triggers subscribers)
    self.debuggers:add(debugger)

    return debugger
end

---Subscribe to all debuggers (existing + future)
---@param callback fun(debugger: Debugger)
function SDK:onDebugger(callback)
    self.debuggers:subscribe(callback)
end

-- Create singleton SDK instance
local _sdk = SDK:new()

return _sdk
