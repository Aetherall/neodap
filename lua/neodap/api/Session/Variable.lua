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
