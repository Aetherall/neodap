local harness = require("helpers.test_harness")

return harness.integration("dap_jump", function(T, ctx)
  -- User scenario: Jump to current frame location
  T["DapJump @frame opens source at frame location"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.jump_cmd")
    h:fixture("simple-vars")
    local main_path = h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Get expected location before jumping
    local expected_line = h:query_field("@frame", "line")

    -- User runs DapJump command
    h:cmd("DapJump @frame")
    h:wait(100)

    -- Verify cursor is at frame location
    local cursor = h.child.api.nvim_win_get_cursor(0)
    local bufname = h.child.api.nvim_buf_get_name(0)

    MiniTest.expect.equality(bufname, main_path)
    MiniTest.expect.equality(cursor[1], expected_line)
  end

  -- User scenario: Jump using frame URI directly
  T["DapJump with frame URI opens source at location"] = function()
    local h = ctx.create()
    h:use_plugin("neodap.plugins.jump_cmd")
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local frame_uri = h:query_field("@frame", "uri")
    local expected_line = h:query_field("@frame", "line")

    -- User runs DapJump with specific frame URI
    h:cmd("DapJump " .. frame_uri)
    h:wait(100)

    local cursor = h.child.api.nvim_win_get_cursor(0)
    MiniTest.expect.equality(cursor[1], expected_line)
  end

  -- User scenario: Jump without debug session shows warning
  T["DapJump without session shows no entity warning"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.jump_cmd")

    -- User tries to jump without a debug session - command errors
    h:expect_cmd_fails("DapJump @frame", "resolve")
  end

  -- User scenario: Jump to non-frame entity shows warning
  T["DapJump @session shows cannot focus warning"] = function()
    local h = ctx.create()
    h:use_plugin("neodap.plugins.jump_cmd")
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- User tries to jump to session (not a frame) - command errors
    h:expect_cmd_fails("DapJump @session", "not a frame")
  end

  -- User scenario: Jump doesn't work in winfixbuf window
  T["DapJump respects winfixbuf and stays in current buffer"] = function()
    local h = ctx.create()
    h:use_plugin("neodap.plugins.jump_cmd")
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Create a new buffer with winfixbuf
    h.child.cmd("enew")
    h.child.cmd("setlocal winfixbuf")

    local initial_bufnr = h.child.api.nvim_get_current_buf()

    -- User tries to jump - should fail due to winfixbuf
    h:expect_cmd_fails("DapJump @frame", "winfixbuf")

    -- Buffer should not have changed
    local final_bufnr = h.child.api.nvim_get_current_buf()
    MiniTest.expect.equality(final_bufnr, initial_bufnr)
  end

  -- User scenario: Jump after stepping to new location
  T["DapJump @frame goes to current frame after step"] = function()
    local h = ctx.create()
    h:use_plugin("neodap.plugins.jump_cmd")
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local initial_line = h:query_field("@frame", "line")

    -- Step a few times to move to new location (line 1 -> 2 -> 3)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=3)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Get the new frame location
    local frame_line = h:query_field("@frame", "line")

    -- Verify we moved to a different line
    MiniTest.expect.equality(frame_line > initial_line, true)

    -- Jump should move cursor to frame location
    h:cmd("DapJump @frame")
    h:wait(100)

    -- Cursor should be at frame line
    local cursor = h.child.api.nvim_win_get_cursor(0)
    MiniTest.expect.equality(cursor[1], frame_line)
  end

  -- User scenario: Jump with invalid URL shows error
  T["DapJump with invalid URL shows error"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.jump_cmd")

    h:expect_cmd_fails("DapJump invalid:uri:format", "resolve")
  end

  -- User scenario: Jump without argument defaults to @frame
  T["DapJump without argument jumps to @frame"] = function()
    local h = ctx.create()
    h:use_plugin("neodap.plugins.jump_cmd")
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local expected_line = h:query_field("@frame", "line")

    -- DapJump without argument should default to @frame
    h:cmd("DapJump")
    h:wait(100)

    local cursor = h.child.api.nvim_win_get_cursor(0)
    MiniTest.expect.equality(cursor[1], expected_line)
  end

  -- User scenario: Picker shows when URL resolves to multiple frames
  T["DapJump with multiple frames shows picker"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.jump_cmd")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:fixture("with-function")

    -- Set breakpoint inside inner() at line 2
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    -- Launch and hit breakpoint (now inside inner(), called from outer())
    h:cmd("DapLaunch Debug")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Verify we have multiple frames (inner, outer, <module>)
    local frame_count = h:query_count("@thread/stacks[0]/frames")
    assert(frame_count >= 2, "Expected at least 2 frames, got " .. frame_count)

    -- Get the second frame's line (outer's call site)
    local second_frame_line = h:query_field("@thread/stacks[0]/frames[1]", "line")

    -- DapJump with URL that matches multiple frames triggers picker
    -- Use type_keys for command + inputlist response (avoids blocking h:cmd)
    h.child.type_keys(":DapJump @thread/stacks[0]/frames<CR>")
    h:wait(50)
    -- Default vim.ui.select uses inputlist(), type "2<CR>" to select second item
    h.child.type_keys("2<CR>")
    h:wait(100)

    -- Verify we jumped to second frame's location
    local cursor = h.child.api.nvim_win_get_cursor(0)
    MiniTest.expect.equality(cursor[1], second_frame_line)
  end

  -- User scenario: Single frame result skips picker
  T["DapJump with single frame skips picker"] = function()
    local h = ctx.create()
    h:use_plugin("neodap.plugins.jump_cmd")
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local expected_line = h:query_field("@frame", "line")

    -- URL with [0] index returns single frame - no picker
    h:cmd("DapJump @thread/stacks[0]/frames[0]")
    h:wait(100)

    -- Should jump directly without picker interaction
    local cursor = h.child.api.nvim_win_get_cursor(0)
    MiniTest.expect.equality(cursor[1], expected_line)
  end
end)
