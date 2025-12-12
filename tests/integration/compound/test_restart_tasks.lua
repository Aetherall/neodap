-- Tests for compound restart with preLaunchTask re-execution
--
-- Gap #5: Compound restart with preLaunchTask
--
-- These tests verify:
-- 1. DapRestartConfig re-runs per-config preLaunchTask (via before_debug hook)
-- 2. Compound-level preLaunchTask does NOT re-run on restart
--    (Config:restart() calls debugger:debug() directly, bypassing start_sessions)

local MiniTest = require("mini.test")
local harness = require("helpers.test_harness")

return harness.integration("restart tasks", function(T, ctx)

  T["DapRestartConfig re-runs per-config preLaunchTask"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:setup_mock_task_runner()

    h:cmd("DapLaunch Both with individual tasks")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- Initial preLaunchTasks ran (build-a, build-b)
    local initial_log = h:get_task_log()
    MiniTest.expect.equality(#initial_log, 2)

    -- Focus a session to enable DapRestartConfig
    h:wait(500)
    h:cmd("DapFocus /sessions(state=stopped)[0]/threads/stacks[0]/frames[0]")
    h:wait_url("@session", harness.TIMEOUT.SHORT)

    -- Restart the config
    h:cmd("DapRestartConfig")

    -- Wait for new sessions
    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.EXTENDED)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.EXTENDED)

    -- preLaunchTasks should have run again (total: 4 = 2 initial + 2 restart)
    h:wait_task_log(4, harness.TIMEOUT.MEDIUM)

    local final_log = h:get_task_log()
    MiniTest.expect.equality(#final_log, 4)

    -- Count occurrences
    local counts = {}
    for _, name in ipairs(final_log) do
      counts[name] = (counts[name] or 0) + 1
    end
    MiniTest.expect.equality(counts["build-a"], 2)
    MiniTest.expect.equality(counts["build-b"], 2)
  end

  T["compound-level preLaunchTask does NOT re-run on restart"] = function()
    -- Config:restart() calls debugger:debug() directly for each stored
    -- specification, bypassing api.start_sessions() in rooter.lua.
    -- Therefore the compound-level preLaunchTask is not re-executed.
    local h = ctx.create()
    h:fixture("multi-session")
    h:setup_mock_task_runner()

    h:cmd("DapLaunch Both with compound task")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- Initial compound preLaunchTask ran once
    local initial_log = h:get_task_log()
    MiniTest.expect.equality(#initial_log, 1)
    MiniTest.expect.equality(initial_log[1], "build-all")

    -- Focus and restart
    h:wait(500)
    h:cmd("DapFocus /sessions(state=stopped)[0]/threads/stacks[0]/frames[0]")
    h:wait_url("@session", harness.TIMEOUT.SHORT)

    h:cmd("DapRestartConfig")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.EXTENDED)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.EXTENDED)

    -- Only the initial compound preLaunchTask should exist (not re-run)
    local final_log = h:get_task_log()
    MiniTest.expect.equality(#final_log, 1)
    MiniTest.expect.equality(final_log[1], "build-all")
  end

end)
