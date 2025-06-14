local Class = require('neodap.tools.class')
local Scope = require('neodap.api.Session.Scope.BaseScope')

---@class api.ReturnValueScope: api.Scope
local ReturnValueScope = Class(Scope)

---@param frame api.Frame
---@param scope dap.Scope
---@return api.ReturnValueScope
function ReturnValueScope.instanciate(frame, scope)
  local instance = ReturnValueScope:new({
    frame = frame,
    --- State
    _variables = nil,
    _source = scope.source and frame.stack.thread.session:getSourceFor(scope.source),
    --- DAP
    ref = scope,
    type = 'returnValue',
  })
  return instance
end

---Get the return value (usually there's only one)
---@return api.Variable|nil
function ReturnValueScope:getReturnValue()
  local variables = self:variables()
  if not variables or #variables == 0 then return nil end
  return variables[1]
end

return ReturnValueScope
