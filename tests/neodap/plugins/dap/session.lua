local harness = require("helpers.test_harness")

return harness.integration("session", function(T, ctx)
  T["session exists after launch"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Session should exist (at least one session in debugger)
    MiniTest.expect.equality(h:query_count("/sessions") >= 1, true)
  end

  T["session transitions through states"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Session should be in stopped state
    MiniTest.expect.equality(h:query_field("@session", "state"), "stopped")
  end

  T["session is linked to debugger"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Check session hierarchy: session should be in debugger.sessions
    MiniTest.expect.equality(h:query_count("/sessions") >= 1, true)
  end

  T["session:disconnect() transitions to terminated"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Disconnect/terminate and wait for terminated state
    -- Use absolute URL since @session becomes nil when focus is cleared during termination
    local index = h.adapter.name == "javascript" and 1 or 0
    local session_url = string.format("/sessions[%d]", index)
    h:query_call("@session", "terminate")
    h:wait_field(session_url, "state", "terminated")

    MiniTest.expect.equality(h:query_field(session_url, "state"), "terminated")
  end

  T["session receives stopped event with stopOnEntry"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_field("@session", "state"), "stopped")
  end
end)
