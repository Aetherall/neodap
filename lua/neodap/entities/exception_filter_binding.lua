-- ExceptionFilterBinding entity methods for neograph-native
return function(ExceptionFilterBinding)
  -- Helper to normalize vim.NIL to nil
  local function normalize(value)
    if value == vim.NIL then return nil end
    return value
  end

  ---Get effective enabled state (binding override or global default)
  ---@return boolean
  function ExceptionFilterBinding:getEffectiveEnabled()
    local override = normalize(self.enabled:get())
    if override ~= nil then return override end
    local ef = self.exceptionFilter:get()
    return ef and ef.defaultEnabled:get() or false
  end

  ---Toggle enabled state (creates override)
  function ExceptionFilterBinding:toggle()
    local current = self:getEffectiveEnabled()
    self:update({ enabled = not current })
  end

  ---Clear session override, revert to global default
  function ExceptionFilterBinding:clearOverride()
    -- Use vim.NIL to explicitly set properties to nil (Lua tables drop nil values)
    self:update({ enabled = vim.NIL, condition = vim.NIL })
  end

  ---Check if binding has any override set
  ---@return boolean
  function ExceptionFilterBinding:hasOverride()
    return normalize(self.enabled:get()) ~= nil or normalize(self.condition:get()) ~= nil
  end

  ---Get display label from the underlying ExceptionFilter
  ---@return string
  function ExceptionFilterBinding:displayLabel()
    local ef = self.exceptionFilter:get()
    if not ef then return "?" end
    local label = ef.label:get()
    if label and label ~= "" and label ~= vim.NIL then return label end
    return ef.filterId:get() or "?"
  end

  ---Check if filter supports conditions
  ---@return boolean
  function ExceptionFilterBinding:canHaveCondition()
    local ef = self.exceptionFilter:get()
    return ef and ef.supportsCondition:get() == true
  end
end
