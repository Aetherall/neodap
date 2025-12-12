-- Tests for compound configuration task hierarchy
--
-- With the 2-layer model:
-- - Compound creates parent orchestrator task + child debug session tasks
-- - Each child debug session is ONE Overseer task
-- - DapLaunch compound creates multiple debug session tasks (no orchestrator)
--
-- NOTE: Overseer backend is not yet implemented. These tests are skipped until
-- the overseer backend module and templates are created.
local harness = require("helpers.test_harness")

local T = harness.integration("compound_tasks", function(T, ctx)

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

  -- Helper to find tasks by name pattern
  local function find_tasks_by_name(tasks, pattern)
    local matches = {}
    for _, task in ipairs(tasks) do
      if task.name:find(pattern) then
        table.insert(matches, task)
      end
    end
    return matches
  end

  T["DapLaunch compound creates multiple debug session tasks"] = function()
    MiniTest.skip("Overseer backend not yet implemented")
    local h = ctx.create()
    local fixture_path = h:fixture("multi-session")

    h.child.lua(string.format([[vim.fn.chdir(%q)]], fixture_path))
    h:cmd("DapLaunch Both Programs")
    h:wait(1500)

    local tasks = get_tasks(h)

    -- Print task info
    print("=== DapLaunch Compound Tasks: " .. #tasks .. " ===")
    for _, task in ipairs(tasks) do
      print(string.format("  id=%d name=%s status=%s parent_id=%s",
        task.id, task.name, task.status, tostring(task.parent_id)))
    end

    -- Should have 2 running tasks (one per debug session in compound)
    local running = count_by_status(tasks, "RUNNING")
    MiniTest.expect.equality(running, 2, "Expected 2 running tasks for compound, got " .. running)

    -- Both should be top-level (no parent)
    local debug_a = find_tasks_by_name(tasks, "Debug A")
    local debug_b = find_tasks_by_name(tasks, "Debug B")
    MiniTest.expect.equality(#debug_a, 1, "Expected 1 Debug A task")
    MiniTest.expect.equality(#debug_b, 1, "Expected 1 Debug B task")
    MiniTest.expect.equality(debug_a[1].parent_id, nil, "Debug A should be top-level")
    MiniTest.expect.equality(debug_b[1].parent_id, nil, "Debug B should be top-level")
  end

  T["OverseerRun compound creates orchestrator with child tasks"] = function()
    MiniTest.skip("Overseer backend not yet implemented")
    local h = ctx.create()
    local fixture_path = h:fixture("multi-session")

    h.child.lua(string.format([[vim.fn.chdir(%q)]], fixture_path))
    h.child.lua([[require("overseer").run_template({ name = "Debug: Both Programs" })]])
    h:wait(1500)

    local tasks = get_tasks(h)

    -- Print task info
    print("=== OverseerRun Compound Tasks: " .. #tasks .. " ===")
    for _, task in ipairs(tasks) do
      print(string.format("  id=%d name=%s status=%s parent_id=%s",
        task.id, task.name, task.status, tostring(task.parent_id)))
    end

    -- Should have 3 tasks: 1 orchestrator + 2 child debug sessions
    local running = count_by_status(tasks, "RUNNING")
    MiniTest.expect.equality(running, 3, "Expected 3 running tasks (orchestrator + 2 children), got " .. running)

    -- Find the orchestrator (parent) task
    local orchestrator = find_tasks_by_name(tasks, "Both Programs")
    MiniTest.expect.equality(#orchestrator, 1, "Expected 1 orchestrator task")
    MiniTest.expect.equality(orchestrator[1].parent_id, nil, "Orchestrator should be top-level")

    -- Child tasks should have orchestrator as parent
    local debug_a = find_tasks_by_name(tasks, "Debug A")
    local debug_b = find_tasks_by_name(tasks, "Debug B")
    MiniTest.expect.equality(#debug_a, 1, "Expected 1 Debug A task")
    MiniTest.expect.equality(#debug_b, 1, "Expected 1 Debug B task")
    MiniTest.expect.equality(debug_a[1].parent_id, orchestrator[1].id, "Debug A should be child of orchestrator")
    MiniTest.expect.equality(debug_b[1].parent_id, orchestrator[1].id, "Debug B should be child of orchestrator")
  end

  T["terminating one session keeps other running"] = function()
    MiniTest.skip("Overseer backend not yet implemented")
    local h = ctx.create()
    local fixture_path = h:fixture("multi-session")

    h.child.lua(string.format([[vim.fn.chdir(%q)]], fixture_path))
    h:cmd("DapLaunch Both Programs")
    h:wait(1500)

    -- Get initial tasks
    local tasks = get_tasks(h)
    local running_before = count_by_status(tasks, "RUNNING")
    MiniTest.expect.equality(running_before, 2, "Expected 2 running tasks initially")

    -- Terminate one session (the first one)
    h.child.lua([[(function()
      local debugger = require("neodap").debugger
      for session in debugger.sessions:iter() do
        session:terminate()
        break
      end
    end)()]])
    h:wait(1000)

    -- One should still be running
    tasks = get_tasks(h)
    local running_after = count_by_status(tasks, "RUNNING")
    MiniTest.expect.equality(running_after, 1, "Expected 1 running task after terminating one, got " .. running_after)
  end

end)

return T
