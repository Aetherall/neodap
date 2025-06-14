local Class = require('neodap.tools.class')
local Scope = require('neodap.api.Scope.BaseScope')
local Source = require("neodap.api.Source.Source")

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
    _source = scope.source and Source.instanciate(frame.stack.thread, scope.source),
    --- DAP
    ref = scope,
  })
  return instance
end

return GenericScope
