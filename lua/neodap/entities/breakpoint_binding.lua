-- BreakpointBinding entity methods for neograph-native
local Location = require("neodap.location")

return function(BreakpointBinding)
  function BreakpointBinding:isVerified()
    return self.verified:get() == true
  end

  function BreakpointBinding:isPending()
    return self.verified:get() ~= true
  end

  function BreakpointBinding:isMoved()
    local actualLine = self.actualLine:get()
    if not actualLine or actualLine == 0 then return false end
    -- Use rollup for one-to-one access
    local breakpoint = self.breakpoint:get()
    if not breakpoint then return false end
    return actualLine ~= breakpoint.line:get()
  end

  ---Get actual location as Location object (supports virtual sources via bufferUri)
  ---@return neodap.Location?
  function BreakpointBinding:actualLocation()
    -- Use rollups for one-to-one access
    local bp = self.breakpoint:get()
    if not bp then return nil end
    local source = bp.source:get()
    if not source then return nil end
    local uri = source:bufferUri()
    if not uri then return nil end
    return Location.new(uri, self.actualLine:get(), self.actualColumn:get())
  end

  function BreakpointBinding:matchKey(key)
    local bp = self.breakpoint:get()
    return bp and bp:matchKey(key)
  end
end
