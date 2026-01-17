-- Breakpoints entity methods for neograph-native
return function(Breakpoints)
  ---Get display label for this node
  ---@return string
  function Breakpoints:label()
    return "Breakpoints"
  end

  ---Get count of breakpoints (uses breakpointCount rollup on debugger)
  ---@return number
  function Breakpoints:getBreakpointCount()
    -- Use rollup for one-to-one access
    local debugger = self.debugger:get()
    if not debugger then return 0 end
    -- Use property rollup
    return debugger.breakpointCount:get() or 0
  end

  -- Alias for compatibility with entities/breakpoints.lua
  Breakpoints.breakpointCount = Breakpoints.getBreakpointCount
end
