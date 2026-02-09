-- Tests for preLaunchTask with compound configurations
--
-- Test scenarios:
-- 1. Individual config with preLaunchTask
-- 2. Compound with individual preLaunchTasks (each config has its own)
-- 3. Compound-level preLaunchTask (runs once before all sessions)
-- 4. Both compound and individual preLaunchTasks
local harness = require("helpers.test_harness")

local T = harness.integration("prelaunch_tasks", function(T, ctx)

  -- Helper to set up task tracking
  local function setup_task_tracking(h, fixture_path)
    h.child.lua(string.format([[
      -- Change to fixture directory so overseer finds .vscode/tasks.json
      vim.fn.chdir(%q)

      vim.g.overseer_tasks_ran = {}

      local overseer = require("overseer")

      -- Hook into overseer to track task completion
      local original_run_task = overseer.run_task
      overseer.run_task = function(opts, callback)
        return original_run_task(opts, function(task, err)
          if task then
            task:subscribe("on_complete", function(_, status)
              local tasks = vim.g.overseer_tasks_ran or {}
              table.insert(tasks, { name = opts.name, status = status })
              vim.g.overseer_tasks_ran = tasks
            end)
          end
          if callback then
            callback(task, err)
          end
        end)
      end
    ]], fixture_path))
  end

  -- Helper to get tracked tasks
  local function get_ran_tasks(h)
    return h.child.lua_get([[vim.g.overseer_tasks_ran or {}]])
  end

  -- Helper to find task by name
  local function find_task(tasks, name)
    for _, task in ipairs(tasks) do
      if task.name == name then
        return task
      end
    end
    return nil
  end

  T["individual config preLaunchTask runs before session"] = function()
    local h = ctx.create()
    local fixture_path = h:fixture("multi-session")
    h:use_plugin("neodap.plugins.overseer")
    setup_task_tracking(h, fixture_path)

    h:cmd("DapLaunch Debug A with task")
    h:wait_url("/sessions")
    h:wait(500)

    local tasks = get_ran_tasks(h)
    print("=== Individual preLaunchTask ===")
    for _, task in ipairs(tasks) do
      print(string.format("  %s: %s", task.name, task.status))
    end

    MiniTest.expect.equality(#tasks >= 1, true, "Expected at least 1 task to run")
    local build_a = find_task(tasks, "build-a")
    MiniTest.expect.equality(build_a ~= nil, true, "Expected build-a task to run")
    MiniTest.expect.equality(build_a.status, "SUCCESS", "Expected build-a to succeed")
  end

  T["compound with individual preLaunchTasks runs each task"] = function()
    local h = ctx.create()
    local fixture_path = h:fixture("multi-session")
    h:use_plugin("neodap.plugins.overseer")
    setup_task_tracking(h, fixture_path)

    h:cmd("DapLaunch Both with individual tasks")
    h:wait(2000) -- Wait for both sessions to start

    local tasks = get_ran_tasks(h)
    print("=== Compound with individual preLaunchTasks ===")
    for _, task in ipairs(tasks) do
      print(string.format("  %s: %s", task.name, task.status))
    end

    -- Both build-a and build-b should have run
    MiniTest.expect.equality(#tasks >= 2, true, "Expected at least 2 tasks to run")
    local build_a = find_task(tasks, "build-a")
    local build_b = find_task(tasks, "build-b")
    MiniTest.expect.equality(build_a ~= nil, true, "Expected build-a task to run")
    MiniTest.expect.equality(build_b ~= nil, true, "Expected build-b task to run")
  end

  T["compound-level preLaunchTask runs once before all sessions"] = function()
    local h = ctx.create()
    local fixture_path = h:fixture("multi-session")
    h:use_plugin("neodap.plugins.overseer")
    setup_task_tracking(h, fixture_path)

    h:cmd("DapLaunch Both with compound task")
    h:wait(2000)

    local tasks = get_ran_tasks(h)
    print("=== Compound-level preLaunchTask ===")
    for _, task in ipairs(tasks) do
      print(string.format("  %s: %s", task.name, task.status))
    end

    -- build-all should have run exactly once
    local build_all_count = 0
    for _, task in ipairs(tasks) do
      if task.name == "build-all" then
        build_all_count = build_all_count + 1
      end
    end
    MiniTest.expect.equality(build_all_count, 1, "Expected build-all to run exactly once")

    -- Check sessions were created (js-debug may create child sessions, so >= 2)
    local session_count = h:query_count("/sessions")
    MiniTest.expect.equality(session_count >= 2, true, "Expected at least 2 debug sessions, got " .. session_count)
  end

  T["compound with both compound and individual preLaunchTasks"] = function()
    local h = ctx.create()
    local fixture_path = h:fixture("multi-session")
    h:use_plugin("neodap.plugins.overseer")
    setup_task_tracking(h, fixture_path)

    h:cmd("DapLaunch Both with all tasks")
    h:wait(2500)

    local tasks = get_ran_tasks(h)
    print("=== Both compound and individual preLaunchTasks ===")
    for _, task in ipairs(tasks) do
      print(string.format("  %s: %s", task.name, task.status))
    end

    -- build-all should run first (once), then build-a and build-b
    MiniTest.expect.equality(#tasks >= 3, true, "Expected at least 3 tasks to run")

    local build_all = find_task(tasks, "build-all")
    local build_a = find_task(tasks, "build-a")
    local build_b = find_task(tasks, "build-b")

    MiniTest.expect.equality(build_all ~= nil, true, "Expected build-all task to run")
    MiniTest.expect.equality(build_a ~= nil, true, "Expected build-a task to run")
    MiniTest.expect.equality(build_b ~= nil, true, "Expected build-b task to run")

    -- Check sessions were created (js-debug may create child sessions, so >= 2)
    local session_count = h:query_count("/sessions")
    MiniTest.expect.equality(session_count >= 2, true, "Expected at least 2 debug sessions, got " .. session_count)
  end

end)

return T
