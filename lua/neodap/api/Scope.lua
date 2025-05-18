local Class = require('neodap.tools.class')

local Variable = require('neodap.api.Variable')


---@class api.ScopeProps
---@field frame api.Frame
---@field ref dap.Scope
---@field _variables api.Variable[] | nil

---@class api.Scope: api.ScopeProps
---@field new Constructor<api.ScopeProps>
local Scope = Class()


---@param frame api.Frame
---@param scope dap.Scope
function Scope.instanciate(frame, scope)
  local instance = Scope:new({
    frame = frame,
    ref = scope,
    _variables = nil,
  })
  return instance
end

---@return api.Variable[]
function Scope:variables()
  if self._variables then
    return self._variables
  end

  local response = self.frame.stack.thread.session.ref.calls:variables({
    variablesReference = self.ref.variablesReference,
    threadId = self.frame.stack.thread.id,
  }):wait()

  self._variables = vim.tbl_map(function(variable)
    return Variable.instanciate(self, variable)
  end, response.variables)

  return self._variables
end

return Scope
