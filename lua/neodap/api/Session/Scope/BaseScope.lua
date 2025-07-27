local Class = require('neodap.tools.class')
local Variable = require('neodap.api.Session.Variable')
local RangedScopeTrait = require('neodap.api.Session.Scope.traits.RangedScopeTrait')

---@class api.ScopeProps
---@field type 'arguments' | 'locals' | 'globals' | 'returnValue' | 'registers' | 'generic'
---@field frame api.Frame
---@field ref dap.Scope
---@field _variables api.Variable[] | nil
---@field protected _source api.Source | nil

---@class api.Scope: api.ScopeProps, api.RangedScopeTrait
---@field new Constructor<api.ScopeProps>
local Scope = RangedScopeTrait.extend(Class())

---@param frame api.Frame
---@param scope dap.Scope
---@return api.Scope
function Scope.instanciate(frame, scope)
  -- Determine scope type based on presentationHint (same logic as old factory)
  local presentationHint = scope.presentationHint
  local scopeName = scope.name and scope.name:lower() or ""
  
  local scopeType = "generic"  -- default
  if presentationHint == "arguments" then 
    scopeType = "arguments"
  elseif presentationHint == "locals" then 
    scopeType = "locals"
  elseif presentationHint == "registers" then 
    scopeType = "registers"
  elseif presentationHint == "returnValue" then 
    scopeType = "returnValue"
  elseif scopeName:match("global") or scopeName:match("window") then 
    scopeType = "globals"
  end

  local instance = Scope:new({
    frame = frame,
    --- State
    _variables = nil,
    _source = scope.source and frame.stack.thread.session:getSourceFor(scope.source),
    --- DAP
    ref = scope,
    type = scopeType,
  })
  return instance
end

---@return_cast self api.ArgumentsScope
function Scope:isArguments()
  return self.type == 'arguments'
end

---@return_cast self api.LocalsScope
function Scope:isLocals()
  return self.type == 'locals'
end

---@return_cast self api.GlobalsScope
function Scope:isGlobals()
  return self.type == 'globals'
end

---@return_cast self api.ReturnValueScope
function Scope:isReturnValue()
  return self.type == 'returnValue'
end

---@return_cast self api.RegistersScope
function Scope:isRegisters()
  return self.type == 'registers'
end

---@return_cast self api.GenericScope
function Scope:isGeneric()
  return self.type == 'generic'
end

---@return {[integer]: api.Variable} | nil
function Scope:variables()
  if self._variables then
    return self._variables
  end

  local response = self.frame.stack.thread.session.ref.calls:variables({
    variablesReference = self.ref.variablesReference,
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

function Scope:toStringDescription()
  local source = self:source()

  if self:hasRange() then
    local rangeString = self:rangeLinkSuffix()

    if not source then
      return string.format("%s %s", self.ref.name, rangeString)
    end

    return string.format("%s (%s) %s", self.ref.name, source:toString(), rangeString)
  end

  if not source then
    return self.ref.name
  end

  return string.format("%s (%s)", self.ref.name, source:toString())
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
