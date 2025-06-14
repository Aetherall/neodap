local Class = require('neodap.tools.class')

local Variable = require('neodap.api.Variable')
local Source = require("neodap.api.Source.Source")


---@class api.ScopeProps
---@field frame api.Frame
---@field ref dap.Scope
---@field _variables api.Variable[] | nil
---@field protected _source api.Source | nil

---@class api.Scope: api.ScopeProps
---@field new Constructor<api.ScopeProps>
local Scope = Class()


---@param frame api.Frame
---@param scope dap.Scope
function Scope.instanciate(frame, scope)
  local instance = Scope:new({
    frame = frame,
    --- State
    _variables = nil,
    _source = scope.source and Source.instanciate(frame.stack.thread, scope.source),
    --- DAP
    ref = scope,
  })
  return instance
end

---@return {[integer]: api.Variable} | nil
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

function Scope:source()
  if not self._source then
    return nil
  end

  return self._source
end

function Scope:region()
  local start = { self.ref.line or 1, self.ref.column or 1 }
  local finish = { self.ref.endLine or start[1], self.ref.endColumn or start[2] }
  return start, finish
end

return Scope
