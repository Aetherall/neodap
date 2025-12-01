---@class Variable : Class
---@field parent Scope|Variable  -- Parent can be scope or another variable
---@field name string
---@field value Signal<string>
---@field type Signal<string?>
---@field variablesReference number
---@field evaluateName string?
---@field presentationHint dap.VariablePresentationHint?
---@field stack_id string?  -- Stack ID for scope-based variables (for indexing)

local neostate = require("neostate")
local VariableContainer = require("neodap.sdk.session.variable_container")

local M = {}

-- =============================================================================
-- VARIABLE
-- =============================================================================

---@class Variable : Class
local Variable = neostate.Class("Variable")

function Variable:init(parent, data)
  self.parent = parent
  self.name = data.name
  self.evaluateName = data.evaluateName
  self.presentationHint = data.presentationHint

  self.value = self:signal(data.value, "value")
  self.type = self:signal(data.type, "type")

  -- Cache references for O(1) access (used by collection indexes)
  self.session, self.container_id, self.container_type, self.stack_id = self:_compute_hierarchy()

  -- Build URI based on container type
  local var_path = data.evaluateName or data.name
  if self.container_type == "scope" then
    -- Variables from scope: use parent scope's URI + var
    if parent.uri then
      self.uri = parent.uri .. "/var:" .. var_path
    end
  elseif self.container_type == "eval" then
    -- Variables from evaluation result: dap:session:<sid>/eval:<id>/var:<path>
    self.uri = "dap:session:" .. self.session.id .. "/eval:" .. self.container_id .. "/var:" .. var_path
  elseif self.container_type == "output" then
    -- Variables from output: dap:session:<sid>/output:<id>/var:<path>
    self.uri = "dap:session:" .. self.session.id .. "/output:" .. self.container_id .. "/var:" .. var_path
  end

  self.key = "var:" .. (data.evaluateName or data.name)
  self._type = "variable"

  -- Initialize variable container trait
  VariableContainer.init_variable_container(
    self,
    data.variablesReference,
    data.namedVariables,
    data.indexedVariables
  )

  self._is_current = self:signal(true, "is_current")
end

---Check if this variable is current (stack not expired)
---@return boolean
function Variable:is_current()
  return self._is_current:get()
end

---Mark this variable as expired (scope/frame/stack expired)
---Propagates expiration to all child variables (recursive)
---@private
function Variable:_mark_expired()
  self._is_current:set(false)

  -- Propagate to child variables (if loaded) via EntityStore View
  if self._variables_fetched and self.uri then
    local debugger = self.session.debugger
    for variable in debugger.variables:where("by_parent_uri", self.uri):iter() do
      variable:_mark_expired()
    end
  end
end

---Get frame ID by traversing parent chain
---@return number?
function Variable:_get_frame_id()
  local current = self.parent
  while current do
    if current.frame then
      -- Parent is a Scope
      return current.frame.id
    elseif current.parent then
      -- Parent is a Variable, traverse up
      current = current.parent
    else
      return nil
    end
  end
  return nil
end

---Compute hierarchy info by traversing parent chain (called once during init)
---@return Session, string, string, string?  -- session, container_id, container_type, stack_id
function Variable:_compute_hierarchy()
  local current = self.parent
  while current do
    -- Check for EvaluateResult first (has is_evaluate_result method)
    if current.is_evaluate_result and current:is_evaluate_result() then
      return current.session, current.id, "eval", nil
    -- Check for Output (has category field)
    elseif current.category then
      return current:_get_session(), tostring(current.index or 0), "output", nil
    -- Check for Scope (has frame AND name - distinguishes from EvaluateResult)
    elseif current.frame and current.name then
      local scope = current
      local frame = scope.frame
      local stack = frame.stack
      local session = stack.thread.session
      return session, scope.name, "scope", stack.id
    -- Check for Variable parent (has parent field)
    elseif current.parent then
      current = current.parent
    -- Fallback for any container with _get_session
    elseif current._get_session then
      local session = current:_get_session()
      return session, "unknown", "unknown", nil
    else
      error("Variable hierarchy broken - no container found")
    end
  end
  error("Variable hierarchy broken - no container found")
end

---Get the session for this variable (required by VariableContainer trait)
---@return Session
function Variable:_get_session()
  return self.session
end

-- Add VariableContainer trait methods
Variable.variables = VariableContainer.variables
Variable.fetch_variables = VariableContainer.fetch_variables

---Fetch children (calls variables if has reference, otherwise no-op)
---@return View|{} variables View of child variables or empty table
function Variable:children()
  if self.variablesReference and self.variablesReference > 0 then
    return self:variables()
  end
  return {}
end

---Get a child variable by name
---@param name string Child variable name
---@return Variable?
function Variable:child(name)
  local children = self:variables()
  if not children then return nil end
  for var in children:iter() do
    if var.name == name then
      return var
    end
  end
  return nil
end

---Set the value of this variable
---@param new_value string
---@return string? error, string? value, string? type
function Variable:set_value(new_value)
  local session = self:_get_session()

  -- Need to find the frame and variablesReference
  -- Walk up to find parent scope or variable
  local variables_reference
  if self.parent.variablesReference then
    variables_reference = self.parent.variablesReference
  else
    -- Parent is scope
    variables_reference = self.parent.variablesReference
  end

  local result, err = neostate.settle(session.client:request("setVariable", {
    variablesReference = variables_reference,
    name = self.name,
    value = new_value,
  }))

  if err then
    return err, nil, nil
  end

  -- Update our local state
  self.value:set(result.value)
  if result.type then
    self.type:set(result.type)
  end
  if result.variablesReference then
    self.variablesReference = result.variablesReference
    -- Clear children cache (structure may have changed)
    self._variables_fetched = false
    self._variables_view = nil
  end
  return nil, result.value, result.type
end

M.Variable = Variable

-- Backwards compatibility
function M.create(parent, data)
  return Variable:new(parent, data)
end

return M
