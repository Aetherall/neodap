-- Minimal test to verify :DapLaunch works via test harness
local harness = require("helpers.test_harness")

return harness.integration("dap_launch", function(T, ctx)
  T["dap_launch starts session"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")

    -- Use DapLaunch command
    h:cmd("DapLaunch Debug stop")

    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Session should exist
    MiniTest.expect.equality(h:query_count("/sessions") >= 1, true)
    -- Should be stopped
    MiniTest.expect.equality(h:query_field("@session", "state"), "stopped")
  end
end)
