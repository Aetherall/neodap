-- E2E tests for neodap neotest strategy with Jest
-- Tests the full neotest -> neodap integration using neotest-jest adapter
--
-- NOTE: These E2E tests spawn npm/jest/js-debug processes.
-- Run with: make test-file FILE=test_neotest_jest
local harness = require("helpers.test_harness")

-- Skip if js-debug not available
if vim.fn.executable("js-debug") ~= 1 then
  return MiniTest.new_set()
end

local T = MiniTest.new_set()
local js = harness.for_adapter("javascript")

T["neotest_jest"] = MiniTest.new_set({
  hooks = js.hooks,
})

-- Setup neotest with jest adapter and neodap strategy (polyfill mode)
local function setup_neotest(h, fixture_path)
  h.child.lua(string.format([[
    -- Disable neotest subprocess for faster test execution
    local lib = require("neotest.lib")
    lib.subprocess.enabled = function() return false end
    lib.subprocess.init = function() end

    -- Install neodap as neotest's "dap" strategy polyfill
    -- Adapters are already configured in neodap.setup() by the test harness
    require("neodap").use(require("neodap.plugins.neotest_strategy"), { polyfill = true })

    -- Configure neotest with jest adapter
    require("neotest").setup({
      adapters = {
        require("neotest-jest")({
          jestCommand = "npx jest",
          cwd = function() return %q end,
        }),
      },
      discovery = { enabled = false },
    })
  ]], fixture_path))
end

-- E2E: neotest.run.run() with neodap strategy creates debug session
T["neotest_jest"]["neotest.run.run creates debug session"] = function()
  local h = js.harness()
  local fixture_path = h:fixture("jest-project")
  local test_file = fixture_path .. "/sum.test.js"
  h:ensure_npm_deps()

  setup_neotest(h, fixture_path)

  -- Open test file and run with neodap strategy function
  h:cmd("edit " .. test_file)
  h.child.lua([[
    require("neotest").run.run({ vim.fn.expand("%"), strategy = "dap" })
  ]])

  -- Wait for debug session to start
  h:wait_url("/sessions", harness.TIMEOUT.MEDIUM)

  -- Verify session exists
  local state = h:query_field("/sessions[0]", "state")
  MiniTest.expect.no_equality(state, nil)

  -- Cleanup
  h:query_call("/sessions[0]", "terminate")
  h:wait_field("/sessions[0]", "state", "terminated", harness.TIMEOUT.MEDIUM)
end

-- E2E: Debug session stops at debugger statement in test
T["neotest_jest"]["stops at debugger statement"] = function()
  local h = js.harness()
  local fixture_path = h:fixture("jest-project")
  local test_file = fixture_path .. "/sum.test.js"
  h:ensure_npm_deps()

  setup_neotest(h, fixture_path)

  -- Open test file and run with neodap strategy
  h:cmd("edit " .. test_file)
  h.child.lua([[
    require("neotest").run.run({ vim.fn.expand("%"), strategy = "dap" })
  ]])

  -- Wait for stopped session (debugger statement hit)
  h:wait_url("/sessions(state=stopped)", harness.TIMEOUT.MEDIUM)

  -- Cleanup
  h:query_call("/sessions[0]", "terminate")
  h:wait_field("/sessions[0]", "state", "terminated", harness.TIMEOUT.MEDIUM)
end

-- E2E: Session terminates cleanly
T["neotest_jest"]["session terminates cleanly"] = function()
  local h = js.harness()
  local fixture_path = h:fixture("jest-project")
  local test_file = fixture_path .. "/sum.test.js"
  h:ensure_npm_deps()

  setup_neotest(h, fixture_path)

  -- Open test file and run with neodap strategy
  h:cmd("edit " .. test_file)
  h.child.lua([[
    require("neotest").run.run({ vim.fn.expand("%"), strategy = "dap" })
  ]])

  -- Wait for stopped session
  h:wait_url("/sessions(state=stopped)", harness.TIMEOUT.MEDIUM)

  -- Terminate and verify clean shutdown
  h:query_call("/sessions[0]", "terminate")
  h:wait_field("/sessions[0]", "state", "terminated", harness.TIMEOUT.MEDIUM)
end

-- E2E: Run single test at cursor
T["neotest_jest"]["run nearest test at cursor"] = function()
  local h = js.harness()
  local fixture_path = h:fixture("jest-project")
  local test_file = fixture_path .. "/sum.test.js"
  h:ensure_npm_deps()

  setup_neotest(h, fixture_path)

  -- Open test file and position cursor on first test (line 4)
  h:cmd("edit " .. test_file)
  h:cmd("4")

  -- Run nearest test with neodap strategy
  h.child.lua([[
    require("neotest").run.run({ strategy = "dap" })
  ]])

  -- Wait for stopped session (debugger statement hit)
  h:wait_url("/sessions(state=stopped)", harness.TIMEOUT.MEDIUM)

  -- Cleanup
  h:query_call("/sessions[0]", "terminate")
  h:wait_field("/sessions[0]", "state", "terminated", harness.TIMEOUT.MEDIUM)
end

-- E2E: Breakpoints are bound when session starts
T["neotest_jest"]["breakpoints bound on session start"] = function()
  local h = js.harness()
  local fixture_path = h:fixture("jest-project")
  local test_file = fixture_path .. "/sum.test.js"
  local source_file = fixture_path .. "/sum.js"
  h:ensure_npm_deps()
  h:use_plugin("neodap.plugins.breakpoint_cmd")

  setup_neotest(h, fixture_path)

  -- Set breakpoint before starting debug session
  h:cmd("edit " .. source_file)
  h:cmd("DapBreakpoint 2")
  MiniTest.expect.equality(h:query_count("/breakpoints"), 1)

  -- Start debug session
  h:cmd("edit " .. test_file)
  h.child.lua([[
    require("neotest").run.run({ vim.fn.expand("%"), strategy = "dap" })
  ]])

  -- Wait for session to stop (at debugger statement)
  h:wait_url("/sessions(state=stopped)", harness.TIMEOUT.MEDIUM)

  -- Verify breakpoint has at least one binding (may have multiple from jest running multiple tests)
  local binding_count = h:query_count("/breakpoints[0]/bindings")
  MiniTest.expect.no_equality(binding_count, 0)

  -- Cleanup
  h:query_call("/sessions[0]", "terminate")
  h:wait_field("/sessions[0]", "state", "terminated", harness.TIMEOUT.MEDIUM)
end

return T
