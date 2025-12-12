-- Tests for console buffer
-- Covers output display, repl category, category toggles, and tailing
local harness = require("helpers.test_harness")

local T = harness.integration("console_buffer", function(T, ctx)

  T["console opens and shows session output"] = function()
    local h = ctx.create()
    h:fixture("logging-steps")
    h:use_plugin("neodap.plugins.console_buffer")
    h:use_plugin("neodap.plugins.tree_buffer")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Save session URI before termination
    local session_uri = tostring(h:query_field("@session", "uri"))

    -- Continue to completion to generate output
    h:cmd("DapContinue")
    h:wait_terminated(5000)
    h:wait_url(session_uri .. "/outputs[0]")

    -- Open console buffer
    h.child.cmd("edit dap://console/" .. session_uri)
    h:wait(300)

    -- Console should show output with category dots
    local content = h:buffer_content()
    MiniTest.expect.equality(content:find("●") ~= nil, true,
      "Console should show output category dots. Buffer:\n" .. content)
  end

  T["evaluate result appears in console"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.console_buffer")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.input_buffer")
    h:use_plugin("neodap.plugins.completion")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local session_uri = tostring(h:query_field("@session", "uri"))

    -- Evaluate an expression via the input buffer
    h.child.cmd("edit dap://input/@frame")
    h:wait(100)
    -- Set buffer content directly to avoid insert-mode key confusion
    h.child.api.nvim_buf_set_lines(0, 0, -1, false, { "1 + 1" })
    -- Submit with Enter in normal mode
    h.child.type_keys("<Esc>")
    h.child.type_keys("<CR>")
    h:wait(500)

    -- Open console buffer
    h.child.cmd("edit dap://console/" .. session_uri)
    h:wait(300)

    -- Console should show the evaluation result with arrow
    h:assert_buffer_contains("→", "Console should show evaluate result with arrow indicator")
  end

  T["category toggle hides outputs"] = function()
    -- Skip for Python - output capture timing is inconsistent
    if ctx.adapter_name == "python" then return end

    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.console_buffer")
    h:use_plugin("neodap.plugins.tree_buffer")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local session_uri = tostring(h:query_field("@session", "uri"))

    -- Continue to completion to generate stdout output
    h:cmd("DapContinue")
    h:wait_terminated(5000)
    h:wait_url(session_uri .. "/outputs[0]")

    -- Open console buffer
    h.child.cmd("edit dap://console/" .. session_uri)
    h:wait(300)

    -- Verify output is visible
    local before = h:buffer_content()
    local has_output = before:find("●") ~= nil
    MiniTest.expect.equality(has_output, true,
      "Console should show output dots before toggle. Buffer:\n" .. before)

    -- Toggle stdout off (key "1")
    h.child.type_keys("1")
    h:wait(200)

    -- Stdout outputs should be hidden
    local after = h:buffer_content()
    MiniTest.expect.equality(after ~= before, true,
      "Console content should change after toggling stdout off.\nBefore:\n" .. before .. "\nAfter:\n" .. after)
  end

  T["G keybind re-enables tailing"] = function()
    -- Skip for Python - output capture timing is inconsistent
    if ctx.adapter_name == "python" then return end

    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.console_buffer")
    h:use_plugin("neodap.plugins.tree_buffer")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local session_uri = tostring(h:query_field("@session", "uri"))

    h:cmd("DapContinue")
    h:wait_terminated(5000)
    h:wait_url(session_uri .. "/outputs[0]")

    -- Open console buffer
    h.child.cmd("edit dap://console/" .. session_uri)
    h:wait(300)

    -- Verify tailing starts enabled (cursor at line 1 = offset 0)
    local cursor_before = h.child.api.nvim_win_get_cursor(0)
    MiniTest.expect.equality(cursor_before[1], 1,
      "Tailing should start with cursor at top (line 1)")

    -- Press G to re-enable tailing (should keep cursor at top)
    h.child.type_keys("G")
    h:wait(100)
    local cursor_after = h.child.api.nvim_win_get_cursor(0)
    MiniTest.expect.equality(cursor_after[1], 1,
      "G should bring cursor back to top (re-tail)")
  end
  T["S keybind toggles orientation"] = function()
    -- Skip for Python - output capture timing is inconsistent
    if ctx.adapter_name == "python" then return end

    local h = ctx.create()
    h:fixture("logging-steps")
    h:use_plugin("neodap.plugins.console_buffer")
    h:use_plugin("neodap.plugins.tree_buffer")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local session_uri = tostring(h:query_field("@session", "uri"))

    h:cmd("DapContinue")
    h:wait_terminated(5000)
    h:wait_url(session_uri .. "/outputs[0]")

    -- Open console buffer (default: newest-first)
    h.child.cmd("edit dap://console/" .. session_uri)
    h:wait(300)

    local before = h:buffer_content()

    -- Toggle to chronological (S keybind)
    h.child.type_keys("S")
    h:wait(300)

    local after = h:buffer_content()

    -- Output order should be different (reversed)
    MiniTest.expect.equality(after ~= before, true,
      "Console content should change after toggling orientation.\nBefore:\n" .. before .. "\nAfter:\n" .. after)
  end
end)

return T
