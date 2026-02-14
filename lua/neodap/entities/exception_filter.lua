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

  ---Sync all sessions that have bindings to this filter
  ---Iterates through all ExceptionFilterBindings and calls syncExceptionFilters
  ---on each bound session.
  function ExceptionFilter:syncAllSessions()
    for binding in self.bindings:iter() do
      local session = binding.session and binding.session:get()
      if session then
        session:syncExceptionFilters()
      end
    end
  end
end
