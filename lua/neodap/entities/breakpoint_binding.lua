-- BreakpointBinding entity methods for neograph-native
local Location = require("neodap.location")

return function(BreakpointBinding)
  -- Helper to normalize vim.NIL to nil
  local function normalize(value)
    if value == vim.NIL then return nil end
    return value
  end

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

  ---Get effective enabled state (binding override or global default)
  ---@return boolean
  function BreakpointBinding:getEffectiveEnabled()
    local override = normalize(self.enabled:get())
    if override ~= nil then return override end
    local bp = self.breakpoint:get()
    return bp and bp:isEnabled() or true
  end

  ---Get effective condition (binding override or global default)
  ---@return string?
  function BreakpointBinding:getEffectiveCondition()
    local override = normalize(self.condition:get())
    if override ~= nil then return override end
    local bp = self.breakpoint:get()
    return bp and normalize(bp.condition:get()) or nil
  end

  ---Get effective hit condition (binding override or global default)
  ---@return string?
  function BreakpointBinding:getEffectiveHitCondition()
    local override = normalize(self.hitCondition:get())
    if override ~= nil then return override end
    local bp = self.breakpoint:get()
    return bp and normalize(bp.hitCondition:get()) or nil
  end

  ---Get effective log message (binding override or global default)
  ---@return string?
  function BreakpointBinding:getEffectiveLogMessage()
    local override = normalize(self.logMessage:get())
    if override ~= nil then return override end
    local bp = self.breakpoint:get()
    return bp and normalize(bp.logMessage:get()) or nil
  end

  ---Toggle enabled state (creates override)
  function BreakpointBinding:toggle()
    local current = self:getEffectiveEnabled()
    self:update({ enabled = not current })
  end

  ---Clear session override, revert to global default
  function BreakpointBinding:clearOverride()
    -- Use vim.NIL to explicitly set properties to nil (Lua tables drop nil values)
    self:update({
      enabled = vim.NIL,
      condition = vim.NIL,
      hitCondition = vim.NIL,
      logMessage = vim.NIL,
    })
  end

  ---Check if binding has any override set
  ---@return boolean
  function BreakpointBinding:hasOverride()
    return normalize(self.enabled:get()) ~= nil
        or normalize(self.condition:get()) ~= nil
        or normalize(self.hitCondition:get()) ~= nil
        or normalize(self.logMessage:get()) ~= nil
  end
end
