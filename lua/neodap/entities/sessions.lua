-- Sessions entity methods for neograph-native
return function(Sessions)
  ---Get display label for this node
  ---@return string
  function Sessions:label()
    return "Sessions"
  end

  ---Get count of sessions (uses sessionCount rollup)
  ---@return number
  function Sessions:getSessionCount()
    return self.sessionCount:get() or 0
  end
end
