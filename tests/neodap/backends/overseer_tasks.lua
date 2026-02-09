-- Tests for overseer backend task hierarchy
--
-- With the 2-layer model:
-- - OverseerRun creates ONE task per debug session
-- - DapLaunch doesn't create Overseer tasks (just process management)
-- - Compound debugging would have parent + child session tasks
local harness = require("helpers.test_harness")

local T = harness.integration("overseer_tasks", function(T, ctx)

  -- Helper to get all overseer tasks
  local function get_tasks(h)
    return h.child.lua_get([[(function()
      local tasks = {}
      for _, task in ipairs(require("overseer").list_tasks({ unique = false })) do
        table.insert(tasks, {
          id = task.id,
          name = task.name,
          status = task.status,
          parent_id = task.parent_id,
        })
      end
      return tasks
    end)()]])
  end

  -- Helper to count tasks by status
  local function count_by_status(tasks, status)
    local count = 0
    for _, task in ipairs(tasks) do
      if task.status == status then
        count = count + 1
      end
    end
    return count
  end

  T["OverseerRun creates single debug session task"] = function()
    local h = ctx.create()
    local fixture_path = h:fixture("simple-vars")

    h.child.lua(string.format([[vim.fn.chdir(%q)]], fixture_path))
    h.child.lua([[require("overseer").run_template({ name = "Debug: Debug stop" })]])

    h:wait_url("/sessions")
    h:wait(500)

    local tasks = get_tasks(h)

    -- Print task info
    print("=== OverseerRun Tasks: " .. #tasks .. " ===")
    for _, task in ipairs(tasks) do
      print(string.format("  id=%d name=%s status=%s parent_id=%s",
        task.id, task.name, task.status, tostring(task.parent_id)))
    end

    -- Should have exactly 1 running task (the debug session)
    local running = count_by_status(tasks, "RUNNING")
    MiniTest.expect.equality(running, 1, "Expected 1 running task, got " .. running)
  end

  T["terminating session completes the task"] = function()
    local h = ctx.create()
    local fixture_path = h:fixture("simple-vars")

    h.child.lua(string.format([[vim.fn.chdir(%q)]], fixture_path))
    h.child.lua([[require("overseer").run_template({ name = "Debug: Debug stop" })]])

    h:wait_url("/sessions")
    h:wait(500)

    h:terminate_root_session()
    h:wait(1000)

    local tasks = get_tasks(h)
    local running = count_by_status(tasks, "RUNNING")

    MiniTest.expect.equality(running, 0, "Expected 0 running tasks after terminate, got " .. running)
  end

  T["DapLaunch creates Overseer task with overseer backend"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions")
    h:wait(500)

    local tasks = get_tasks(h)

    -- Print task info
    print("=== DapLaunch Tasks: " .. #tasks .. " ===")
    for _, task in ipairs(tasks) do
      print(string.format("  id=%d name=%s status=%s parent_id=%s",
        task.id, task.name, task.status, tostring(task.parent_id)))
    end

    -- DapLaunch with overseer backend creates 1 Overseer task for visibility
    local running = count_by_status(tasks, "RUNNING")
    MiniTest.expect.equality(running, 1, "Expected 1 running task, got " .. running)
  end

end)

return T
