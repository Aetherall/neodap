-- ExceptionFilter entity methods for neograph-native
return function(ExceptionFilter)
  ---Check if filter is enabled
  ---@return boolean
  function ExceptionFilter:isEnabled()
    local enabled = self.enabled:get()
    if enabled == nil then
      return self.defaultEnabled:get() or false
    end
    return enabled
  end

  ---Toggle enabled state
  function ExceptionFilter:toggle()
    self:update({ enabled = not self:isEnabled() })
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
