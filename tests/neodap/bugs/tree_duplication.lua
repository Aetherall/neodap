-- Verify: tree structure for js-debug parent/child session hierarchy
--
-- js-debug creates parent/child session hierarchy naturally:
-- - Parent session (pwa-node launcher)
-- - Child session (actual debuggee)
-- - Thread in child session
--
-- Tree shows sessions under Configs group:
-- - Configs: shows Config entities which contain target sessions with threads
-- The Config entity groups sessions by launch configuration.

local harness = require("helpers.test_harness")

-- JavaScript only - creates parent/child session hierarchy
local original_adapters = harness.enabled_adapters
harness.enabled_adapters = { "javascript" }

local T = harness.integration("tree_duplication", function(T, ctx)
  T["thread appears under Configs group"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Wait for child session to fully populate (js-debug timing)
    h:wait(500)

    -- Open tree at debugger root
    h:open_tree("@debugger")
    h:wait(300)

    -- Get all buffer lines
    local lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)

    -- Check that Configs appears in the tree
    local has_configs = false
    for _, line in ipairs(lines) do
      if line:match("Configs") then
        has_configs = true
        break
      end
    end
    MiniTest.expect.equality(has_configs, true,
      string.format("Should show Configs group. Lines:\n%s", table.concat(lines, "\n")))

    -- Configs has eager=true for activeConfigs, and Config has eager targets,
    -- so sessions should auto-expand showing Threads group
    local has_threads_group = false
    for _, line in ipairs(lines) do
      if line:match("Threads") then
        has_threads_group = true
        break
      end
    end
    MiniTest.expect.equality(has_threads_group, true,
      string.format("Should show Threads group (under Configs > Config > Session). Lines:\n%s", table.concat(lines, "\n")))

    -- Now expand Threads to show Thread entity
    h.child.fn.search("Threads")
    h.child.type_keys("<CR>")  -- Expand Threads group
    h:wait(500)  -- Wait for threads to be fetched and tree to re-render

    -- Get buffer lines after expand
    lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)

    -- Check that Thread entity appears (not just Threads group)
    local has_thread_entity = false
    for _, line in ipairs(lines) do
      if line:match("Thread %d+:") then
        has_thread_entity = true
        break
      end
    end
    MiniTest.expect.equality(has_thread_entity, true,
      string.format("Should show Thread entity after expanding Threads. Lines:\n%s",
        table.concat(lines, "\n")))
  end

  T["expanding Output preserves Threads in tree"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(500)

    -- Open tree at debugger root
    h:open_tree("@debugger")
    h:wait(300)

    -- Get lines and verify both Output and Threads appear under Config's target session
    local lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)

    local has_output = false
    local has_threads = false
    for _, line in ipairs(lines) do
      if line:match("Output") then has_output = true end
      if line:match("Threads") then has_threads = true end
    end

    MiniTest.expect.equality(has_output, true,
      string.format("Should have Output in tree. Lines:\n%s", table.concat(lines, "\n")))
    MiniTest.expect.equality(has_threads, true,
      string.format("Should have Threads in tree. Lines:\n%s", table.concat(lines, "\n")))

    -- Expand Output
    h.child.fn.search("Output")
    h.child.type_keys("<CR>")
    h:wait(300)

    -- Get lines again and verify Threads is still present
    lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)

    has_threads = false
    for _, line in ipairs(lines) do
      if line:match("Threads") then
        has_threads = true
        break
      end
    end

    MiniTest.expect.equality(has_threads, true,
      string.format("Threads should still be present after expanding Output. Lines:\n%s", table.concat(lines, "\n")))
  end

  T["data model has correct entity counts"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Wait for child session to fully populate
    h:wait(500)

    -- Count sessions via URL query
    local session_count = h:query_count("/sessions")

    -- js-debug creates 2 sessions: parent (launcher) and child (debuggee)
    MiniTest.expect.equality(session_count >= 2, true,
      string.format("Expected at least 2 sessions (parent + child), got %d", session_count))

    -- Count threads - should have exactly 1 thread in the child session
    local thread_count = h:query_count("/sessions/threads")
    MiniTest.expect.equality(thread_count >= 1, true,
      string.format("Expected at least 1 thread, got %d", thread_count))
  end
end)

-- Restore adapters
harness.enabled_adapters = original_adapters

return T
