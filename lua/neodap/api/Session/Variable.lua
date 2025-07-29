local Class = require('neodap.tools.class')


---@class api.VariableProps
---@field scope api.Scope
---@field ref dap.Variable

---@class (partial) api.Variable: api.VariableProps
---@field name string The variable name
---@field new Constructor<api.VariableProps>
local Variable = Class()


---@param scope api.Scope
---@param variable dap.Variable
function Variable.instanciate(scope, variable)
  local instance = Variable:new({
    scope = scope,
    ref = variable,
    name = variable.name,  -- Add name directly as a field
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
  
  if not variables then
    return nil
  end

  -- Handle two cases:
  -- 1. Standard lazy variables: return exactly one child with the resolved value
  -- 2. Chrome DevTools quirk: returns multiple children for function properties
  
  if #variables == 1 then
    -- Standard case: single resolved value
    local resolved = variables[1]
    
    if not resolved then
      return nil
    end

    -- Update this variable's properties with the resolved variable's data
    self.ref.value = resolved.value or self.ref.value
    self.ref.type = resolved.type or self.ref.type
    self.ref.variablesReference = resolved.variablesReference or 0
    
    -- Copy over any new presentation hints from the resolved variable
    if resolved.presentationHint then
      self.ref.presentationHint = vim.tbl_extend("force", self.ref.presentationHint or {}, resolved.presentationHint)
    end
  else
    -- Chrome DevTools case: multiple children returned
    -- This means the lazy variable was actually just marking that children need to be fetched
    -- The variable itself doesn't change, but now we know it has children
    -- Keep the original variable properties but mark it as having children
    if self.ref.variablesReference and self.ref.variablesReference > 0 then
      -- Variable already has a reference, just mark as resolved
    end
  end
  
  -- Clear the lazy flag since we've resolved it
  if self.ref.presentationHint then
    self.ref.presentationHint.lazy = false
  end
  
  -- Return success indicator (the variable data may not have changed for Chrome case)
  return true
end

---@return { [integer]: api.Variable }?
function Variable:variables()
  -- Only variables with a variablesReference > 0 have children
  if not self.ref.variablesReference or self.ref.variablesReference == 0 then
    return nil
  end

  -- Get variables from the session using the reference
  local response = self.scope.frame.session:Variables(self.ref.variablesReference, self.scope.frame.ref.id)
  if not response or not response.variables then
    return {}
  end

  -- Wrap each raw variable into a Variable instance
  local variables = vim.tbl_map(function(variable)
    return Variable.instanciate(self.scope, variable)
  end, response.variables)

  return variables
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
