-- Breakpoint entity methods for neograph-native
local Location = require("neodap.location")

return function(Breakpoint)
  function Breakpoint:isEnabled()
    local enabled = self.enabled:get()
    if enabled == nil then return true end
    return enabled
  end

  function Breakpoint:enable()
    self:update({ enabled = true })
  end

  function Breakpoint:disable()
    self:update({ enabled = false })
  end

  function Breakpoint:toggle()
    self:update({ enabled = not self:isEnabled() })
  end

  ---Get location as Location object (supports virtual sources via bufferUri)
  ---@return neodap.Location?
  function Breakpoint:location()
    return Location.fromEntity(self)
  end

  ---Sync this breakpoint's source to the debug adapter
  ---Call after modifying the breakpoint to send changes to all active sessions
  function Breakpoint:sync()
    local source = self.source:get()
    if source then source:syncBreakpoints() end
  end

  -- Find the binding that determines display state (hit > verified)
  -- Uses rollups: hitBinding, verifiedBinding
  function Breakpoint:dominatedBinding()
    -- Use reference rollups for efficient lookup
    local hit = self.hitBinding:get()
    if hit then return hit, true end

    local verified = self.verifiedBinding:get()
    return verified, false
  end

  ---Get display-oriented state string
  ---Unlike state() which returns "unbound"/"bound", this accounts for enabled status
  ---and uses display-oriented names.
  ---@return string "disabled"|"hit"|"adjusted"|"verified"|"unverified"
  function Breakpoint:displayState()
    if not self:isEnabled() then return "disabled" end
    local binding, is_hit = self:dominatedBinding()
    if not binding then return "unverified" end
    if is_hit then return "hit" end
    local bp_line = self.line:get()
    local b_line = binding.actualLine:get()
    if b_line and b_line ~= bp_line then return "adjusted" end
    return "verified"
  end

  ---Compute current mark state (synchronous, not reactive)
  ---@return {state: string, line: number, column: number, path: string?}?
  function Breakpoint:getMark()
    if self:isDeleted() then return nil end
    local loc = self:location()
    local path = loc and loc.path
    local bp_line, bp_col = self.line:get(), self.column:get() or 1

    if not self:isEnabled() then
      return { state = "disabled", line = bp_line, column = bp_col, path = path }
    end

    -- Use reference rollups
    local hit = self.hitBinding:get()
    if hit then
      local line = hit.actualLine:get() or bp_line
      local col = hit.actualColumn:get() or bp_col
      return { state = "hit", line = line, column = col, path = path }
    end

    local verified = self.verifiedBinding:get()
    if verified then
      local line = verified.actualLine:get() or bp_line
      local col = verified.actualColumn:get() or bp_col
      local adjusted = (line ~= bp_line) or (self.column:get() and col ~= bp_col)
      local state = adjusted and "adjusted" or "bound"
      return { state = state, line = line, column = col, path = path }
    end

    return { state = "unbound", line = bp_line, column = bp_col, path = path }
  end
end
