-- Scope entity methods for neograph-native
return function(Scope)
  ---Check if key matches this scope
  ---@param key string
  ---@return boolean
  function Scope:matchKey(key)
    return self.name:get() == key
  end

  ---Check if this is an expensive scope
  ---@return boolean
  function Scope:isExpensive()
    return self.expensive:get() == true
  end

  ---Check if scope has variables to fetch
  ---@return boolean
  function Scope:hasVariables()
    return (self.variablesReference:get() or 0) > 0
  end

  ---Get display label for this scope
  ---@return string
  function Scope:label()
    return self.name:get() or "Scope"
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
