local MiniTest = require("mini.test")
local harness = require("helpers.test_harness")

return harness.integration("compound config lifecycle", function(T, ctx)
  T["compound launch creates Config with correct properties"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:cmd("DapLaunch Both Programs")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    MiniTest.expect.equality(h:query_count("/configs"), 1)
    MiniTest.expect.equality(h:query_field("/configs[0]", "isCompound"), true)
    MiniTest.expect.equality(h:query_field("/configs[0]", "state"), "active")
  end

  T["Config tracks target count independently of total session count"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:cmd("DapLaunch Both Programs")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- targets are root sessions only, always 2 regardless of adapter
    MiniTest.expect.equality(h:query_field("/configs[0]", "targetCount"), 2)

    -- total session count differs: python=2, js-debug=4+ (parent+child per config)
    local session_count = h:query_count("/sessions")
    if h.adapter.name == "javascript" then
      MiniTest.expect.equality(session_count > 2, true)
    else
      MiniTest.expect.equality(session_count, 2)
    end
  end

  T["Config terminates when all sessions end"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:cmd("DapLaunch Both Programs")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)
    h:wait_url("/sessions(state=stopped)[1]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    -- disconnect sessions individually (more reliable than DapContinue across adapters)
    h:cmd("DapDisconnect /sessions(state=stopped)[0]")
    h:wait_url("/sessions(state=terminated)[0]", harness.TIMEOUT.LONG)

    h:cmd("DapDisconnect /sessions(state=stopped)[0]")

    -- Config should terminate once all targets are done
    h:wait_field("/configs[0]", "state", "terminated", harness.TIMEOUT.LONG)
  end

  T["single launch creates Config with isCompound false"] = function()
    local h = ctx.create()
    h:fixture("multi-session")
    h:cmd("DapLaunch Debug A stop")

    h:wait_url("/sessions(state=stopped)[0]/threads/stacks[0]/frames[0]", harness.TIMEOUT.LONG)

    MiniTest.expect.equality(h:query_count("/configs"), 1)
    MiniTest.expect.equality(h:query_field("/configs[0]", "isCompound"), false)
    MiniTest.expect.equality(h:query_field("/configs[0]", "state"), "active")
  end
end)
