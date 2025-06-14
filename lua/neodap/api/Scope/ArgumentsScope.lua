local Class = require('neodap.tools.class')
local Scope = require('neodap.api.Scope.BaseScope')
local Source = require("neodap.api.Source.Source")

---@class api.ArgumentsScope: api.Scope
local ArgumentsScope = Class(Scope)

---@param frame api.Frame
---@param scope dap.Scope
---@return api.ArgumentsScope
function ArgumentsScope.instanciate(frame, scope)
  local instance = ArgumentsScope:new({
    frame = frame,
    --- State
    _variables = nil,
    _source = scope.source and Source.instanciate(frame.stack.thread, scope.source),
    --- DAP
    ref = scope,
  })
  return instance
end

---Get a specific argument by name
---@param name string
---@return api.Variable|nil
function ArgumentsScope:getArgument(name)
  local variables = self:variables()
  if not variables then return nil end

  for _, variable in ipairs(variables) do
    if variable.ref.name == name then
      return variable
    end
  end
  return nil
end

---Get all argument names
---@return string[]
function ArgumentsScope:getArgumentNames()
  local variables = self:variables()
  if not variables then return {} end

  local names = {}
  for _, variable in ipairs(variables) do
    table.insert(names, variable.ref.name)
  end
  return names
end

return ArgumentsScope
