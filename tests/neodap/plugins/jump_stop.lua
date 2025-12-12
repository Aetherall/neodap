-- Comprehensive tests for jump_stop plugin
-- Tests auto-jump behavior, enable/disable, vim commands, and cleanup
local harness = require("helpers.test_harness")

local T = harness.integration("jump_stop", function(T, ctx)
  T["jumps to file when thread state changes to stopped"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.jump_stop")

    -- Start from a different buffer
    h:enew()

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Wait for auto-jump to complete
    h:wait(1000)

    -- Check that we jumped to the test file (fixture main file)
    local current_buf = h.child.api.nvim_buf_get_name(0)
    local expected_path = h:query_field("@frame/source[0]", "path")
    MiniTest.expect.equality(current_buf, expected_path)
  end

  T["does not jump when disabled"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.jump_stop")

    -- Disable before starting session
    h:cmd("DapJumpStop off")

    -- Start from a different buffer
    h:enew()

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Give time for any jump to happen (it shouldn't because plugin is disabled)
    h:wait(500)

    -- Should not have jumped - current buffer should still be empty
    local current_buf = h.child.api.nvim_buf_get_name(0)
    local frame_path = h:query_field("@frame/source[0]", "path")
    MiniTest.expect.equality(current_buf == frame_path, false)
  end

  T["positions cursor at correct line"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.jump_stop")
    h:enew()

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Wait for auto-jump to complete
    h:wait(1000)

    -- Check cursor position - stopOnEntry should position at line 1
    local cursor_line = h.child.api.nvim_win_get_cursor(0)[1]
    MiniTest.expect.equality(cursor_line, 1)
  end

end)

return T
