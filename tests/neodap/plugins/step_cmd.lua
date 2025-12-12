local harness = require("helpers.test_harness")

return harness.integration("dap_step", function(T, ctx)
  T[":DapStep over advances to next line"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.step_cmd")
    h:use_plugin("neodap.plugins.focus_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks(seq=1)[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks(seq=1)[0]/frames[0]")

    MiniTest.expect.equality(h:query_field("@frame", "line"), 1)

    h:cmd("DapStep over")
    h:wait_url("/sessions/threads/stacks(seq=2)[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks(seq=2)[0]/frames[0]")

    MiniTest.expect.equality(h:query_field("@frame", "line"), 2)
  end

  T[":DapStep defaults to over"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.step_cmd")
    h:use_plugin("neodap.plugins.focus_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks(seq=1)[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks(seq=1)[0]/frames[0]")

    h:cmd("DapStep")
    h:wait_url("/sessions/threads/stacks(seq=2)[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks(seq=2)[0]/frames[0]")

    MiniTest.expect.equality(h:query_field("@frame", "line"), 2)
  end

  T["multiple :DapStep in sequence"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.step_cmd")
    h:use_plugin("neodap.plugins.focus_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks(seq=1)[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks(seq=1)[0]/frames[0]")

    h:cmd("DapStep over")
    h:wait_url("/sessions/threads/stacks(seq=2)[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks(seq=2)[0]/frames[0]")

    h:cmd("DapStep over")
    h:wait_url("/sessions/threads/stacks(seq=3)[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks(seq=3)[0]/frames[0]")

    -- After stepping from line 2, lands on try block (line 4 in Python, line 5 in JS)
    local line = h:query_field("@frame", "line")
    MiniTest.expect.equality(line >= 4 and line <= 5, true)
  end
end)
