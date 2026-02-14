-- Variable entity methods for neograph-native
local normalize = require("neodap.utils").normalize

return function(Variable)
  ---Get value with newlines normalized to spaces
  ---@return string
  function Variable:displayValue()
    local value = self.value:get() or ""
    return value:gsub("\n", " ")
  end

  ---Get type name, or nil if unavailable
  ---@return string|nil
  function Variable:displayType()
    local vtype = normalize(self.varType:get())
    if vtype and vtype ~= "" then return vtype end
    return nil
  end

  ---Get the session this variable belongs to
  ---Walks parent chain to find session via scope, frame, or output attachment
  ---@return neodap.entities.Session?
  function Variable:session()
    local var = self
    while var do
      local scope = var.scope:get()
      if scope then return scope:session() end
      local frame = var.frame:get()
      if frame then return frame:session() end
      local output = var.output:get()
      if output then return output.session:get() end
      var = var.parent:get()
    end
  end

  ---Check if variable's session is terminated
  ---Returns true if terminated OR if unable to determine (safe default)
  ---@return boolean
  function Variable:isSessionTerminated()
    local session = self:session()
    if not session then return true end
    return session:isTerminated()
  end
end
