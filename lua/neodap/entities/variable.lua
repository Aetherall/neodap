-- Variable entity methods for neograph-native
return function(Variable)
  ---Check if variable has children (expandable)
  ---@return boolean
  function Variable:hasChildren()
    return (self.variablesReference:get() or 0) > 0
  end

  ---Get display string for variable
  ---@return string
  function Variable:display()
    local name = self.name:get() or ""
    local value = self.value:get() or ""
    local vtype = self.varType:get()
    if vtype and vtype ~= "" then
      return string.format("%s: %s = %s", name, vtype, value)
    end
    return string.format("%s = %s", name, value)
  end

  ---Check if key matches this variable
  ---@param key string
  ---@return boolean
  function Variable:matchKey(key)
    return self.name:get() == key
  end

  ---Check if variable's session is terminated
  ---Returns true if terminated OR if unable to determine (safe default)
  ---@return boolean
  function Variable:isSessionTerminated()
    local scope = self.scope:get()
    if not scope then return true end  -- Can't reach session, assume terminated
    return scope:isSessionTerminated()
  end
end
