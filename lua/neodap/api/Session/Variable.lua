local Class = require('neodap.tools.class')


---@class api.VariableProps
---@field scope api.Scope
---@field ref dap.Variable

---@class (partial) api.Variable: api.VariableProps
---@field new Constructor<api.VariableProps>
local Variable = Class()


---@param scope api.Scope
---@param variable dap.Variable
function Variable.instanciate(scope, variable)
  local instance = Variable:new({
    scope = scope,
    ref = variable,
  })
  return instance
end

function Variable:resolve()
  -- Check if this is a lazy variable that needs resolution
  if not (self.ref.presentationHint and self.ref.presentationHint.lazy) then
    return nil
  end

  -- Lazy variables must have a variablesReference to fetch the actual value
  if not self.ref.variablesReference or self.ref.variablesReference == 0 then
    return nil
  end

  -- For lazy variables, we fetch the children which should contain a single variable
  -- with the actual resolved value
  local variables = self.scope.frame:variables(self.ref.variablesReference)
  
  if not variables or #variables ~= 1 then
    -- DAP spec says lazy variables should return exactly one child
    return nil
  end

  local resolved = variables[1]
  
  if not resolved then
    return nil
  end

  -- Update this variable's properties with the resolved variable's data
  -- The resolved variable typically has no name, just value and type
  self.ref.value = resolved.value or self.ref.value
  self.ref.type = resolved.type or self.ref.type
  self.ref.variablesReference = resolved.variablesReference or 0
  
  -- Copy over any new presentation hints from the resolved variable
  if resolved.presentationHint then
    self.ref.presentationHint = vim.tbl_extend("force", self.ref.presentationHint or {}, resolved.presentationHint)
  end
  
  -- Clear the lazy flag since we've resolved it
  if self.ref.presentationHint then
    self.ref.presentationHint.lazy = false
  end
  
  -- Return the resolved variable data
  return resolved
end

function Variable:toString()
  if self.ref.evaluateName and self.ref.value then
    return string.format('%s: %s', self.ref.evaluateName, self.ref.value)
  elseif self.ref.name and self.ref.value then
    return string.format('%s: %s', self.ref.name, self.ref.value)
  elseif self.ref.name then
    return self.ref.name
  else
    return ''
  end
end

return Variable
