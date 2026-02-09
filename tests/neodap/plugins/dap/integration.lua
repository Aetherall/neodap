local harness = require("helpers.test_harness")

return harness.integration("integration", function(T, ctx)
  T["full debug flow: breakpoint -> stop -> inspect variables"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:init_plugin("neodap.plugins.breakpoint_cmd")

    -- Launch with stopOnEntry
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Add and sync breakpoint at line 10
    h:edit_main()
    h:cmd("DapBreakpoint 10")
    h:wait_url("/breakpoints(line=10)/bindings(verified=true)")

    -- Verify breakpoint was set
    MiniTest.expect.equality(h:query_count("/breakpoints(line=10)"), 1)
    MiniTest.expect.equality(h:query_field("/breakpoints[0]/bindings[0]", "verified"), true)

    -- Continue to hit the breakpoint at line 10
    h:cmd("DapContinue")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=10)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Should be stopped at line 10
    MiniTest.expect.equality(h:query_field("@frame", "line"), 10)

    -- Fetch scopes and variables
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")

    -- Check variables exist
    MiniTest.expect.equality(h:query_is_nil("@frame/scopes[0]/variables(name=x)[0]"), false)
    MiniTest.expect.equality(h:query_is_nil("@frame/scopes[0]/variables(name=y)[0]"), false)
  end
end)
