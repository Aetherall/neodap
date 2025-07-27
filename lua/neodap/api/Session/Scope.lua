local Class = require('neodap.tools.class')
local Variable = require('neodap.api.Session.Variable')

---@class api.ScopeProps
---@field frame api.Frame
---@field ref dap.Scope

---@class api.Scope: api.ScopeProps
---@field _variables { [integer]: api.Variable }?
---@field _source api.Source?
---@field new Constructor<api.ScopeProps>
local Scope = Class()

---@param frame api.Frame
---@param scope dap.Scope
---@return api.Scope
function Scope.instanciate(frame, scope)
  local instance = Scope:new({
    frame = frame,
    ref = scope,
    _variables = nil,
    _source = scope.source and frame.session:getSourceFor(scope.source),
  })
  return instance
end

---@return { [integer]: api.Variable }?
function Scope:variables()
  if self._variables then
    return self._variables
  end

  local response = self.frame.session:Variables(self.ref.variablesReference, self.frame.ref.id)
  if not response or not response.variables then
    self._variables = {}
    return self._variables
  end

  self._variables = vim.tbl_map(function(variable)
    return Variable.instanciate(self, variable)
  end, response.variables)

  return self._variables
end

---@return api.Source?
function Scope:source()
  return self._source
end

return Scope