-- ExceptionFiltersGroup entity methods for neograph-native
return function(ExceptionFiltersGroup)
  ---Get display label for this node
  ---@return string
  function ExceptionFiltersGroup:label()
    return "Exception Filters"
  end

  ---Get count of exception filters (uses rollup on debugger)
  ---@return number
  function ExceptionFiltersGroup:getExceptionFilterCount()
    local debugger = self.debugger:get()
    if not debugger then return 0 end
    return debugger.exceptionFilterCount:get() or 0
  end

  ---Get count of enabled exception filters (uses rollup on debugger)
  ---@return number
  function ExceptionFiltersGroup:getEnabledExceptionFilterCount()
    local debugger = self.debugger:get()
    if not debugger then return 0 end
    return debugger.enabledExceptionFilterCount:get() or 0
  end
end
