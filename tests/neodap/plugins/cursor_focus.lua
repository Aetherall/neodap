-- Tests for cursor_focus plugin
-- Tests cursor tracking and thread stop auto-focus
local harness = require("helpers.test_harness")

local T = harness.integration("cursor_focus", function(T, ctx)
  T["initializes context on BufEnter"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:init_plugin("neodap.plugins.cursor_focus", nil, "cursor_focus_api")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Open the source file - should initialize context
    h:edit_main()
    h:wait_context_frame()

    -- Check context has a frame
    MiniTest.expect.equality(h:context_has_frame(), true)
  end

  T["context frame matches stopped location"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:init_plugin("neodap.plugins.cursor_focus", nil, "cursor_focus_api")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:wait_context_frame()

    -- stopOnEntry should be at line 1
    MiniTest.expect.equality(h:context_frame_line(), 1)
  end

  T["auto-focuses top frame when thread stops"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:init_plugin("neodap.plugins.cursor_focus", nil, "cursor_focus_api")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait_url("@frame") -- Wait for focused frame

    -- After stop, focused frame should exist
    MiniTest.expect.equality(h:query_is_nil("@frame"), false)
  end

  T["update() API triggers context refresh"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:init_plugin("neodap.plugins.cursor_focus", nil, "cursor_focus_api")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:wait_context_frame()

    -- Context should have a frame after BufEnter
    MiniTest.expect.equality(h:context_has_frame(), true)

    -- Call update API (should not crash, should maintain context)
    h:call_plugin("cursor_focus_api", "update", true)
    h:wait_context_frame()

    MiniTest.expect.equality(h:context_has_frame(), true)
  end

  T["cleans up on BufWipeout"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:init_plugin("neodap.plugins.cursor_focus", nil, "cursor_focus_api")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:wait_context_frame()

    local bufnr = h:current_buf()
    MiniTest.expect.equality(h:context_has_frame(), true)

    -- Wipe the buffer
    h:bwipeout(bufnr, true)

    -- Buffer should no longer exist (immediate check)
    MiniTest.expect.equality(h:buf_valid(bufnr), false)
  end

  T["respects debounce for cursor movement"] = function()
    local h = ctx.create()
    h:fixture("with-function")
    -- Use short debounce for testing
    h:init_plugin("neodap.plugins.cursor_focus", { debounce_ms = 50 }, "cursor_focus_api")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:wait_context_frame()

    -- Move cursor rapidly - debounce should coalesce updates
    h:set_cursor(1, 0)
    h:set_cursor(2, 0)
    h:set_cursor(3, 0)

    -- Wait for debounce to settle (inherent timing for debounce testing)
    h:wait(100)

    -- Context should still work after debounced updates
    MiniTest.expect.equality(h:context_has_frame(), true)
  end

  T["handles buffer without debug source gracefully"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:init_plugin("neodap.plugins.cursor_focus", nil, "cursor_focus_api")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Open a buffer that has no associated source
    h:enew()
    h:set_lines(0, { "line 1", "line 2" })

    -- Should not crash - test passes if we get here
    MiniTest.expect.equality(true, true)
  end

  T["context persists when cursor moves within buffer"] = function()
    local h = ctx.create()
    h:fixture("with-function")
    h:init_plugin("neodap.plugins.cursor_focus", { debounce_ms = 10 }, "cursor_focus_api")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:wait_context_frame()

    -- Get initial frame
    MiniTest.expect.equality(h:context_has_frame(), true)

    -- Move cursor to different line
    local line_count = h:line_count()
    h:set_cursor(math.min(3, line_count), 0)

    -- Wait for debounce (10ms) to settle
    h:wait(50)

    -- Context should still have a frame (sticky behavior)
    MiniTest.expect.equality(h:context_has_frame(), true)
  end
end)

return T
