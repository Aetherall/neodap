local harness = require("helpers.test_harness")

return harness.integration("dap_run_to_cursor", function(T, ctx)
  T["DapRunToCursor stops at target line"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.run_to_cursor_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local initial_line = h:query_field("@frame", "line")
    MiniTest.expect.equality(initial_line, 1)

    -- Open the file and position cursor at line 3
    h:edit_main()
    h:set_cursor(3, 0)

    -- Run to cursor
    h:cmd("DapRunToCursor")

    -- Wait for execution to reach line 3
    h:wait_url("/sessions/threads/stacks/frames(line=3)")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    MiniTest.expect.equality(h:query_field("@frame", "line"), 3)
  end

  T["DapRunToCursor removes temporary breakpoint after stop"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.run_to_cursor_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local bp_count_before = h:query_count("/breakpoints")

    -- Open the file and position cursor at line 3
    h:edit_main()
    h:set_cursor(3, 0)

    -- Run to cursor
    h:cmd("DapRunToCursor")

    -- Wait for running then stopped
    h:wait_url("/sessions(state=running)", 5000)
    h:wait_url("/sessions(state=stopped)", 5000)

    -- Wait for temp breakpoint to be removed
    h:wait(500)

    -- Breakpoint count should be same as before (temp bp removed)
    MiniTest.expect.equality(h:query_count("/breakpoints"), bp_count_before)
  end

  T["DapRunToCursor! skips intermediate breakpoints"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:use_plugin("neodap.plugins.run_to_cursor_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Add breakpoint at line 2 (intermediate)
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Position cursor at line 3
    h:set_cursor(3, 0)

    -- Run to cursor with ignoreBreakpoints - should skip line 2
    h:cmd("DapRunToCursor!")

    -- Wait for stop at line 3
    h:wait_url("/sessions/threads/stacks/frames(line=3)")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Should be at line 3, not line 2
    MiniTest.expect.equality(h:query_field("@frame", "line"), 3)
  end

  T["DapRunToCursor! restores breakpoints after stop"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:use_plugin("neodap.plugins.run_to_cursor_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Add breakpoint at line 2
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Verify breakpoint exists and is enabled before
    h:wait_url("/breakpoints(line=2,enabled=true)")

    -- Position cursor at line 3
    h:set_cursor(3, 0)

    -- Run to cursor with ignoreBreakpoints
    h:cmd("DapRunToCursor!")

    -- Wait for stop
    h:wait_url("/sessions(state=running)", 5000)
    h:wait_url("/sessions(state=stopped)", 5000)

    -- Wait for breakpoint to be re-enabled
    h:wait_url("/breakpoints(line=2,enabled=true)")

    -- Verify breakpoint count (should still have 1 breakpoint)
    MiniTest.expect.equality(h:query_count("/breakpoints(line=2)"), 1)
  end
end)
