-- Variable entity DAP methods
local entities = require("neodap.entities")
local uri = require("neodap.uri")
local context = require("neodap.plugins.dap.context")
local utils = require("neodap.plugins.dap.utils")
local a = require("neodap.async")

local Variable = entities.Variable

local get_dap_session = context.get_dap_session

---Fetch child variables
---@param self neodap.entities.Variable
function Variable:fetchChildren()
  -- Check if children already exist (avoid duplicate fetches)
  for _ in self.children:iter() do
    return
  end

  -- Find session by traversing up from scope
  -- For child variables, traverse parent chain to find a variable with a scope
  local var = self
  local scope = var.scope:get()
  while not scope and var do
    var = var.parent:get()
    if var then
      scope = var.scope:get()
    end
  end
  local frame = scope and scope.frame:get()
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
  end, "fetchChildren:request")

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

Variable.fetchChildren = a.memoize(Variable.fetchChildren)

---Set variable value
---@param self neodap.entities.Variable
---@param value string
function Variable:setValue(value)
  local scope = self.scope:get()
  if not scope then
    error("No scope", 0)
  end

  -- Traverse to find session for DAP access
  local frame = scope.frame:get()
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

  local body = a.wait(function(cb)
    dap_session.client:request("setVariable", {
      variablesReference = scope.variablesReference:get(),
      name = self.name:get(),
      value = value,
    }, cb)
  end, "Variable:setValue")

  -- Update the variable value
  local updates = { value = body.value }
  if body.type then
    updates.varType = body.type
  end
  if body.variablesReference then
    updates.variablesReference = body.variablesReference
  end
  self:update(updates)
end
Variable.setValue = a.fn(Variable.setValue)

return Variable
