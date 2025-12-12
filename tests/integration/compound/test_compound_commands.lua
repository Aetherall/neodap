local MiniTest = require("mini.test")
local harness = require("helpers.test_harness")

return harness.integration("compound commands", function(T, ctx)
  T["DapTerminateConfig terminates all sessions in Config"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:cmd("DapLaunch Both Programs")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    local session_count = h:query_count("/sessions")

    -- stabilize before focus (async events like breakpoint sync may be in-flight)
    h:wait(500)
    h:cmd("DapFocus /sessions(state=stopped)[0]/threads/stacks[0]/frames[0]")
    h:wait_url("@session", harness.TIMEOUT.SHORT)

    h:cmd("DapTerminateConfig")

    h:wait_field("/configs[0]", "state", "terminated", harness.TIMEOUT.LONG)

    -- all sessions should be terminated, not just the focused one
    MiniTest.expect.equality(h:query_count("/sessions(state=terminated)"), session_count)
  end

  T["DapTerminateAll terminates all active Configs"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:cmd("DapLaunch Both Programs")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    h:cmd("DapTerminateAll")

    h:wait_field("/configs[0]", "state", "terminated", harness.TIMEOUT.LONG)

    -- no active configs should remain
    MiniTest.expect.equality(h:query_count("/configs(state=active)"), 0)
  end

  T["DapRestartConfig relaunches all compound sessions"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:cmd("DapLaunch Both Programs")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- stabilize, then focus so DapRestartConfig has a focused Config
    h:wait(500)
    h:cmd("DapFocus /sessions(state=stopped)[0]/threads/stacks[0]/frames[0]")
    h:wait_url("@session", harness.TIMEOUT.SHORT)

    -- capture old session URIs after focus is stable
    local old_a = h:query_uri("/sessions(state=stopped)[0]")
    local old_b = h:query_uri("/sessions(state=stopped)[1]")

    h:cmd("DapRestartConfig")

    -- wait for new sessions to come up after restart
    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.EXTENDED)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.EXTENDED)

    -- new sessions should have different URIs
    local new_a = h:query_uri("/sessions(state=stopped)[0]")
    local new_b = h:query_uri("/sessions(state=stopped)[1]")
    local old_uris = { [old_a] = true, [old_b] = true }
    MiniTest.expect.equality(old_uris[new_a] or false, false)
    MiniTest.expect.equality(old_uris[new_b] or false, false)

    -- Config should persist and be active again
    MiniTest.expect.equality(h:query_count("/configs"), 1)
    MiniTest.expect.equality(h:query_field("/configs[0]", "state"), "active")
  end

  T["DapRestartRoot relaunches only targeted root session"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:cmd("DapLaunch Both Programs")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- capture all session URIs before restart
    local old_uris = {}
    local count = h:query_count("/sessions(state=stopped)")
    for i = 0, count - 1 do
      old_uris[#old_uris + 1] = h:query_uri("/sessions(state=stopped)[" .. i .. "]")
    end

    -- stabilize, then focus so DapRestartRoot has a session to operate on
    h:wait(500)
    h:cmd("DapFocus /sessions(state=stopped)[0]/threads/stacks[0]/frames[0]")
    h:wait_url("@session", harness.TIMEOUT.SHORT)

    h:cmd("DapRestartRoot")

    -- wait for sessions to settle after restart
    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.EXTENDED)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.EXTENDED)

    -- collect new session URIs
    local new_uris = {}
    local new_count = h:query_count("/sessions(state=stopped)")
    for i = 0, new_count - 1 do
      new_uris[h:query_uri("/sessions(state=stopped)[" .. i .. "]")] = true
    end

    -- exactly one old session should survive (the one NOT restarted)
    local survived = 0
    for _, uri in ipairs(old_uris) do
      if new_uris[uri] then survived = survived + 1 end
    end
    MiniTest.expect.equality(survived >= 1, true)
    MiniTest.expect.equality(survived < #old_uris, true) -- at least one was restarted

    -- Config should still be active with 1 config
    MiniTest.expect.equality(h:query_count("/configs"), 1)
    MiniTest.expect.equality(h:query_field("/configs[0]", "state"), "active")
  end
end)
