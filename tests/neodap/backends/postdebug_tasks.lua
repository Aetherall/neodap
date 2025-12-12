-- Tests for postDebugTask with real overseer backend
--
-- Covers compound and per-config postDebugTask execution, including
-- the server adapter fix (on_session hook fires for all adapter types).
local harness = require("helpers.test_harness")

local T = harness.integration("postdebug_tasks", function(T, ctx)

  -- Reuse the same task-tracking monkey-patch as prelaunch_tasks.lua
  local function setup_task_tracking(h, fixture_path)
    h.child.lua(string.format([[
      vim.fn.chdir(%q)

      vim.g.overseer_tasks_ran = {}

      local overseer = require("overseer")

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

  local function get_ran_tasks(h)
    return h.child.lua_get([[vim.g.overseer_tasks_ran or {}]])
  end

  local function wait_for_tasks(h, count, timeout)
    timeout = timeout or 5000
    h.child.lua(string.format([[
      vim.wait(%d, function()
        return #(vim.g.overseer_tasks_ran or {}) >= %d
      end, 50)
    ]], timeout, count))
  end

  local function find_task(tasks, name)
    for _, task in ipairs(tasks) do
      if task.name == name then
        return task
      end
    end
    return nil
  end

  T["compound postDebugTask fires when Config terminates"] = function()
    local h = ctx.create()
    local fixture_path = h:fixture("multi-session")
    h:use_plugin("neodap.plugins.overseer")
    setup_task_tracking(h, fixture_path)

    h:cmd("DapLaunch Both with compound post task")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- No tasks should have run yet
    MiniTest.expect.equality(#get_ran_tasks(h), 0)

    -- Terminate the Config
    h:wait(500)
    h:cmd("DapFocus /sessions(state=stopped)[0]/threads/stacks[0]/frames[0]")
    h:wait_url("@session", harness.TIMEOUT.SHORT)
    h:cmd("DapTerminateConfig")

    h:wait_field("/configs[0]", "state", "terminated", harness.TIMEOUT.LONG)
    wait_for_tasks(h, 1)

    local tasks = get_ran_tasks(h)
    MiniTest.expect.equality(#tasks >= 1, true)
    local build_all = find_task(tasks, "build-all")
    MiniTest.expect.equality(build_all ~= nil, true, "Expected build-all postDebugTask to run")
    MiniTest.expect.equality(build_all.status, "SUCCESS")
  end

  T["compound postDebugTask does NOT fire while sessions active"] = function()
    local h = ctx.create()
    local fixture_path = h:fixture("multi-session")
    h:use_plugin("neodap.plugins.overseer")
    setup_task_tracking(h, fixture_path)

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
    MiniTest.expect.equality(#get_ran_tasks(h), 0)
  end

  T["per-config postDebugTask fires on session termination"] = function()
    local h = ctx.create()
    local fixture_path = h:fixture("multi-session")
    h:use_plugin("neodap.plugins.overseer")
    setup_task_tracking(h, fixture_path)

    h:cmd("DapLaunch Both with individual post tasks")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- No tasks yet
    MiniTest.expect.equality(#get_ran_tasks(h), 0)

    -- Terminate first session
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")
    h:wait_url("/sessions(state=terminated)[0]", harness.TIMEOUT.LONG)

    wait_for_tasks(h, 1)

    local tasks = get_ran_tasks(h)
    MiniTest.expect.equality(#tasks >= 1, true, "Expected at least 1 postDebugTask to run")
    -- Should be either build-a or build-b
    local valid = tasks[1].name == "build-a" or tasks[1].name == "build-b"
    MiniTest.expect.equality(valid, true, "Expected build-a or build-b, got " .. tasks[1].name)
    MiniTest.expect.equality(tasks[1].status, "SUCCESS")
  end

  T["per-config postDebugTask fires independently per session"] = function()
    local h = ctx.create()
    local fixture_path = h:fixture("multi-session")
    h:use_plugin("neodap.plugins.overseer")
    setup_task_tracking(h, fixture_path)

    h:cmd("DapLaunch Both with individual post tasks")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- Terminate first
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")
    h:wait_url("/sessions(state=terminated)[0]", harness.TIMEOUT.LONG)
    wait_for_tasks(h, 1)

    -- Terminate second
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")
    h:wait_field("/configs[0]", "state", "terminated", harness.TIMEOUT.LONG)
    wait_for_tasks(h, 2)

    local tasks = get_ran_tasks(h)
    MiniTest.expect.equality(#tasks >= 2, true, "Expected at least 2 postDebugTasks to run")

    local build_a = find_task(tasks, "build-a")
    local build_b = find_task(tasks, "build-b")
    MiniTest.expect.equality(build_a ~= nil, true, "Expected build-a postDebugTask")
    MiniTest.expect.equality(build_b ~= nil, true, "Expected build-b postDebugTask")
  end

  T["server adapter postDebugTask works via on_session hook"] = function()
    -- This test verifies the server adapter fix: the old overseer monkey-patch
    -- couldn't attach a postDebugTask listener for server adapters because
    -- debug() returned nil. The new on_session lifecycle hook fires inside
    -- onSessionCreated for ALL adapter types.
    if ctx.adapter_name ~= "javascript" then return end

    local h = ctx.create()
    local fixture_path = h:fixture("multi-session")
    h:use_plugin("neodap.plugins.overseer")
    setup_task_tracking(h, fixture_path)

    h:cmd("DapLaunch Debug A with post task")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- No tasks yet
    MiniTest.expect.equality(#get_ran_tasks(h), 0)

    -- Terminate the session
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")
    h:wait_url("/sessions(state=terminated)[0]", harness.TIMEOUT.LONG)

    wait_for_tasks(h, 1, 7000)

    local tasks = get_ran_tasks(h)
    MiniTest.expect.equality(#tasks >= 1, true, "Expected postDebugTask for server adapter")
    MiniTest.expect.equality(tasks[1].name, "build-a")
    MiniTest.expect.equality(tasks[1].status, "SUCCESS")
  end

end)

return T
