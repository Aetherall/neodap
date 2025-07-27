local BaseScope = require('neodap.api.Session.Scope.BaseScope')

-- Simplified factory - just delegates to BaseScope.instanciate()
local ScopeFactory = {}

---@param frame api.Frame
---@param scope dap.Scope
---@return api.Scope
function ScopeFactory.instanciate(frame, scope)
  return BaseScope.instanciate(frame, scope)
end

return ScopeFactory

