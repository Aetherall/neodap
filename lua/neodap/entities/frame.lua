-- Frame entity methods for neograph-native
local Location = require("neodap.location")
local normalize = require("neodap.utils").normalize

return function(Frame)
  ---Get location as Location object
  ---@return neodap.Location?
  function Frame:location()
    return Location.fromEntity(self)
  end

  ---Get the thread this frame belongs to
  ---@return neodap.entities.Thread?
  function Frame:thread()
    local stack = self.stack:get()
    return stack and stack.thread:get()
  end

  ---Get the session this frame belongs to (Frame → Stack → Thread → Session)
  ---@return neodap.entities.Session?
  function Frame:session()
    local thread = self:thread()
    return thread and thread.session:get()
  end

  ---Should frame be visually de-emphasized?
  ---@param hints? table<string, boolean> Presentation hints to treat as subtle (default: {subtle=true})
  ---@return boolean
  function Frame:isSubtle(hints)
    hints = hints or { subtle = true }
    local hint = normalize(self.presentationHint:get())
    if not hint then return false end
    return hints[hint] == true
  end

  ---Should frame be hidden from navigation?
  ---@param hints? table<string, boolean> Presentation hints to treat as skippable (default: {label=true})
  ---@return boolean
  function Frame:isSkippable(hints)
    hints = hints or { label = true }
    local hint = normalize(self.presentationHint:get())
    if not hint then return false end
    return hints[hint] == true
  end

  ---Check if frame's session is terminated
  ---Returns true if terminated OR if unable to determine (safe default)
  ---@return boolean
  function Frame:isSessionTerminated()
    local thread = self:thread()
    if not thread then return true end  -- Can't reach session, assume terminated
    return thread:isSessionTerminated()
  end
end
