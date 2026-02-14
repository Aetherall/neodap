-- Scope entity DAP methods
local entities = require("neodap.entities")
local context = require("neodap.plugins.dap.context")
local utils = require("neodap.plugins.dap.utils")
local a = require("neodap.async")

local Scope = entities.Scope

local get_dap_session = context.get_dap_session

---Get the DAP session for this scope (Scope → Session → DapSession)
---@return DapSession? dap_session, neodap.entities.Session? session
function Scope:dapSession()
  local session = self:session()
  if not session then return nil, nil end
  return get_dap_session(session), session
end

---Fetch variables and populate Variable entities
---@param self neodap.entities.Scope
function Scope:fetchVariables()
  utils.fetch_variables(self, self.variables, "fetchVariables")
end

Scope.fetchVariables = a.memoize(Scope.fetchVariables)

return Scope
