-- Test factory module to isolate the issue
local GenericScope = require('neodap.api.Scope.GenericScope')

local ScopeFactory = {}

function ScopeFactory.instanciate(frame, scope)
  return GenericScope.instanciate(frame, scope)
end

return ScopeFactory
