-- Scope entity methods for neograph-native
return function(Scope)
  ---Get the session this scope belongs to (Scope → Frame → Stack → Thread → Session)
  ---@return neodap.entities.Session?
  function Scope:session()
    local frame = self.frame:get()
    return frame and frame:session()
  end

  ---Check if scope's session is terminated
  ---Returns true if terminated OR if unable to determine (safe default)
  ---@return boolean
  function Scope:isSessionTerminated()
    local frame = self.frame:get()
    if not frame then return true end  -- Can't reach session, assume terminated
    return frame:isSessionTerminated()
  end
end
