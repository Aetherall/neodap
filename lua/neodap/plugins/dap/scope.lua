-- Scope entity DAP methods
local entities = require("neodap.entities")
local uri = require("neodap.uri")
local context = require("neodap.plugins.dap.context")
local utils = require("neodap.plugins.dap.utils")
local a = require("neodap.async")

local Scope = entities.Scope

local get_dap_session = context.get_dap_session

---Fetch variables and populate Variable entities
---@param self neodap.entities.Scope
function Scope:fetchVariables()
  -- Check if variables already exist (avoid duplicate fetches)
  for _ in self.variables:iter() do
    return
  end

  -- Traverse to find session for DAP access
  local frame = self.frame:get()
  local stack = frame and frame.stack:get()
  local thread = stack and stack.thread:get()
  local session = thread and thread.session:get()

  if not session then
    error("No session", 0)
  end

  local dap_session = get_dap_session(session)
  if not dap_session then
    error("No DAP session", 0)
  end

  local graph = self._graph
  local vars_ref = self.variablesReference:get()

  if not vars_ref or vars_ref == 0 then
    return
  end

  -- Get sessionId for URI
  local session_id = session.sessionId:get()

  local body = a.wait(function(cb)
    dap_session.client:request("variables", {
      variablesReference = vars_ref,
    }, cb)
  end, "fetchVariables:request")

  -- Create Variable entities
  for _, var_data in ipairs(body.variables or {}) do
    local variable = entities.Variable.new(graph, {
      uri = uri.variable(session_id, vars_ref, var_data.name),
      name = var_data.name,
      value = var_data.value,
      varType = var_data.type,
      variablesReference = var_data.variablesReference or 0,
      evaluateName = var_data.evaluateName,
    })
    self.variables:link(variable)
  end
end

Scope.fetchVariables = a.memoize(Scope.fetchVariables)

return Scope
