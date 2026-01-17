local harness = require("helpers.test_harness")

return harness.integration("frame", function(T, ctx)
  T["frame:fetchScopes() populates scope entities"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")

    MiniTest.expect.equality(h:query_count("@frame/scopes") >= 1, true)
  end

  T["scopes link back to frame"] = function()
    local h = ctx.create()
    h:fixture("hello")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")

    -- Check scope exists and links back to frame
    MiniTest.expect.equality(h:query_count("@frame/scopes") >= 1, true)
    MiniTest.expect.equality(h:query_field_uri("@frame/scopes[0]", "frame"), h:query_uri("@frame"))
  end

  T["frame:evaluate() evaluates expression"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks(seq=1)[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks(seq=1)[0]/frames[0]")

    -- Step once so x is defined (line 1 -> 2)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads/stacks(seq=2)[0]/frames[0]")  -- Wait for NEW stack
    h:cmd("DapFocus /sessions/threads/stacks(seq=2)[0]/frames[0]")

    -- Simple arithmetic that works in both Python and JS
    MiniTest.expect.equality(h:evaluate("1 + 10"), "11")
  end
end)
