-- Output entity DAP methods
local entities = require("neodap.entities")
local context = require("neodap.plugins.dap.context")
local utils = require("neodap.plugins.dap.utils")
local a = require("neodap.async")

local Output = entities.Output

local get_dap_session = context.get_dap_session

---Get the DAP session for this output (Output → Session → DapSession)
---@return DapSession? dap_session, neodap.entities.Session? session
function Output:dapSession()
  local session = self.session:get()
  if not session then return nil, nil end
  return get_dap_session(session), session
end

---Fetch child variables for structured output
---@param self neodap.entities.Output
function Output:fetchChildren()
  utils.fetch_variables(self, self.children, "fetchChildren")
end

Output.fetchChildren = a.memoize(Output.fetchChildren)

return Output
