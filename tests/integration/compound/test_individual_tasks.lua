-- Tests for per-config postDebugTask within compounds
--
-- Gap #6: Per-config postDebugTask in compounds + server adapter fix
--
-- These tests verify:
-- 1. Per-config postDebugTask fires on session termination
-- 2. Per-config postDebugTask fires independently per session
-- 3. Per-config preLaunchTask runs for each compound member
-- 4. Server adapter postDebugTask works (was broken with old monkey-patch)
-- 5. Both compound-level and per-config tasks work together

local MiniTest = require("mini.test")
local harness = require("helpers.test_harness")

return harness.integration("individual tasks", function(T, ctx)

  T["per-config postDebugTask fires on session termination"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:setup_mock_task_runner()

    h:cmd("DapLaunch Both with individual post tasks")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- No tasks yet (postDebugTask fires on termination)
    MiniTest.expect.equality(#h:get_task_log(), 0)

    -- Terminate first session
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")
    h:wait_url("/sessions(state=terminated)[0]", harness.TIMEOUT.LONG)

    -- Wait for task to fire
    h:wait_task_log(1, harness.TIMEOUT.SHORT)

    -- One postDebugTask should have fired
    local log = h:get_task_log()
    MiniTest.expect.equality(#log, 1)
    -- Should be either build-a or build-b (depends on which session was [0])
    local valid = log[1] == "build-a" or log[1] == "build-b"
    MiniTest.expect.equality(valid, true)
  end

  T["per-config postDebugTask fires independently per session"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:setup_mock_task_runner()

    h:cmd("DapLaunch Both with individual post tasks")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- Terminate first
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")
    h:wait_url("/sessions(state=terminated)[0]", harness.TIMEOUT.LONG)
    h:wait_task_log(1, harness.TIMEOUT.SHORT)

    -- Terminate second
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")
    h:wait_field("/configs[0]", "state", "terminated", harness.TIMEOUT.LONG)
    h:wait_task_log(2, harness.TIMEOUT.SHORT)

    -- Both postDebugTasks should have fired
    local log = h:get_task_log()
    MiniTest.expect.equality(#log, 2)

    -- Both build-a and build-b should be present (in any order)
    local tasks = {}
    for _, name in ipairs(log) do tasks[name] = true end
    MiniTest.expect.equality(tasks["build-a"] == true, true)
    MiniTest.expect.equality(tasks["build-b"] == true, true)
  end

  T["per-config preLaunchTask runs for each compound member"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:setup_mock_task_runner()

    h:cmd("DapLaunch Both with individual tasks")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- Both per-config preLaunchTasks should have run
    local log = h:get_task_log()
    MiniTest.expect.equality(#log, 2)

    local tasks = {}
    for _, name in ipairs(log) do tasks[name] = true end
    MiniTest.expect.equality(tasks["build-a"] == true, true)
    MiniTest.expect.equality(tasks["build-b"] == true, true)
  end

  T["both compound-level and per-config tasks work together"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:setup_mock_task_runner()

    h:cmd("DapLaunch Both with compound and individual tasks")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- Compound preLaunchTask + 2 per-config preLaunchTasks = 3 tasks
    local log = h:get_task_log()
    MiniTest.expect.equality(#log, 3)
    -- First should be compound task (runs before individual ones)
    MiniTest.expect.equality(log[1], "build-all")

    -- The rest should be per-config tasks
    local individual = {}
    for i = 2, #log do individual[log[i]] = true end
    MiniTest.expect.equality(individual["build-a"] == true, true)
    MiniTest.expect.equality(individual["build-b"] == true, true)

    -- Now terminate all and check postDebugTasks fire
    h:clear_task_log()

    h:wait(500)
    h:cmd("DapFocus /sessions(state=stopped)[0]/threads/stacks[0]/frames[0]")
    h:wait_url("@session", harness.TIMEOUT.SHORT)
    h:cmd("DapTerminateConfig")

    h:wait_field("/configs[0]", "state", "terminated", harness.TIMEOUT.LONG)

    -- Wait for post-debug tasks: 2 per-config + 1 compound = 3
    h:wait_task_log(3, harness.TIMEOUT.MEDIUM)

    local post_log = h:get_task_log()
    MiniTest.expect.equality(#post_log, 3)

    -- Should have both per-config and compound postDebugTasks
    local post_tasks = {}
    for _, name in ipairs(post_log) do
      post_tasks[name] = (post_tasks[name] or 0) + 1
    end
    MiniTest.expect.equality(post_tasks["build-a"] == 1, true)
    MiniTest.expect.equality(post_tasks["build-b"] == 1, true)
    MiniTest.expect.equality(post_tasks["build-all"] == 1, true)
  end

  T["server adapter postDebugTask works via on_session hook"] = function()
    -- This test explicitly verifies the server adapter fix.
    -- Previously, debug() returned nil for server adapters so the
    -- old overseer monkey-patch's session.state:use() never attached.
    -- The new on_session hook fires inside onSessionCreated for ALL adapters.
    if ctx.adapter_name ~= "javascript" then return end

    local h = ctx.create()
    h:fixture("multi-session")
    h:setup_mock_task_runner()

    -- Launch a single config with postDebugTask using a server adapter
    h:cmd("DapLaunch Debug A with post task")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- No tasks yet
    MiniTest.expect.equality(#h:get_task_log(), 0)

    -- Terminate the session
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")
    h:wait_url("/sessions(state=terminated)[0]", harness.TIMEOUT.LONG)

    -- postDebugTask should fire even for server adapter
    h:wait_task_log(1, harness.TIMEOUT.MEDIUM)

    local log = h:get_task_log()
    MiniTest.expect.equality(#log, 1)
    MiniTest.expect.equality(log[1], "build-a")
  end

end)
