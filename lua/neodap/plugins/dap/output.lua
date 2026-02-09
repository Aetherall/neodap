-- Output entity DAP methods
local entities = require("neodap.entities")
local uri = require("neodap.uri")
local context = require("neodap.plugins.dap.context")
local a = require("neodap.async")

local Output = entities.Output

local get_dap_session = context.get_dap_session

---Fetch child variables for structured output
---@param self neodap.entities.Output
function Output:fetchChildren()
  -- Check if children already exist (avoid duplicate fetches)
  for _ in self.children:iter() do
    return
  end

  local vars_ref = self.variablesReference:get()
  if not vars_ref or vars_ref == 0 then
    return
  end

  -- Get session directly from output
  local session = self.session:get()
  if not session then
    error("No session", 0)
  end

  local dap_session = get_dap_session(session)
  if not dap_session then
    error("No DAP session", 0)
  end

  local graph = self._graph
  local session_id = session.sessionId:get()

  local body = a.wait(function(cb)
    dap_session.client:request("variables", {
      variablesReference = vars_ref,
    }, cb)
  end, "Output:fetchChildren:request")

  -- Create child Variable entities
  for _, var_data in ipairs(body.variables or {}) do
    local child = entities.Variable.new(graph, {
      uri = uri.variable(session_id, vars_ref, var_data.name),
      name = var_data.name,
      value = var_data.value,
      varType = var_data.type,
      variablesReference = var_data.variablesReference or 0,
      evaluateName = var_data.evaluateName,
    })
    self.children:link(child)
  end
end

Output.fetchChildren = a.memoize(Output.fetchChildren)

return Output
