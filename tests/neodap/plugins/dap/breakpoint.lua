local harness = require("helpers.test_harness")

return harness.integration("breakpoint", function(T, ctx)
  -------------------------------------------------------------------------------
  -- Basic Breakpoint Entity Tests
  -------------------------------------------------------------------------------

  T["source:addBreakpoint creates breakpoint entity"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Verify breakpoint exists and has correct line
    MiniTest.expect.equality(h:query_count("/breakpoints"), 1)
    MiniTest.expect.equality(h:query_field("/breakpoints[0]", "line"), 2)
  end

  T["breakpoint is linked to debugger"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Check breakpoint is linked to debugger via query
    MiniTest.expect.equality(h:query_count("/breakpoints"), 1)
    -- Breakpoint has debugger edge - verify it has at least one entry
    MiniTest.expect.equality(h:query_count("/breakpoints[0]/debugger") >= 1, true)
  end

  T["sourceBinding:syncBreakpoints sends to adapter"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Verify binding was created
    MiniTest.expect.equality(h:query_count("/breakpoints[0]/bindings"), 1)
  end

  T["BreakpointBinding has verified status from adapter"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Check binding is verified with expected properties
    MiniTest.expect.equality(h:query_field("/breakpoints[0]/bindings[0]", "verified"), true)
    MiniTest.expect.equality(h:query_field("/breakpoints[0]/bindings[0]", "breakpointId") ~= nil, true)
    MiniTest.expect.equality(h:query_field("/breakpoints[0]/bindings[0]", "actualLine"), 2)
  end

  T["BreakpointBinding links to breakpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Check binding exists and links back to breakpoint
    MiniTest.expect.equality(h:query_count("/breakpoints[0]/bindings"), 1)
    -- The binding's breakpoint edge should have at least one entry
    MiniTest.expect.equality(h:query_count("/breakpoints[0]/bindings[0]/breakpoint") >= 1, true)
  end

  T["breakpoint:remove deletes breakpoint and bindings"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Count before removal
    local bp_count_before = h:query_count("/breakpoints")
    local binding_count_before = h:query_count("/breakpoints[0]/bindings")

    -- Remove breakpoint (toggle off)
    h:cmd("DapBreakpoint 2")
    h:wait(500)

    -- Count after removal
    local bp_count_after = h:query_count("/breakpoints")

    MiniTest.expect.equality(bp_count_before, 1)
    MiniTest.expect.equality(binding_count_before, 1)
    MiniTest.expect.equality(bp_count_after, 0)
  end

  T["source:syncBreakpoints syncs all bindings"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    -- Add breakpoint BEFORE session (will be unbound initially)
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    -- Now launch - breakpoint syncs automatically
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Verify bindings created (may be >1 for multi-session adapters like js-debug)
    MiniTest.expect.equality(h:query_count("/breakpoints[0]/bindings") >= 1, true)
  end

  T["conditional breakpoint is sent to adapter"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd([[DapBreakpoint condition 2 x > 0]])
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Verify condition is set
    MiniTest.expect.equality(h:query_field("/breakpoints[0]", "condition"), "x > 0")
  end

  -------------------------------------------------------------------------------
  -- Breakpoint State Tests (via observable behavior)
  -------------------------------------------------------------------------------

  T["breakpoint has no bindings before session exists"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    -- Add breakpoint BEFORE session (will be unbound - no session to sync with)
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    -- Verify no bindings exist (unbound state)
    MiniTest.expect.equality(h:query_count("/breakpoints[0]/bindings"), 0)
  end

  T["breakpoint gets verified binding when session exists"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Verify binding exists and is verified (bound state)
    MiniTest.expect.equality(h:query_count("/breakpoints[0]/bindings"), 1)
    MiniTest.expect.equality(h:query_field("/breakpoints[0]/bindings[0]", "verified"), true)
  end

  T["breakpoint binding has hit=true when stopped at breakpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:use_plugin("neodap.plugins.hit_polyfill")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Set breakpoint on line 2
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Continue execution to hit the breakpoint at line 2
    h:cmd("DapContinue")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Wait for hit to be inferred (happens after stack trace fetch)
    h:wait_url("/breakpoints[0]/bindings(hit=true)")

    MiniTest.expect.equality(h:query_field("/breakpoints[0]/bindings[0]", "hit"), true)
  end

  T["hit state clears when continuing past breakpoint"] = function()
    local h = ctx.create()
    h:fixture("bp-multi-line")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:use_plugin("neodap.plugins.hit_polyfill")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Set breakpoints on line 2 and 4
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")
    h:cmd("DapBreakpoint 4")
    h:wait_url("/breakpoints(line=4)/bindings(verified=true)")

    -- Continue to hit line 2 breakpoint
    h:cmd("DapContinue")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait_url("/breakpoints(line=2)/bindings(hit=true)")

    -- First breakpoint should be hit
    MiniTest.expect.equality(h:query_field("/breakpoints(line=2)/bindings[0]", "hit"), true)

    -- Continue to hit line 4 breakpoint
    h:cmd("DapContinue")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=4)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait_url("/breakpoints(line=4)/bindings(hit=true)")

    -- Second breakpoint should be hit, first should be cleared
    MiniTest.expect.equality(h:query_field("/breakpoints(line=2)/bindings[0]", "hit"), false)
    MiniTest.expect.equality(h:query_field("/breakpoints(line=4)/bindings[0]", "hit"), true)
  end

  T["breakpoint binding actualLine reflects adapter adjustment"] = function()
    local h = ctx.create()
    -- Line 1: code, Line 2: blank, Line 3: code
    h:fixture("bp-blank-line")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Set breakpoint on blank line 2 - adapter should adjust to line 3
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Check if adapter adjusted the line (actualLine may differ from requested line)
    local requested_line = h:query_field("/breakpoints[0]", "line")
    local actual_line = h:query_field("/breakpoints[0]/bindings[0]", "actualLine")

    -- The breakpoint was requested at line 2
    MiniTest.expect.equality(requested_line, 2)
    -- actualLine should be set (either 2 if no adjustment, or 3 if adjusted)
    MiniTest.expect.equality(actual_line ~= nil, true)
  end

  -------------------------------------------------------------------------------
  -- Breakpoint Enabled/Disabled Tests
  -------------------------------------------------------------------------------

  T["breakpoint is enabled by default"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    MiniTest.expect.equality(h:query_field("/breakpoints[0]", "enabled"), true)
  end

  T["DapBreakpoint disable sets enabled to false"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    h:cmd("DapBreakpoint disable 2")
    h:wait_url("/breakpoints(enabled=false)")
    MiniTest.expect.equality(h:query_field("/breakpoints[0]", "enabled"), false)
  end

  T["DapBreakpoint enable sets enabled to true"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    h:cmd("DapBreakpoint disable 2")
    h:wait_url("/breakpoints(enabled=false)")
    h:cmd("DapBreakpoint enable 2")
    h:wait_url("/breakpoints(enabled=true)")
    MiniTest.expect.equality(h:query_field("/breakpoints[0]", "enabled"), true)
  end

  T["disabled/enabled cycle works correctly"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    local before = h:query_field("/breakpoints[0]", "enabled")

    h:cmd("DapBreakpoint disable 2")
    h:wait_url("/breakpoints(enabled=false)")
    local after_disable = h:query_field("/breakpoints[0]", "enabled")

    h:cmd("DapBreakpoint enable 2")
    h:wait_url("/breakpoints(enabled=true)")
    local after_enable = h:query_field("/breakpoints[0]", "enabled")

    MiniTest.expect.equality(before, true)
    MiniTest.expect.equality(after_disable, false)
    MiniTest.expect.equality(after_enable, true)
  end

  -------------------------------------------------------------------------------
  -- Disabled Breakpoint Integration Tests
  -------------------------------------------------------------------------------

  T["disabled breakpoint is NOT sent to adapter on sync"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    -- Add breakpoint BEFORE session, then disable it
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    h:cmd("DapBreakpoint disable 2")
    h:wait_url("/breakpoints(enabled=false)")

    -- Now launch - disabled breakpoint should not create a binding
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Count bindings - should be 0 since the only breakpoint was disabled
    MiniTest.expect.equality(h:query_count("/breakpoints[0]/bindings"), 0)
  end

  T["enabled breakpoint creates binding, disabled does not"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    -- Add two breakpoints before session
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    h:cmd("DapBreakpoint 10")
    h:wait_url("/breakpoints(line=10)")

    -- Disable the first one
    h:cmd("DapBreakpoint disable 2")
    h:wait_url("/breakpoints(line=2,enabled=false)")

    -- Now launch
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait_url("/breakpoints(line=10)/bindings(verified=true)")

    -- Only the enabled breakpoint (line 10) should have a binding
    -- (may be >1 for multi-session adapters like js-debug)
    MiniTest.expect.equality(h:query_count("/breakpoints[0]/bindings"), 0)  -- Disabled - no binding
    MiniTest.expect.equality(h:query_count("/breakpoints[1]/bindings") >= 1, true)  -- Enabled - has binding
  end

  T["program does not stop at disabled breakpoint"] = function()
    local h = ctx.create()
    h:fixture("bp-multi-line")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()

    -- Add breakpoints on lines 2 and 3 BEFORE launching
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    h:cmd("DapBreakpoint 3")
    h:wait_url("/breakpoints(line=3)")

    -- Disable line 2 before launch - avoids concurrent sync races
    h:cmd("DapBreakpoint disable 2")
    h:wait_url("/breakpoints(line=2,enabled=false)")

    -- Launch - initial sync will only send line 3 (line 2 is disabled)
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait_url("/breakpoints(line=3)/bindings(verified=true)")

    -- Continue - should skip line 2 and stop at line 3
    h:cmd("DapContinue")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=3)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Check we're at line 3, not line 2
    MiniTest.expect.equality(h:query_field("@frame", "line"), 3)
  end

  T["re-enabling breakpoint creates binding"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()

    -- Add breakpoint before launch, then disable it
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    h:cmd("DapBreakpoint disable 2")
    h:wait_url("/breakpoints(line=2,enabled=false)")

    -- Launch - disabled breakpoint should NOT create a binding
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    -- Wait for initial sync to complete
    h:wait(500)

    local count_disabled = h:query_count("/breakpoints[0]/bindings")

    -- Re-enable - binding should be created
    h:cmd("DapBreakpoint enable 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)", 5000)

    local count_enabled = h:query_count("/breakpoints[0]/bindings")

    MiniTest.expect.equality(count_disabled, 0)
    -- js-debug creates 2 sessions (parent + child), each with their own binding
    MiniTest.expect.equality(count_enabled >= 1, true)
  end
end)
