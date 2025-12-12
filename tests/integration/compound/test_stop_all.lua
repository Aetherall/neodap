local MiniTest = require("mini.test")
local harness = require("helpers.test_harness")

return harness.integration("compound stopAll", function(T, ctx)
  T["stopAll terminates all sessions when one ends"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:cmd("DapLaunch Both Programs (stopAll)")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    local session_count = h:query_count("/sessions")

    -- disconnect one session — triggers stopAll cascade
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")

    -- Config should terminate (stopAll triggers Config:terminate() on all sessions)
    h:wait_field("/configs[0]", "state", "terminated", harness.TIMEOUT.LONG)

    -- all sessions should be terminated
    MiniTest.expect.equality(h:query_count("/sessions(state=terminated)"), session_count)
  end

  T["non-stopAll leaves other sessions running when one ends"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:cmd("DapLaunch Both Programs")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- disconnect one stopped session
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")
    h:wait_url("/sessions(state=terminated)[0]", harness.TIMEOUT.LONG)

    -- Config should still be active
    MiniTest.expect.equality(h:query_field("/configs[0]", "state"), "active")

    -- there should still be at least one stopped session
    MiniTest.expect.equality(h:query_is_nil("/sessions(state=stopped)[0]"), false)
  end

  T["stopAll cascade terminates all session types"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:cmd("DapLaunch Both Programs (stopAll)")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    local total_sessions = h:query_count("/sessions")

    if h.adapter.name == "javascript" then
      -- js-debug has parent+child per config, verify we have more than 2 sessions
      MiniTest.expect.equality(total_sessions > 2, true)
    end

    -- disconnect one session to trigger stopAll cascade
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")

    h:wait_field("/configs[0]", "state", "terminated", harness.TIMEOUT.LONG)

    -- every session (parent and child) should be terminated
    MiniTest.expect.equality(h:query_count("/sessions(state=terminated)"), total_sessions)
  end
end)
