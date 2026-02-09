local harness = require("helpers.test_harness")

return harness.integration("actions", function(T, ctx)

  -- ========================================================================
  -- toggle
  -- ========================================================================

  T["toggle disables an enabled breakpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    h:wait_field("/breakpoints(line=2)[0]", "enabled", true)

    h:run_action("toggle", "/breakpoints(line=2)[0]")
    h:wait_field("/breakpoints(line=2)[0]", "enabled", false)
  end

  T["toggle re-enables a disabled breakpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    h:run_action("toggle", "/breakpoints(line=2)[0]")
    h:wait_field("/breakpoints(line=2)[0]", "enabled", false)

    h:run_action("toggle", "/breakpoints(line=2)[0]")
    h:wait_field("/breakpoints(line=2)[0]", "enabled", true)
  end

  -- ========================================================================
  -- enable / disable
  -- ========================================================================

  T["disable disables a breakpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    h:wait_field("/breakpoints(line=2)[0]", "enabled", true)

    h:run_action("disable", "/breakpoints(line=2)[0]")
    h:wait_field("/breakpoints(line=2)[0]", "enabled", false)
  end

  T["enable enables a disabled breakpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    h:run_action("disable", "/breakpoints(line=2)[0]")
    h:wait_field("/breakpoints(line=2)[0]", "enabled", false)

    h:run_action("enable", "/breakpoints(line=2)[0]")
    h:wait_field("/breakpoints(line=2)[0]", "enabled", true)
  end

  T["enable on already-enabled breakpoint is a no-op"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    h:wait_field("/breakpoints(line=2)[0]", "enabled", true)

    h:run_action("enable", "/breakpoints(line=2)[0]")
    -- Still enabled
    MiniTest.expect.equality(h:query_field("/breakpoints(line=2)[0]", "enabled"), true)
  end

  -- ========================================================================
  -- remove
  -- ========================================================================

  T["remove deletes a breakpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    h:run_action("remove", "/breakpoints(line=2)[0]")
    h:yield(100)

    MiniTest.expect.equality(h:query_count("/breakpoints"), 0)
  end

  -- ========================================================================
  -- focus
  -- ========================================================================

  T["focus sets debugger context to frame"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local frame_uri = h:query_uri("@frame")

    h:run_action("focus", "@frame")
    h:yield(100)

    local focused_uri = h:query_uri("@frame")
    MiniTest.expect.equality(focused_uri, frame_uri)
  end

  -- ========================================================================
  -- edit_condition (via vim.ui.input)
  -- ========================================================================

  T["edit_condition sets breakpoint condition via vim.ui.input"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    -- type_keys triggers the action non-blockingly; vim.ui.input opens a prompt
    h.child.type_keys(":lua _G.debugger:action('edit_condition', _G.debugger:query('/breakpoints(line=2)[0]'))<CR>")
    h:wait(50)
    h.child.type_keys("x > 0<CR>")
    h:yield(100)

    MiniTest.expect.equality(h:query_field("/breakpoints(line=2)[0]", "condition"), "x > 0")
  end

  -- ========================================================================
  -- edit_hit_condition (via vim.ui.input)
  -- ========================================================================

  T["edit_hit_condition sets breakpoint hit condition via vim.ui.input"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    h.child.type_keys(":lua _G.debugger:action('edit_hit_condition', _G.debugger:query('/breakpoints(line=2)[0]'))<CR>")
    h:wait(50)
    h.child.type_keys("5<CR>")
    h:yield(100)

    MiniTest.expect.equality(h:query_field("/breakpoints(line=2)[0]", "hitCondition"), "5")
  end

  -- ========================================================================
  -- edit_log_message (via vim.ui.input)
  -- ========================================================================

  T["edit_log_message sets breakpoint log message via vim.ui.input"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    h.child.type_keys(":lua _G.debugger:action('edit_log_message', _G.debugger:query('/breakpoints(line=2)[0]'))<CR>")
    h:wait(50)
    h.child.type_keys("Value: {x}<CR>")
    h:yield(100)

    MiniTest.expect.equality(h:query_field("/breakpoints(line=2)[0]", "logMessage"), "Value: {x}")
  end

end)
