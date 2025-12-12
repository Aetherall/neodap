-- Integration tests for Session entity behavior
local harness = require("helpers.test_harness")

return harness.integration("session", function(T, ctx)
  T["creates graph and debugger"] = function()
    local h = ctx.create()

    -- Debugger should exist at root
    MiniTest.expect.equality(h:query_is_nil("/"), false)
    -- Debugger URI should be "debugger"
    MiniTest.expect.equality(h:query_uri("/"), "debugger")
  end

  T["Session tracks state"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Session should have a name (use @session for focused session)
    local session_name = h:query_field("@session", "name")
    MiniTest.expect.equality(session_name ~= nil, true)

    -- Session should have at least one stopped thread
    local stopped_count = h:query_count("@session/stoppedThreads")
    MiniTest.expect.equality(stopped_count >= 1, true)

    -- Continue execution
    h:cmd("DapContinue")
    h:wait_terminated(10000)
  end
end)
