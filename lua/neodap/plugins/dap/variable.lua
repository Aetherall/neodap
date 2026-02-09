-- Variable entity DAP methods
local entities = require("neodap.entities")
local uri = require("neodap.uri")
local context = require("neodap.plugins.dap.context")
local utils = require("neodap.plugins.dap.utils")
local a = require("neodap.async")

local Variable = entities.Variable

local get_dap_session = context.get_dap_session

---Find session by traversing up from variable
---Handles scope-found, frame-found (expression), and output-found variables
---@param self neodap.entities.Variable
---@return table? session, table? frame
local function find_session_and_frame(self)
  -- Try scope path first (scope-found variables)
  local var = self
  local scope = var.scope:get()
  while not scope and var do
    var = var.parent:get()
    if var then
      scope = var.scope:get()
    end
  end

  if scope then
    local frame = scope.frame:get()
    local stack = frame and frame.stack:get()
    local thread = stack and stack.thread:get()
    local session = thread and thread.session:get()
    return session, frame
  end

  -- Try frame path (expression-found variables)
  local frame = self.frame:get()
  if frame then
    local stack = frame.stack:get()
    local thread = stack and stack.thread:get()
    local session = thread and thread.session:get()
    return session, frame
  end

  -- Try output path (variables from console evaluations)
  local output = self.output:get()
  if output then
    local session = output.session:get()
    return session, nil
  end

  -- Try parent chain for nested variables
  var = self.parent:get()
  while var do
    local session, frm = find_session_and_frame(var)
    if session then
      return session, frm
    end
    var = var.parent:get()
  end

  return nil, nil
end

---Fetch child variables
---@param self neodap.entities.Variable
function Variable:fetchChildren()
  -- Check if children already exist (avoid duplicate fetches)
  for _ in self.children:iter() do
    return
  end

  local session, _ = find_session_and_frame(self)
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
---Uses setExpression if variable has evaluateName, otherwise setVariable
---@param self neodap.entities.Variable
---@param newValue string
function Variable:setValue(newValue)
  local session, frame = find_session_and_frame(self)
  if not session then
    error("No session", 0)
  end

  local dap_session = get_dap_session(session)
  if not dap_session then
    error("No DAP session", 0)
  end

  local evaluateName = self.evaluateName:get()
  local scope = self.scope:get()
  local parent = self.parent:get()

  local body

  if evaluateName and frame then
    -- Use setExpression (address by expression)
    if not dap_session.capabilities or not dap_session.capabilities.supportsSetExpression then
      error("Adapter does not support setExpression", 0)
    end

    body = a.wait(function(cb)
      dap_session.client:request("setExpression", {
        expression = evaluateName,
        value = newValue,
        frameId = frame.frameId:get(),
      }, cb)
    end, "Variable:setValue:setExpression")

  elseif scope then
    -- Use setVariable with scope's variablesReference
    body = a.wait(function(cb)
      dap_session.client:request("setVariable", {
        variablesReference = scope.variablesReference:get(),
        name = self.name:get(),
        value = newValue,
      }, cb)
    end, "Variable:setValue:setVariable:scope")

  elseif parent then
    -- Use setVariable with parent's variablesReference
    local parent_ref = parent.variablesReference:get()
    if not parent_ref or parent_ref == 0 then
      error("Parent has no variablesReference", 0)
    end

    body = a.wait(function(cb)
      dap_session.client:request("setVariable", {
        variablesReference = parent_ref,
        name = self.name:get(),
        value = newValue,
      }, cb)
    end, "Variable:setValue:setVariable:parent")

  else
    error("Variable is not editable (no evaluateName, scope, or parent)", 0)
  end

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
