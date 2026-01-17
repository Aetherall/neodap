-- Output entity methods for neograph-native
local Location = require("neodap.location")

return function(Output)
  ---Get location as Location object (supports virtual sources via bufferUri)
  ---@return neodap.Location?
  function Output:location()
    -- Use rollup for one-to-one access
    local source = self.source:get()
    if not source then return nil end
    local uri = source:bufferUri()
    if not uri then return nil end
    return Location.new(uri, self.line:get(), self.column:get())
  end

  function Output:isStdout()
    return self.category:get() == "stdout"
  end

  function Output:isStderr()
    return self.category:get() == "stderr"
  end

  function Output:isConsole()
    local cat = self.category:get()
    return cat == "console" or cat == "important"
  end

  function Output:isTelemetry()
    return self.category:get() == "telemetry"
  end

  function Output:isGroupStart()
    local group = self.group:get()
    return group == "start" or group == "startCollapsed"
  end

  function Output:isGroupEnd()
    return self.group:get() == "end"
  end

  function Output:hasVariables()
    local ref = self.variablesReference:get()
    return ref ~= nil and ref > 0
  end
end
