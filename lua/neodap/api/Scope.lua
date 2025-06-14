local BaseScope = require('neodap.api.Scope.BaseScope')
local ArgumentsScope = require('neodap.api.Scope.ArgumentsScope')
local LocalsScope = require('neodap.api.Scope.LocalsScope')
local GlobalsScope = require('neodap.api.Scope.GlobalsScope')
local ReturnValueScope = require('neodap.api.Scope.ReturnValueScope')
local RegistersScope = require('neodap.api.Scope.RegistersScope')
local GenericScope = require('neodap.api.Scope.GenericScope')

-- Create a factory module that exports the instanciate method
local ScopeFactory = {}

---@param frame api.Frame
---@param scope dap.Scope
---@return api.Scope
function ScopeFactory.instanciate(frame, scope)
  -- Determine scope type based on presentationHint
  local presentationHint = scope.presentationHint
  local scopeName = scope.name and scope.name:lower() or ""

  if presentationHint == "arguments" then
    return ArgumentsScope.instanciate(frame, scope)
  elseif presentationHint == "locals" then
    return LocalsScope.instanciate(frame, scope)
  elseif presentationHint == "registers" then
    return RegistersScope.instanciate(frame, scope)
  elseif presentationHint == "returnValue" then
    return ReturnValueScope.instanciate(frame, scope)
  elseif scopeName:match("global") or scopeName:match("window") then
    -- Handle globals by name if no explicit presentationHint
    return GlobalsScope.instanciate(frame, scope)
  else
    -- Default to GenericScope for unrecognized scope types
    -- Note: Range capabilities are now available on all scope types via hasRange() type guard
    return GenericScope.instanciate(frame, scope)
  end
end

return ScopeFactory

