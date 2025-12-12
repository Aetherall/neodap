local harness = require("helpers.test_harness")

-- Neotest strategy tests only run with python adapter
local T = MiniTest.new_set()

local adapter = harness.for_adapter("python")

T["neotest_strategy"] = MiniTest.new_set({
  hooks = adapter.hooks,
})

-- User scenario: Strategy function can be loaded and configured
T["neotest_strategy"]["strategy loads and configures"] = function()
  local h = adapter.harness()

  -- Setup neotest with neodap strategy
  h:setup_neotest("python")
  h:wait(50)

  -- Verify strategy was registered
  local has_strategy = h:get("require('neotest.config').strategies.neodap ~= nil")
  MiniTest.expect.equality(has_strategy, true)
end

-- User scenario: Strategy creates debug session when called directly
T["neotest_strategy"]["direct strategy call creates session"] = function()
  local h = adapter.harness()
  local fixture_path = h:fixture("simple-vars")

  h:setup_neotest("python")

  -- Call strategy directly (simulating what neotest does)
  local main_path = fixture_path .. "/main.py"
  h.child.lua(string.format([[
    local spec = {
      strategy = {
        type = "python",
        request = "launch",
        program = %q,
        stopOnEntry = true,
      },
    }
    _G.test_process = _G.neotest_strategy_api.strategy(spec)
  ]], main_path))

  -- Wait for session
  h:wait_url("/sessions", harness.TIMEOUT.LONG)

  -- Verify session exists
  local state = h:query_field("@session", "state")
  MiniTest.expect.no_equality(state, nil)
end

-- User scenario: Process stop terminates session
T["neotest_strategy"]["process stop terminates session"] = function()
  local h = adapter.harness()
  local fixture_path = h:fixture("simple-vars")

  h:setup_neotest("python")

  local main_path = fixture_path .. "/main.py"
  h.child.lua(string.format([[
    local spec = {
      strategy = {
        type = "python",
        request = "launch",
        program = %q,
        stopOnEntry = true,
      },
    }
    _G.test_process = _G.neotest_strategy_api.strategy(spec)
  ]], main_path))

  h:wait_url("/sessions", harness.TIMEOUT.LONG)
  h:wait(100)

  -- Stop via process interface
  h.child.lua("_G.test_process:stop()")

  -- Wait for session to be terminated
  h:wait_field("/sessions[0]", "state", "terminated", harness.TIMEOUT.MEDIUM)
end

return T
