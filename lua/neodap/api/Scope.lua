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

function Scope:rangeLinkSuffix()
  local start, finish = self:region()
  return string.format("%d:%d-%d:%d", start[1], start[2], finish[1], finish[2])
end

function Scope:toStringDescription()
  local source = self:source()

  local rangeString = self:rangeLinkSuffix()

  if not source then
    return string.format("%s %s", self.ref.name, rangeString)
  end

  local virtualSource = source:asVirtual()
  if virtualSource then
    return string.format("%s (%s:%s) (%s)", self.ref.name, virtualSource.origin, virtualSource.reference, rangeString)
  end

  local relativePath = source.ref.path and vim.fn.fnamemodify(source.ref.path, ':~:.') or 'unknown'
  return string.format("%s (%s:%s)", self.ref.name, relativePath, rangeString)
end

function Scope:toString()
  local description = self:toStringDescription()

  if self.ref.expensive then
    return description .. " (expensive)"
  end

  local variables = self:variables()
  if not variables or vim.tbl_isempty(variables) then
    return description
  end


  local variableStrings = vim.tbl_map(function(variable)
    return variable:toString()
  end, variables)

  return string.format("%s\n    Variables:\n      %s", description, table.concat(variableStrings, "\n      "))
end

return Scope
