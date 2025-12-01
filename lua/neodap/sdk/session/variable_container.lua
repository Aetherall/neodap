---@class VariableContainerTrait
-- A trait that adds lazy variable loading to any class that has:
-- - variablesReference field
-- - A way to get the session (via _get_session() method)
--
-- This trait is used by:
-- - Scope (container for variables in a frame)
-- - Variable (can have child variables)
-- - EvaluateResult (result of expression evaluation)
-- - Output (debug output with structured data)

local M = {}

---Initialize the variable container fields
---@param self any The instance to add container behavior to
---@param variablesReference number The DAP variablesReference (0 means no children)
---@param namedVariables? number Optional hint for number of named children
---@param indexedVariables? number Optional hint for number of indexed children
function M.init_variable_container(self, variablesReference, namedVariables, indexedVariables)
  self.variablesReference = variablesReference or 0
  self.namedVariables = namedVariables
  self.indexedVariables = indexedVariables
  self._variables_fetched = false
end

---Get variables (lazy load if needed)
---@param self any
---@return View View of child variables
function M.variables(self)
  -- Fetch from DAP if not yet loaded
  if not self._variables_fetched then
    self:fetch_variables()
  end

  -- Return cached View
  if not self._variables_view then
    local session = self:_get_session()
    if session and self.uri then
      local debugger = session.debugger
      self._variables_view = debugger.variables:where(
        "by_parent_uri",
        self.uri,
        "Variables:" .. self.uri
      )
    end
  end
  return self._variables_view
end

---Fetch variables from DAP
---@param self any
---@private
function M.fetch_variables(self)
  -- Check if already loaded or in progress
  if self._variables_fetched then
    return
  end

  -- No children to fetch
  if self.variablesReference == 0 then
    self._variables_fetched = true
    return
  end

  -- Get session (each class implements this differently)
  local session = self:_get_session()
  if not session then
    self._variables_fetched = true
    return
  end

  -- Mark as fetched BEFORE async request to prevent concurrent fetches
  -- (settle yields, allowing other coroutines to call this method)
  self._variables_fetched = true

  local neostate = require("neostate")
  local result, err = neostate.settle(session.client:request("variables", {
    variablesReference = self.variablesReference,
  }))

  if err or not result or not result.variables then
    return
  end

  -- Create Variable entities
  local Variable = require("neodap.sdk.session.variable")

  -- Get debugger for global collection
  local debugger = session.debugger

  for _, var_data in ipairs(result.variables) do
    local child_var = Variable.Variable:new(self, var_data)
    child_var:set_parent(self)

    -- Add to EntityStore with "variable" edge to parent (scope or variable)
    -- Skip if entity already exists (can happen with duplicate variable names)
    if self.uri and child_var.uri and not debugger.store:has(child_var.uri) then
      debugger.store:add(child_var, "variable", {
        { type = "variable", to = self.uri }
      })
    end
  end
end

return M
