-- Visual test for multi-session breakpoint and frame highlight rendering
-- Reproduces: two sessions, breakpoints, stepping - captures marker/color issues

local harness = require("helpers.test_harness")

return harness.integration("multi_session_visual", function(T, ctx)
  T["two sessions at breakpoint with stepping"] = function()
    local h = ctx.create()
    h:fixture("simple-loop")
    h:setup_visual()
    h:use_plugin("neodap.plugins.breakpoint_signs")
    h:use_plugin("neodap.plugins.frame_highlights")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    -- Launch first session
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Add breakpoint on line 2 (inside loop)
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Step session 1 twice (to line 2)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Launch second session (still using same debug_file)
    h:cmd("DapLaunch Debug stop")
    -- Wait for second session to be stopped
    h:wait_url("/sessions(state=stopped)[1]/threads[0]/stacks[0]/frames[0]")

    -- Open source and take screenshot
    h:edit_main()
    h:wait(500)
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["session 1 stepped, session 2 at breakpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:setup_visual()
    h:use_plugin("neodap.plugins.breakpoint_signs")
    h:use_plugin("neodap.plugins.frame_highlights")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:use_plugin("neodap.plugins.hit_polyfill")

    -- Launch first session
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Add breakpoint on line 1
    h:edit_main()
    h:cmd("DapBreakpoint 1")
    h:wait_url("/breakpoints(line=1)/bindings(verified=true)")

    -- Step session 1 forward (line 1 -> 2)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Launch second session (stops on entry at line 1)
    h:cmd("DapLaunch Debug stop")
    -- Wait for second session to be stopped
    h:wait_url("/sessions(state=stopped)[1]/threads[0]/stacks[0]/frames[0]")

    -- Open source and take screenshot
    h:edit_main()
    h:wait(500)
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["breakpoint hit by both sessions shows correct marker"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:setup_visual()
    h:use_plugin("neodap.plugins.breakpoint_signs")
    h:use_plugin("neodap.plugins.frame_highlights")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:use_plugin("neodap.plugins.hit_polyfill")

    -- Launch first session
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Add breakpoint on line 1
    h:edit_main()
    h:cmd("DapBreakpoint 1")
    h:wait_url("/breakpoints(line=1)/bindings(verified=true)")

    -- Launch second session (also stops on entry at line 1)
    h:cmd("DapLaunch Debug stop")
    -- Wait for second session to be stopped
    h:wait_url("/sessions(state=stopped)[1]/threads[0]/stacks[0]/frames[0]")

    -- Both sessions now stopped at line 1 with breakpoint
    h:edit_main()
    h:wait(500)
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end
end)
