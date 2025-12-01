---@class EvaluateResult : Class
---@field id string  -- Unique identifier for this evaluation result
---@field session Session  -- Direct session reference (independent of frame lifecycle)
---@field expression string  -- The expression that was evaluated
---@field context string  -- "watch"|"repl"|"hover"|"clipboard"|"variables"
---@field result string  -- Display value
---@field type string?  -- Type information
---@field variablesReference number
---@field presentationHint dap.VariablePresentationHint?
---@field memoryReference string?
---@field uri string  -- URI for this evaluation result

local neostate = require("neostate")
local VariableContainer = require("neodap.sdk.session.variable_container")

local M = {}

-- Counter for unique evaluation result IDs
local eval_counter = 0

-- =============================================================================
-- EVALUATE RESULT
-- =============================================================================

---@class EvaluateResult : Class
local EvaluateResult = neostate.Class("EvaluateResult")

function EvaluateResult:init(session, expression, context, data)
  -- Generate unique ID
  eval_counter = eval_counter + 1
  self.id = tostring(eval_counter)

  -- Store session directly (not frame - we have independent lifetime)
  self.session = session
  self.expression = expression
  self.context = context or "repl"

  self.result = data.result
  self.type = data.type
  self.presentationHint = data.presentationHint
  self.memoryReference = data.memoryReference

  -- Build URI: dap:session:<sid>/eval:<id>
  self.uri = "dap:session:" .. session.id .. "/eval:" .. self.id
  self.key = "eval:" .. self.id
  self._type = "evaluate_result"

  -- Eager expansion: evaluation results auto-expand in tree views
  self.eager = true

  -- Initialize variable container trait
  VariableContainer.init_variable_container(
    self,
    data.variablesReference,
    data.namedVariables,
    data.indexedVariables
  )

  -- Add to EntityStore with parent edge to session
  local debugger = session.debugger
  if debugger then
    debugger.store:add(self, "evaluate_result", {
      { type = "parent", to = session.uri }
    })
  end
end

---Get session (required by VariableContainer trait)
---@return Session
function EvaluateResult:_get_session()
  return self.session
end

---Check if this is an EvaluateResult (used by Variable._compute_hierarchy)
---@return boolean
function EvaluateResult:is_evaluate_result()
  return true
end

-- Add VariableContainer trait methods
EvaluateResult.variables = VariableContainer.variables
EvaluateResult.fetch_variables = VariableContainer.fetch_variables

---Fetch children (calls variables if has reference, otherwise no-op)
---@return View|{} variables View of child variables or empty table
function EvaluateResult:children()
  if self.variablesReference and self.variablesReference > 0 then
    return self:variables()
  end
  return {}
end

---Get a child variable by name
---@param name string Child variable name
---@return Variable?
function EvaluateResult:child(name)
  local children = self:variables()
  if not children then return nil end
  for var in children:iter() do
    if var.name == name then
      return var
    end
  end
  return nil
end

M.EvaluateResult = EvaluateResult

-- Backwards compatibility (now takes session instead of frame)
function M.create(session, expression, context, data)
  return EvaluateResult:new(session, expression, context, data)
end

return M
