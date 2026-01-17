-- Comprehensive tests for breakpoint_signs plugin
-- Tests sign display, state tracking, configuration, and cleanup
local harness = require("helpers.test_harness")

local T = harness.integration("breakpoint_signs", function(T, ctx)
  -------------------------------------------------------------------------------
  -- Sign Display Tests (Visual)
  -------------------------------------------------------------------------------

  T["shows sign for breakpoint in loaded buffer"] = function()
    local h = ctx.create()

    h:setup_visual()
    h:use_plugin("neodap.plugins.breakpoint_signs")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    -- Create buffer with content
    h:cmd("edit /tmp/test_bp_sign.py")
    h:set_lines(0, { "x = 1", "y = 2", "print(y)" })

    -- Add breakpoint via command
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["shows multiple signs for multiple breakpoints"] = function()
    local h = ctx.create()

    h:setup_visual()
    h:use_plugin("neodap.plugins.breakpoint_signs")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    -- Create buffer with content
    h:cmd("edit /tmp/test_bp_multi.py")
    h:set_lines(0, { "x = 1", "y = 2", "z = 3", "print(z)" })

    -- Add breakpoints via commands
    h:cmd("DapBreakpoint 1")
    h:cmd("DapBreakpoint 2")
    h:cmd("DapBreakpoint 4")
    h:wait_url("/breakpoints(line=4)")

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["signs cleanup via debugger dispose"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_signs")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:edit_main()

    local bufnr = h:get("vim.api.nvim_get_current_buf()")
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    local marks_after_add = h:get(string.format(
      "#vim.api.nvim_buf_get_extmarks(%d, vim.api.nvim_get_namespaces()['neodap_breakpoint_signs'], 0, -1, {})",
      bufnr
    ))

    -- Clear all breakpoints removes signs
    h:cmd("DapBreakpoint clear")
    h:wait(50)

    local marks_after_cleanup = h:get(string.format(
      "#vim.api.nvim_buf_get_extmarks(%d, vim.api.nvim_get_namespaces()['neodap_breakpoint_signs'] or 0, 0, -1, {})",
      bufnr
    ))

    MiniTest.expect.equality(marks_after_add, 1)
    MiniTest.expect.equality(marks_after_cleanup, 0)
  end

  T["shows unbound sign with correct highlight"] = function()
    local h = ctx.create()

    h:setup_visual()
    h:use_plugin("neodap.plugins.breakpoint_signs")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    -- Create buffer with content
    h:cmd("edit /tmp/test_bp_unbound.py")
    h:set_lines(0, { "x = 1", "y = 2", "print(y)" })

    -- Add breakpoint via command
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["shows disabled sign when breakpoint is disabled"] = function()
    local h = ctx.create()

    h:setup_visual()
    h:use_plugin("neodap.plugins.breakpoint_signs")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    -- Create buffer with content
    h:cmd("edit /tmp/test_bp_disabled.py")
    h:set_lines(0, { "x = 1", "y = 2", "print(y)" })

    -- Add breakpoint via command
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    -- Disable the breakpoint via command
    h:cmd("DapBreakpoint disable 2")
    h:wait_url("/breakpoints(enabled=false)")

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  -------------------------------------------------------------------------------
  -- Cleanup Tests
  -------------------------------------------------------------------------------

  T["cleanup removes all signs"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_signs")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:edit_main()

    local bufnr = h:get("vim.api.nvim_get_current_buf()")
    h:cmd("DapBreakpoint 1")
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    local marks_before = h:get(string.format(
      "#vim.api.nvim_buf_get_extmarks(%d, vim.api.nvim_get_namespaces()['neodap_breakpoint_signs'], 0, -1, {})",
      bufnr
    ))

    -- Clear all breakpoints removes all signs
    h:cmd("DapBreakpoint clear")
    h:wait(50)

    local marks_after = h:get(string.format(
      "#vim.api.nvim_buf_get_extmarks(%d, vim.api.nvim_get_namespaces()['neodap_breakpoint_signs'] or 0, 0, -1, {})",
      bufnr
    ))

    MiniTest.expect.equality(marks_before, 2)
    MiniTest.expect.equality(marks_after, 0)
  end

  -------------------------------------------------------------------------------
  -- Configuration Tests
  -------------------------------------------------------------------------------

  T["renders custom icons"] = function()
    local h = ctx.create()

    h:setup_visual()
    h:init_plugin("neodap.plugins.breakpoint_signs", { icons = { unbound = "B", bound = "V" } })
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    -- Create buffer with content
    h:cmd("edit /tmp/test_bp_custom_icon.py")
    h:set_lines(0, { "x = 1", "print(x)" })

    -- Add breakpoint via command
    h:cmd("DapBreakpoint 1")
    h:wait_url("/breakpoints(line=1)")

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["accepts custom priority"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:init_plugin("neodap.plugins.breakpoint_signs", { priority = 100 })
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:edit_main()

    local bufnr = h:get("vim.api.nvim_get_current_buf()")
    h:cmd("DapBreakpoint 1")
    h:wait_url("/breakpoints(line=1)")

    local priority = h:get(string.format([[
      (function()
        local ns = vim.api.nvim_get_namespaces()["neodap_breakpoint_signs"]
        local marks = vim.api.nvim_buf_get_extmarks(%d, ns, 0, -1, { details = true })
        return marks[1] and marks[1][4].priority
      end)()
    ]], bufnr))

    MiniTest.expect.equality(priority, 100)
  end

  -------------------------------------------------------------------------------
  -- Regression Tests
  -------------------------------------------------------------------------------

  T["adding second breakpoint while stopped does not move first sign"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:setup_visual()
    h:use_plugin("neodap.plugins.breakpoint_signs")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:use_plugin("neodap.plugins.control_cmd")
    h:edit_main()

    -- Add first breakpoint on line 2
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    -- Launch debugger with stopOnEntry, then continue to hit bp on line 2
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks(seq=1)[0]/frames[0]")
    h:cmd("DapContinue")
    h:wait_url("/sessions/threads/stacks(seq=2)[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Add second breakpoint on line 3 while stopped at first
    h:cmd("DapBreakpoint 3")
    h:wait_url("/breakpoints(line=3)/bindings(verified=true)")
    h:wait(100)

    -- Screenshot should show signs on BOTH line 2 and line 3
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

end)

return T
