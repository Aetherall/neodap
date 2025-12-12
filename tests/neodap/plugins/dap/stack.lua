local harness = require("helpers.test_harness")

return harness.integration("stack", function(T, ctx)
  T["stack contains frames from stack trace"] = function()
    local h = ctx.create()
    h:fixture("with-function")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_count("@thread/stacks"), 1)
    MiniTest.expect.equality(h:query_count("@thread/stacks/frames") >= 1, true)
  end

  T["frames have correct properties"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_nil("@frame"), false)
    MiniTest.expect.equality(h:query_field("@frame", "line"), 1)
    MiniTest.expect.equality(type(h:query_field("@frame", "name")), "string")
  end

  T["stack links back to thread"] = function()
    local h = ctx.create()
    h:fixture("hello")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Check stack exists and links back to thread
    MiniTest.expect.equality(h:query_count("@thread/stacks") >= 1, true)
    MiniTest.expect.equality(h:query_field_uri("@thread/stacks[0]", "thread"), h:query_uri("@thread"))
  end
end)
