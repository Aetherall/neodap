-- Tests for preLaunchTask failure dialog in compound context
--
-- Gap #4: preLaunchTask failure dialog in compound context
--
-- When a compound preLaunchTask fails, the user is presented with a
-- vim.ui.select dialog offering "Launch anyway" or "Cancel". These tests
-- verify that dialog flow using mock task runner + vim.ui.select mock.

local MiniTest = require("mini.test")
local harness = require("helpers.test_harness")

return harness.integration("prelaunch failure", function(T, ctx)

  T["successful compound preLaunchTask proceeds to launch"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:setup_mock_task_runner()  -- all tasks succeed by default

    h:cmd("DapLaunch Both with compound task")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    MiniTest.expect.equality(h:query_count("/configs"), 1)
    MiniTest.expect.equality(h:query_field("/configs[0]", "state"), "active")

    -- Task ran
    local log = h:get_task_log()
    MiniTest.expect.equality(#log, 1)
    MiniTest.expect.equality(log[1], "build-all")

    -- No dialog shown (task succeeded)
    MiniTest.expect.equality(#h:get_ui_select_log(), 0)
  end

  T["failed compound preLaunchTask shows dialog"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:setup_mock_task_runner({ failing_tasks = { ["build-all"] = true } })
    h:setup_ui_select_mock("Cancel")

    h:cmd("DapLaunch Both with compound task")

    -- Wait for the dialog to fire
    h:wait(1000)

    -- Dialog should have been shown
    local ui_log = h:get_ui_select_log()
    MiniTest.expect.equality(#ui_log >= 1, true)
    MiniTest.expect.equality(ui_log[1].items[1], "Launch anyway")
    MiniTest.expect.equality(ui_log[1].items[2], "Cancel")

    -- Task was attempted
    local task_log = h:get_task_log()
    MiniTest.expect.equality(#task_log, 1)
    MiniTest.expect.equality(task_log[1], "build-all")
  end

  T["Cancel aborts compound launch after failure"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:setup_mock_task_runner({ failing_tasks = { ["build-all"] = true } })
    h:setup_ui_select_mock("Cancel")

    h:cmd("DapLaunch Both with compound task")

    -- Wait for the dialog + cancellation
    h:wait(1500)

    -- No sessions should have been created
    MiniTest.expect.equality(h:query_count("/sessions"), 0)
  end

  T["Launch anyway proceeds despite failure"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:setup_mock_task_runner({ failing_tasks = { ["build-all"] = true } })
    h:setup_ui_select_mock("Launch anyway")

    h:cmd("DapLaunch Both with compound task")

    -- Sessions should still be created despite task failure
    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    MiniTest.expect.equality(h:query_count("/configs"), 1)
    MiniTest.expect.equality(h:query_field("/configs[0]", "state"), "active")

    -- Dialog was shown
    local ui_log = h:get_ui_select_log()
    MiniTest.expect.equality(#ui_log >= 1, true)
  end

end)
