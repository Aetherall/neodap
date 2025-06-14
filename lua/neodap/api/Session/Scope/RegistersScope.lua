local Class = require('neodap.tools.class')
local Scope = require('neodap.api.Session.Scope.BaseScope')

---@class api.RegistersScope: api.Scope
local RegistersScope = Class(Scope)

---@param frame api.Frame
---@param scope dap.Scope
---@return api.RegistersScope
function RegistersScope.instanciate(frame, scope)
  local instance = RegistersScope:new({
    frame = frame,
    --- State
    _variables = nil,
    _source = scope.source and frame.stack.thread.session:getSourceFor(scope.source),
    --- DAP
    ref = scope,
    type = 'registers',
  })
  return instance
end

---Get a specific register by name
---@param name string
---@return api.Variable|nil
function RegistersScope:getRegister(name)
  local variables = self:variables()
  if not variables then return nil end

  for _, variable in ipairs(variables) do
    if variable.ref.name == name then
      return variable
    end
  end
  return nil
end

return RegistersScope
