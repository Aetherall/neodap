local neostate = require("neostate")

local M = {}

-- =============================================================================
-- OUTPUT
-- =============================================================================

---@class Output : Class
---@field session Session
---@field category string
---@field output string
---@field timestamp number
---@field source dap.Source?
---@field line number?
---@field column number?
---@field variablesReference number
---@field variables Signal<List<Variable>?>  -- Lazy loaded (if variablesReference > 0)
local Output = neostate.Class("Output")

function Output:init(session, body)
  self.session = session
  self.category = body.category
  self.output = body.output
  self.timestamp = vim.loop.now()
  self.source = body.source
  self.line = body.line
  self.column = body.column

  local debugger = session.debugger

  -- Index is the current count of outputs for this session (0-based)
  local index = 0
  if debugger and debugger.outputs then
    -- Count existing outputs for this session
    for _ in debugger.outputs:where("by_session_id", session.id):iter() do
      index = index + 1
    end
  end
  self.index = index

  -- URI: dap:session:<session_id>/output:<index>
  self.uri = "dap:session:" .. session.id .. "/output:" .. index
  self.key = "output:" .. index
  self._type = "output"

  -- Add to EntityStore
  if debugger then
    debugger.store:add(self, "output", {
      { type = "parent", to = session.uri }
    })
  end

  -- Initialize variable container trait if output has structured data
  if body.variablesReference and body.variablesReference > 0 then
    local VariableContainer = require("neodap.sdk.session.variable_container")
    VariableContainer.init_variable_container(
      self,
      body.variablesReference,
      body.namedVariables,
      body.indexedVariables
    )
    -- Add trait methods
    self.variables = VariableContainer.variables
    self.fetch_variables = VariableContainer.fetch_variables
  else
    self.variablesReference = 0
  end
end

---Get session (required by VariableContainer trait, if used)
---@return Session
function Output:_get_session()
  return self.session
end

---Fetch children (calls variables if has reference, otherwise no-op)
---@return View|{} variables View of child variables or empty table
function Output:children()
  if self.variablesReference and self.variablesReference > 0 and self.variables then
    return self:variables()
  end
  return {}
end

M.Output = Output

return M
