-- ExceptionFilter entity methods for neograph-native
-- ExceptionFilter is now global (debugger-scoped), with per-session overrides via ExceptionFilterBinding
return function(ExceptionFilter)
  ---Check if filter is enabled (global default)
  ---@return boolean
  function ExceptionFilter:isEnabled()
    return self.defaultEnabled:get() or false
  end

  ---Toggle global default enabled state
  function ExceptionFilter:toggle()
    self:update({ defaultEnabled = not self:isEnabled() })
  end

  ---Check if filter supports conditions
  ---@return boolean
  function ExceptionFilter:canHaveCondition()
    return self.supportsCondition:get() == true
  end

  ---Check if key matches this filter
  ---@param key string
  ---@return boolean
  function ExceptionFilter:matchKey(key)
    return self.filterId:get() == key
  end
end
