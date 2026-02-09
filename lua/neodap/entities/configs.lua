-- Configs entity methods for neograph-native (UI group entity)
return function(Configs)
  ---Get display label for this node
  ---@return string
  function Configs:label()
    return "Configs"
  end

  ---Get count of active configs (uses activeConfigCount rollup on debugger)
  ---@return number
  function Configs:getConfigCount()
    local debugger = self.debugger:get()
    if not debugger then return 0 end
    return debugger.activeConfigCount:get() or 0
  end
end
