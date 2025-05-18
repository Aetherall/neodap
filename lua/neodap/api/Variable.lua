local Class = require('neodap.tools.class')


---@class api.VariableProps
---@field scope api.Scope
---@field ref dap.Variable

---@class api.Variable: api.VariableProps
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

return Variable
