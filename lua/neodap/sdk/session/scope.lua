---@class Scope : Class
---@field frame Frame
---@field name string  -- "Locals", "Globals", "Registers", etc.
---@field variablesReference number
---@field expensive boolean  -- Whether fetching is expensive
---@field presentationHint string?

local neostate = require("neostate")
local VariableContainer = require("neodap.sdk.session.variable_container")

local M = {}

-- =============================================================================
-- SCOPE
-- =============================================================================

---@class Scope : Class
local Scope = neostate.Class("Scope")

function Scope:init(frame, data)
  self.frame = frame
  self.name = data.name
  self.expensive = data.expensive or false
  self.presentationHint = data.presentationHint

  -- URI: dap:session:<session_id>/thread:<thread_id>/stack:<seq>/frame:<frame_id>/scope:<name>
  local session = frame.stack.thread.session
  self.uri = string.format(
    "dap:session:%s/thread:%d/stack:%d/frame:%d/scope:%s",
    session.id,
    frame.stack.thread.id,
    frame.stack.sequence,
    frame.id,
    data.name
  )
  self.key = "scope:" .. data.name
  self._type = "scope"

  -- Initialize variable container trait
  VariableContainer.init_variable_container(
    self,
    data.variablesReference,
    data.namedVariables,
    data.indexedVariables
  )

  self._is_current = self:signal(true, "is_current")

  -- Eager expansion: non-expensive scopes auto-expand in tree
  self.eager = self:signal(not self.expensive, "eager")
end

---Check if this scope is current (stack not expired)
---@return boolean
function Scope:is_current()
  return self._is_current:get()
end

---Mark this scope as expired (frame/stack expired)
---Propagates expiration to all variables
---@private
function Scope:_mark_expired()
  self._is_current:set(false)

  -- Propagate to variables (if loaded) via EntityStore View
  if self._variables_fetched then
    local debugger = self.frame.stack.thread.session.debugger
    for variable in debugger.variables:where("by_parent_uri", self.uri):iter() do
      variable:_mark_expired()
    end
  end
end

---Get session (required by VariableContainer trait)
---@return Session
function Scope:_get_session()
  return self.frame.stack.thread.session
end

-- Add VariableContainer trait methods
Scope.variables = VariableContainer.variables
Scope.fetch_variables = VariableContainer.fetch_variables

---Fetch children (calls variables if has reference, otherwise no-op)
---@return View|{} variables View of child variables or empty table
function Scope:children()
  if self.variablesReference and self.variablesReference > 0 then
    return self:variables()
  end
  return {}
end

---Get a child variable by name
---@param name string Child variable name
---@return Variable?
function Scope:child(name)
  local children = self:variables()
  if not children then return nil end
  for var in children:iter() do
    if var.name == name then
      return var
    end
  end
  return nil
end

M.Scope = Scope

-- Backwards compatibility
function M.create(frame, data)
  return Scope:new(frame, data)
end

return M
