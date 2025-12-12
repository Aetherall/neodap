--- Common test utilities for DAP plugin tests
--- This module provides shared setup and utility functions.
---@class tests.helpers.dap
local M = {}

---Wait for a condition with timeout
---@param timeout number Timeout in milliseconds
---@param condition fun(): boolean Condition to wait for
---@return boolean success Whether condition was met
function M.wait_for(timeout, condition)
  vim.wait(timeout, condition, 10)
  return condition()
end

---Setup neodap with the dap plugin loaded
---@return neodap.entities.Debugger debugger
---@return table graph
function M.setup()
  local neodap = require("neodap")
  neodap.setup()
  neodap.use(require("neodap.plugins.dap"))
  return neodap.debugger, neodap.graph
end

---Get the first entity from an edge collection or reference rollup
---@param edge_or_ref any Edge collection (has :iter()) or reference rollup (has :get())
---@return any? First entity or nil
function M.edge_first(edge_or_ref)
  if not edge_or_ref then return nil end
  -- Check if it's an edge (has :iter())
  if type(edge_or_ref.iter) == "function" then
    for entity in edge_or_ref:iter() do
      return entity
    end
    return nil
  end
  -- Check if it's a reference rollup (has :get())
  if type(edge_or_ref.get) == "function" then
    return edge_or_ref:get()
  end
  return nil
end

return M
