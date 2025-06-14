local Class = require('neodap.tools.class')
local Scope = require('neodap.api.Session.Scope.BaseScope')

---@class api.GenericScope: api.Scope
local GenericScope = Class(Scope)

---@param frame api.Frame
---@param scope dap.Scope
---@return api.GenericScope
function GenericScope.instanciate(frame, scope)
  local instance = GenericScope:new({
    frame = frame,
    --- State
    _variables = nil,
    _source = scope.source and frame.stack.thread.session:getSourceFor(scope.source),
    --- DAP
    ref = scope,
    type = 'generic',
  })
  return instance
end

return GenericScope
