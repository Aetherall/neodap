-- BreakpointBinding entity methods for neograph-native
local normalize = require("neodap.utils").normalize

return function(BreakpointBinding)

  ---Get effective value for a field: binding override wins, then falls back to breakpoint
  ---@param self table BreakpointBinding entity
  ---@param field string Property name (e.g., "condition", "hitCondition", "logMessage")
  ---@return any?
  local function getEffective(self, field)
    local override = normalize(self[field]:get())
    if override ~= nil then return override end
    local bp = self.breakpoint:get()
    return bp and normalize(bp[field]:get()) or nil
  end

  function BreakpointBinding:isVerified()
    return self.verified:get() == true
  end

  ---Get effective enabled state (binding override or global default)
  ---@return boolean
  function BreakpointBinding:getEffectiveEnabled()
    local override = normalize(self.enabled:get())
    if override ~= nil then return override end
    local bp = self.breakpoint:get()
    if not bp then return true end
    return bp:isEnabled()
  end

  function BreakpointBinding:getEffectiveCondition() return getEffective(self, "condition") end
  function BreakpointBinding:getEffectiveHitCondition() return getEffective(self, "hitCondition") end
  function BreakpointBinding:getEffectiveLogMessage() return getEffective(self, "logMessage") end

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
