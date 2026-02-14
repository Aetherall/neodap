-- Output entity methods for neograph-native
local Location = require("neodap.location")

return function(Output)
  ---Get location as Location object (supports virtual sources via bufferUri)
  ---@return neodap.Location?
  function Output:location()
    return Location.fromEntity(self)
  end

  ---Check if output's session is terminated
  ---Returns true if terminated OR if unable to determine (safe default)
  ---@return boolean
  function Output:isSessionTerminated()
    local session = self.session:get()
    if not session then return true end
    return session:isTerminated()
  end
end
