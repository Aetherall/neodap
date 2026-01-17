local harness = require("helpers.test_harness")

return harness.integration("dap_breakpoint", function(T, ctx)
  -- Breakpoint creation tests using DapBreakpoint commands

  T["toggle creates breakpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    MiniTest.expect.equality(h:query_count("/breakpoints"), 0)

    h:edit_main()
    h:cmd("DapBreakpoint 1")

    MiniTest.expect.equality(h:query_count("/breakpoints"), 1)
    MiniTest.expect.equality(h:query_field("/breakpoints[0]", "line"), 1)
  end

  T["toggle removes existing breakpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 1")
    MiniTest.expect.equality(h:query_count("/breakpoints"), 1)

    -- Toggle again to remove
    h:cmd("DapBreakpoint 1")

    MiniTest.expect.equality(h:query_count("/breakpoints"), 0)
  end

  T["condition creates breakpoint with condition"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint condition 2 x > 0")

    MiniTest.expect.equality(h:query_count("/breakpoints"), 1)
    MiniTest.expect.equality(h:query_field("/breakpoints[0]", "condition"), "x > 0")
  end

  T["log creates breakpoint with log message"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint log 1 Value: {x}")

    MiniTest.expect.equality(h:query_count("/breakpoints"), 1)
    MiniTest.expect.equality(h:query_field("/breakpoints[0]", "logMessage"), "Value: {x}")
  end

  T["creates multiple breakpoints at different lines"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 1")
    h:cmd("DapBreakpoint 2")
    h:cmd("DapBreakpoint 3")

    MiniTest.expect.equality(h:query_count("/breakpoints"), 3)
  end

  T["toggle removes specific breakpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 1")
    MiniTest.expect.equality(h:query_count("/breakpoints"), 1)

    -- Toggle to remove
    h:cmd("DapBreakpoint 1")
    MiniTest.expect.equality(h:query_count("/breakpoints"), 0)
  end

  T["condition updates existing breakpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 1")
    -- Initial breakpoint has no condition (nil or vim.NIL)
    local initial_condition = h:query_field("/breakpoints[0]", "condition")
    MiniTest.expect.equality(initial_condition == nil or initial_condition == vim.NIL, true)

    h:cmd("DapBreakpoint condition 1 x == 1")
    MiniTest.expect.equality(h:query_field("/breakpoints[0]", "condition"), "x == 1")
  end

  T["log creates logpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint log 1 Value is {x}")

    MiniTest.expect.equality(h:query_field("/breakpoints[0]", "logMessage"), "Value is {x}")
  end

  -- Session integration tests (tests real adapter behavior)

  T["toggle finds line-only breakpoint when adjusted to point"] = function()
    -- Skip for JavaScript - multi-session toggle behavior differs
    if ctx.adapter_name == "javascript" then
      return
    end

    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    -- Add a breakpoint BEFORE session starts (line-only)
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    MiniTest.expect.equality(h:query_count("/breakpoints"), 1)

    -- Launch session
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Toggle again to remove
    h:cmd("DapBreakpoint 2")

    MiniTest.expect.equality(h:query_count("/breakpoints"), 0)
  end

  T["breakpoint syncs to debug session and stops execution"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:use_plugin("neodap.plugins.control_cmd")
    h:use_plugin("neodap.plugins.focus_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks(seq=1)[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks(seq=1)[0]/frames[0]")

    -- Add breakpoint via Vim command
    h:edit_main()
    h:cmd("2") -- Go to line 2
    h:cmd("DapBreakpoint")
    h:wait_url("/breakpoints[0]/bindings[0]")

    -- Continue to hit breakpoint
    h:cmd("DapContinue")
    h:wait_url("/sessions/threads/stacks(seq=2)[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks(seq=2)[0]/frames[0]")

    MiniTest.expect.equality(h:query_field("@frame", "line"), 2)
  end

  -- Vim command tests
  T[":DapBreakpoint toggles at cursor"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("2") -- Go to line 2
    h:cmd("DapBreakpoint")

    MiniTest.expect.equality(h:query_count("/breakpoints"), 1)
    MiniTest.expect.equality(h:query_field("/breakpoints[0]", "line"), 2)
  end

  T[":DapBreakpoint clear removes all breakpoints"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    -- Add multiple breakpoints
    h:edit_main()
    h:cmd("1")
    h:cmd("DapBreakpoint")
    h:cmd("2")
    h:cmd("DapBreakpoint")
    h:cmd("3")
    h:cmd("DapBreakpoint")

    MiniTest.expect.equality(h:query_count("/breakpoints"), 3)

    h:cmd("DapBreakpoint clear")

    MiniTest.expect.equality(h:query_count("/breakpoints"), 0)
  end
end)
