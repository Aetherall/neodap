--- Test fixtures for DAP plugin tests
--- Provides adapter configurations for debuggers.
---@class tests.helpers.dap.fixtures
local M = {}

-- Per-process temp directory to avoid conflicts in parallel tests
-- Uses project-local .tests/ to avoid scanning /tmp which may have millions of files
local tmpdir = vim.fn.getcwd() .. "/.tests/neodap_test_" .. vim.fn.getpid()
vim.fn.mkdir(tmpdir, "p")

---Get the temp directory path
---@return string tmpdir
function M.get_tmpdir()
  return tmpdir
end

---Get debugpy adapter configuration
---@return table adapter Adapter configuration for debugpy
function M.debugpy_adapter()
  return {
    type = "stdio",
    command = "python3",
    args = { "-m", "debugpy.adapter" },
  }
end

---Get js-debug adapter configuration
---Uses type=server pattern - dap-lua handles spawning, ready detection, and cleanup
---@return table adapter Adapter configuration for js-debug
function M.jsdbg_adapter()
  return {
    type = "server",
    command = "js-debug",
    args = { "0" },  -- port 0 = auto-assign
    connect_condition = function(chunk)
      -- js-debug outputs "Debug server listening at ::1:PORT"
      -- Match port after last colon
      local port = chunk:match(":(%d+)%s*$")
      if port then
        return tonumber(port), "::1"
      end
      return nil
    end,
  }
end

---Create a launch configuration for Node.js
---@param opts { program: string, stopOnEntry?: boolean, name?: string }
---@return table config Launch configuration
function M.node_launch(opts)
  return {
    type = "pwa-node",
    request = "launch",
    name = opts.name or "Test",
    program = opts.program,
    stopOnEntry = opts.stopOnEntry or false,
    -- Enable source maps for virtual source testing
    sourceMaps = true,
    skipFiles = {},  -- Don't skip any files so we can see node internals
  }
end

return M
