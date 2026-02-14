-- Session query methods for Debugger (neograph-native)
-- Note: firstSession is now a rollup, accessed via debugger.firstSession:get()

---Check if any active session supports a capability
---@param capability string Method name to check (e.g., "supportsBreakpointLocations")
---@return boolean
local function any_session_supports(self, capability)
  for session in self.sessions:iter() do
    local method = session[capability]
    if session.state:get() ~= "terminated" and method and method(session) then
      return true
    end
  end
  return false
end

---Check if any active session supports breakpoint locations
---@return boolean
local function supports_breakpoint_locations(self)
  return any_session_supports(self, "supportsBreakpointLocations")
end

---Iterate over active sessions that support a capability
---@param capability string Method name to check
---@return fun(): neodap.entities.Session? iterator
local function iter_sessions_supporting(self, capability)
  local session_iter = self.sessions:iter()
  return function()
    for session in session_iter do
      local method = session[capability]
      if session.state:get() ~= "terminated" and method and method(session) then
        return session
      end
    end
    return nil
  end
end

return function(Debugger)
  Debugger.supportsBreakpointLocations = supports_breakpoint_locations
  Debugger.iterSessionsSupporting = iter_sessions_supporting
end
