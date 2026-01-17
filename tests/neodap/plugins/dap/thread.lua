local harness = require("helpers.test_harness")

return harness.integration("thread", function(T, ctx)
  T["session:fetchThreads() populates thread entities"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_nil("@thread"), false)
    MiniTest.expect.equality(h:query_field("@thread", "threadId") ~= nil, true)
    MiniTest.expect.equality(h:query_count("@session/threads") >= 1, true)
  end

  T["thread:continue() resumes execution"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Continue the thread
    h:cmd("DapContinue")

    -- Wait for session to terminate (program finishes)
    h:wait_terminated(5000)

    MiniTest.expect.equality(h:query_field("@session", "state"), "terminated")
  end

  T["thread:stepOver() steps to next line"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step over (line 1 -> 2)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_field("@session", "state"), "stopped")
  end

  T["thread:fetchStackTrace() populates stack and frames"] = function()
    local h = ctx.create()
    h:fixture("with-function")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_count("@thread/stacks"), 1)
    MiniTest.expect.equality(h:query_count("@thread/stacks/frames") >= 1, true)
  end
end)
