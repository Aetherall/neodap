--- JS-debug test scenarios for DAP plugin tests
--- Provides high-level test scenarios for js-debug virtual source tests.
---
--- NOTE: js-debug uses a child session pattern:
--- 1. Connect to js-debug server (root session)
--- 2. Send launch request
--- 3. js-debug spawns actual debuggee and creates child session via startDebugging
--- 4. The child session is where actual debugging happens
---@class tests.helpers.dap.jsdbg
local M = {}

local H = require("helpers.dap")
local fixtures = require("helpers.dap.fixtures")

---@class JsdbgContext : SessionContext
---@field source? neodap.entities.Source
---@field thread? neodap.entities.Thread
---@field virtual_sources neodap.entities.Source[]
---@field root_session neodap.entities.Session
---@field child_session? neodap.entities.Session

---Start a js-debug session (handles child session pattern)
---@param opts { program: string, stopOnEntry?: boolean }
---@return JsdbgContext
function M.start_session(opts)
  local debugger, db = H.setup()

  -- Start root session
  local root_session = debugger:debug({
    adapter = fixtures.jsdbg_adapter(),
    config = fixtures.node_launch({
      program = opts.program,
      stopOnEntry = opts.stopOnEntry,
    }),
  })

  -- Wait for root session to be running
  H.wait_for(10000, function()
    return root_session.state:get() == "running"
  end)

  -- Wait for child session to be created (js-debug spawns it)
  -- Child sessions are now linked via parent.children, not debugger.sessions
  local child_session = nil
  H.wait_for(10000, function()
    child_session = H.edge_first(root_session.children)
    return child_session ~= nil
  end)

  -- Wait for child session to be stopped (if stopOnEntry or debugger statement)
  if child_session then
    H.wait_for(10000, function()
      local state = child_session.state:get()
      return state == "stopped" or state == "terminated"
    end)
  end

  return {
    session = child_session or root_session,  -- Use child session for debugging
    root_session = root_session,
    child_session = child_session,
    debugger = debugger,
    db = db,
  }
end

return M
