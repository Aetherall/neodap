local harness = require("helpers.test_harness")

return harness.integration("dap_continue", function(T, ctx)
  T[":DapContinue resumes execution to termination"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.control_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_field("@session", "state"), "stopped")

    h:cmd("DapContinue")

    h:wait_terminated(10000)
    MiniTest.expect.equality(h:query_field("@session", "state"), "terminated")
  end

  T[":DapContinue stops at breakpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.control_cmd")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:use_plugin("neodap.plugins.focus_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks(seq=1)[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks(seq=1)[0]/frames[0]")

    -- Open the file and add breakpoint at line 10
    h:edit_main()
    h:cmd("DapBreakpoint 10")
    -- Wait for breakpoint to be created and binding to sync
    h:wait_url("/breakpoints[0]/bindings[0]")

    -- Continue to breakpoint
    h:cmd("DapContinue")
    h:wait_url("/sessions/threads/stacks(seq=2)[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks(seq=2)[0]/frames[0]")

    MiniTest.expect.equality(h:query_field("@frame", "line"), 10)
  end

  T[":DapTerminate ends session"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.control_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:cmd("DapTerminate")

    h:wait_terminated(10000)
    MiniTest.expect.equality(h:query_field("@session", "state"), "terminated")
  end
end)
