-- Tests for compound-level preLaunchTask and postDebugTask
--
-- Gap #2: Compound-level postDebugTask (production code exists, no verification)
--
-- These tests verify:
-- 1. Compound postDebugTask fires when Config terminates
-- 2. Compound postDebugTask does NOT fire while any session is active
-- 3. Compound postDebugTask fires exactly once
-- 4. Compound preLaunchTask runs before sessions start
-- 5. Noop: compound proceeds without errors when no runner registered

local MiniTest = require("mini.test")
local harness = require("helpers.test_harness")

return harness.integration("compound tasks", function(T, ctx)

  T["compound postDebugTask fires when Config terminates"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:setup_mock_task_runner()

    h:cmd("DapLaunch Both with compound post task")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- No tasks should have fired yet (postDebugTask only fires on termination)
    MiniTest.expect.equality(#h:get_task_log(), 0)

    -- Terminate all sessions via DapTerminateConfig
    h:wait(500)
    h:cmd("DapFocus /sessions(state=stopped)[0]/threads/stacks[0]/frames[0]")
    h:wait_url("@session", harness.TIMEOUT.SHORT)
    h:cmd("DapTerminateConfig")

    h:wait_field("/configs[0]", "state", "terminated", harness.TIMEOUT.LONG)
    h:wait_task_log(1, harness.TIMEOUT.SHORT)

    local log = h:get_task_log()
    MiniTest.expect.equality(#log, 1)
    MiniTest.expect.equality(log[1], "build-all")
  end

  T["compound postDebugTask does NOT fire while sessions active"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:setup_mock_task_runner()

    h:cmd("DapLaunch Both with compound post task")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- Terminate only one session
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")
    h:wait_url("/sessions(state=terminated)[0]", harness.TIMEOUT.LONG)

    -- Config should still be active
    MiniTest.expect.equality(h:query_field("/configs[0]", "state"), "active")

    -- postDebugTask should NOT have fired
    h:wait(500)
    MiniTest.expect.equality(#h:get_task_log(), 0)
  end

  T["compound postDebugTask fires exactly once"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:setup_mock_task_runner()

    h:cmd("DapLaunch Both with compound post task")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- Terminate first session
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")
    h:wait_url("/sessions(state=terminated)[0]", harness.TIMEOUT.LONG)

    -- Terminate second session
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")
    h:wait_field("/configs[0]", "state", "terminated", harness.TIMEOUT.LONG)

    h:wait_task_log(1, harness.TIMEOUT.SHORT)

    -- Should fire exactly once, not once per session
    local log = h:get_task_log()
    MiniTest.expect.equality(#log, 1)
    MiniTest.expect.equality(log[1], "build-all")
  end

  T["compound preLaunchTask runs before sessions start"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:setup_mock_task_runner()

    h:cmd("DapLaunch Both with compound task")

    -- Wait for sessions to be created
    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- preLaunchTask should have run
    local log = h:get_task_log()
    MiniTest.expect.equality(#log, 1)
    MiniTest.expect.equality(log[1], "build-all")

    -- Sessions should exist
    local session_count = h:query_count("/sessions")
    MiniTest.expect.equality(session_count >= 2, true)
  end

  T["noop: compound proceeds without errors when no runner registered"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    -- Do NOT register mock task runner -- use the noop default

    h:cmd("DapLaunch Both with compound task")

    -- Sessions should still be created (noop runner returns true)
    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    MiniTest.expect.equality(h:query_count("/configs"), 1)
    MiniTest.expect.equality(h:query_field("/configs[0]", "state"), "active")
  end

end)
