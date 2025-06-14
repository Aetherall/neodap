local Class = require('neodap.tools.class')
local Scope = require('neodap.api.Session.Scope.BaseScope')

---@class api.LocalsScope: api.Scope
local LocalsScope = Class(Scope)

---@param frame api.Frame
---@param scope dap.Scope
---@return api.LocalsScope
function LocalsScope.instanciate(frame, scope)
  local instance = LocalsScope:new({
    frame = frame,
    --- State
    _variables = nil,
    _source = scope.source and frame.stack.thread.session:getSourceFor(scope.source),
    --- DAP
    ref = scope,
    type = 'locals',
  })
  return instance
end

---Get a specific local variable by name
---@param name string
---@return api.Variable|nil
function LocalsScope:getLocal(name)
  local variables = self:variables()
  if not variables then return nil end

  for _, variable in ipairs(variables) do
    if variable.ref.name == name then
      return variable
    end
  end
  return nil
end

return LocalsScope
