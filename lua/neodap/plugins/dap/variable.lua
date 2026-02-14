-- Variable entity DAP methods
local entities = require("neodap.entities")
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
  -- Walk up parent chain to find a variable with a scope, frame, or output link
  local var = self
  while var do
    -- Scope path (scope-found variables): scope → frame → session
    local scope = var.scope:get()
    if scope then
      return scope:session(), scope.frame:get()
    end

    -- Frame path (expression-found variables): frame → session
    local frame = var.frame:get()
    if frame then
      return frame:session(), frame
    end

    -- Output path (variables from console evaluations): output → session
    local output = var.output:get()
    if output then
      return output.session:get(), nil
    end

    var = var.parent:get()
  end

  return nil, nil
end

---Get the DAP session for this variable (Variable → ... → Session → DapSession)
---@return DapSession? dap_session, neodap.entities.Session? session, neodap.entities.Frame? frame
function Variable:dapSession()
  local session, frame = find_session_and_frame(self)
  if not session then return nil, nil, nil end
  return get_dap_session(session), session, frame
end

---Fetch child variables
---@param self neodap.entities.Variable
function Variable:fetchChildren()
  utils.fetch_variables(self, self.children, "fetchChildren")
end

Variable.fetchChildren = a.memoize(Variable.fetchChildren)

---Set variable value
---Uses setExpression if variable has evaluateName, otherwise setVariable
---@param self neodap.entities.Variable
---@param newValue string
function Variable:setValue(newValue)
  local dap_session, session, frame = self:dapSession()
  if not session then error("No session", 0) end
  if not dap_session then error("No DAP session", 0) end

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
