-- Tests for overseer plugin (preLaunchTask / postDebugTask)
local harness = require("helpers.test_harness")

local T = harness.integration("overseer", function(T, ctx)

  -- Helper to set up task tracking (tasks are defined in .vscode/tasks.json)
  -- Also changes cwd to fixture directory so overseer can find tasks.json
  local function setup_test_tasks(h, fixture_path)
    h.child.lua(string.format([[
      -- Change to fixture directory so overseer finds .vscode/tasks.json
      vim.fn.chdir(%q)

      vim.g.overseer_task_ran = {}

      local overseer = require("overseer")

      -- Hook into overseer to track task completion
      local original_run_task = overseer.run_task
      overseer.run_task = function(opts, callback)
        return original_run_task(opts, function(task, err)
          if task then
            task:subscribe("on_complete", function(_, status)
              -- vim.g tables are copies, not references, so we must re-assign
              local tasks = vim.g.overseer_task_ran or {}
              table.insert(tasks, { name = opts.name, status = status })
              vim.g.overseer_task_ran = tasks
            end)
          end
          if callback then
            callback(task, err)
          end
        end)
      end
    ]], fixture_path))
  end

  T["preLaunchTask runs before debug session starts"] = function()
    local h = ctx.create()
    local fixture_path = h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.overseer")
    setup_test_tasks(h, fixture_path)

    -- Launch with preLaunchTask config from launch.json
    h:cmd("DapLaunch Debug with preLaunchTask")

    -- Wait for session to be created
    h:wait_url("/sessions")
    h:wait(500) -- Give time for task tracking

    -- Check that task ran
    local tasks_ran = h.child.lua_get([[vim.g.overseer_task_ran]])
    MiniTest.expect.equality(#tasks_ran >= 1, true)
    MiniTest.expect.equality(tasks_ran[1].name, "test-build")
    MiniTest.expect.equality(tasks_ran[1].status, "SUCCESS")
  end

  T["postDebugTask runs after session terminates"] = function()
    local h = ctx.create()
    local fixture_path = h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.overseer")
    setup_test_tasks(h, fixture_path)

    -- Launch with postDebugTask config from launch.json
    h:cmd("DapLaunch Debug with postDebugTask")

    -- Wait for session
    h:wait_url("/sessions")
    h:wait(300)

    -- Task should NOT have run yet
    local tasks_before = h.child.lua_get([[vim.g.overseer_task_ran]])
    MiniTest.expect.equality(#tasks_before, 0)

    -- Terminate the session using harness method (more reliable for tests)
    h:terminate_root_session()
    h:wait(1000) -- Give time for postDebugTask to run

    -- Now task should have run
    local tasks_after = h.child.lua_get([[vim.g.overseer_task_ran]])
    MiniTest.expect.equality(#tasks_after >= 1, true)
    MiniTest.expect.equality(tasks_after[1].name, "test-cleanup")
  end

  T["failed preLaunchTask aborts debug launch"] = function()
    local h = ctx.create()
    local fixture_path = h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.overseer")
    setup_test_tasks(h, fixture_path)

    -- Launch with failing preLaunchTask config from launch.json
    h:cmd("DapLaunch Debug with failing task")

    -- Wait for task to fail
    h:wait(1500)

    -- Check task ran and failed
    local tasks_ran = h.child.lua_get([[vim.g.overseer_task_ran]])
    MiniTest.expect.equality(#tasks_ran >= 1, true)
    MiniTest.expect.equality(tasks_ran[1].status, "FAILURE")

    -- Check that no session was created (debug was aborted)
    MiniTest.expect.equality(h:query_count("/sessions"), 0)
  end

  T["both preLaunchTask and postDebugTask work together"] = function()
    local h = ctx.create()
    local fixture_path = h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.overseer")
    setup_test_tasks(h, fixture_path)

    -- Launch with both tasks config from launch.json
    h:cmd("DapLaunch Debug with both tasks")

    -- Wait for session
    h:wait_url("/sessions")
    h:wait(500)

    -- Only pre-task should have run
    local tasks_mid = h.child.lua_get([[vim.g.overseer_task_ran]])
    MiniTest.expect.equality(#tasks_mid, 1)
    MiniTest.expect.equality(tasks_mid[1].name, "test-build")

    -- Terminate the session using harness method (more reliable for tests)
    h:terminate_root_session()
    h:wait(1000) -- Give time for postDebugTask to run

    -- Both tasks should have run
    local tasks_final = h.child.lua_get([[vim.g.overseer_task_ran]])
    MiniTest.expect.equality(#tasks_final, 2)
    MiniTest.expect.equality(tasks_final[2].name, "test-cleanup")
  end

end)

return T
