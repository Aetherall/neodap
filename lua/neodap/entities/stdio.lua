-- Stdio entity methods for neograph-native
return function(Stdio)
  ---Get display label for this node
  ---@return string
  function Stdio:label()
    return "Output"
  end

  ---Get count of outputs (uses outputCount property rollup)
  ---@return number
  function Stdio:getOutputCount()
    return self.outputCount:get() or 0
  end

  -- Alias for compatibility with entities/stdio.lua
  Stdio.outputCount = Stdio.getOutputCount
end
