local harness = require("helpers.test_harness")

return harness.integration("focus", function(T, ctx)
  T["focus focuses session with stopped thread"] = function()
    local h = ctx.create()
    h:use_plugin("neodap.plugins.focus_cmd")
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Store original URIs
    local original_thread_uri = h:query_uri("@thread")
    local original_frame_uri = h:query_uri("@frame")

    -- Refocus on session (should restore thread and frame)
    h:cmd("DapFocus @session")

    -- Check session, thread, frame are all focused
    MiniTest.expect.equality(h:query_is_nil("@session"), false)
    MiniTest.expect.equality(h:query_uri("@thread"), original_thread_uri)
    MiniTest.expect.equality(h:query_uri("@frame"), original_frame_uri)
  end

  T["focus with no threads still sets focusedSession"] = function()
    local h = ctx.create()
    h:use_plugin("neodap.plugins.focus_cmd")
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Focus on session using absolute URL (no prior focus needed)
    h:cmd("DapFocus /sessions[0]")

    -- Session should be focused
    MiniTest.expect.equality(h:query_is_nil("@session"), false)
  end

  T["focus on session also focuses thread"] = function()
    local h = ctx.create()
    h:use_plugin("neodap.plugins.focus_cmd")
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Focus on session
    h:cmd("DapFocus @session")

    -- Thread should also be focused
    MiniTest.expect.equality(h:query_is_nil("@thread"), false)
  end

  T["focus on session preserves thread"] = function()
    local h = ctx.create()
    h:use_plugin("neodap.plugins.focus_cmd")
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Store original thread URI
    local original_thread_uri = h:query_uri("@thread")

    -- Focus on session
    h:cmd("DapFocus @session")

    -- Thread should be same as before
    MiniTest.expect.equality(h:query_uri("@thread"), original_thread_uri)
  end

  T["focus on terminated session still sets focusedSession"] = function()
    local h = ctx.create()
    h:use_plugin("neodap.plugins.focus_cmd")
    h:fixture("hello")
    h:cmd("DapLaunch Debug")
    h:wait_terminated(10000)

    -- Session is terminated (use absolute URL, no focus needed)
    MiniTest.expect.equality(h:query_field("/sessions[0]", "state"), "terminated")

    -- Focus on session
    h:cmd("DapFocus /sessions[0]")

    -- Session should be focused
    MiniTest.expect.equality(h:query_is_nil("@session"), false)
  end

  -- User scenario: Picker shows when URL resolves to multiple frames
  T["DapFocus with multiple frames shows picker"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.focus_cmd")
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

    -- Get the second frame's URI
    local second_frame_uri = h:query_field("@thread/stacks[0]/frames[1]", "uri")

    -- DapFocus with URL that matches multiple frames triggers picker
    -- Use type_keys for command + inputlist response (avoids blocking h:cmd)
    h.child.type_keys(":DapFocus @thread/stacks[0]/frames<CR>")
    h:wait(50)
    -- Default vim.ui.select uses inputlist(), type "2<CR>" to select second item
    h.child.type_keys("2<CR>")
    h:wait(100)

    -- Verify second frame is now focused
    local focused_uri = h:query_field("@frame", "uri")
    MiniTest.expect.equality(focused_uri, second_frame_uri)
  end

  -- User scenario: Single result skips picker
  T["DapFocus with single result skips picker"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.focus_cmd")
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")

    -- Clear focus first
    h:unfocus()
    MiniTest.expect.equality(h:query_is_nil("@session"), true)

    -- DapFocus with URL that matches single session - no picker needed
    h:cmd("DapFocus /sessions[0]")
    h:wait(100)

    -- Session should be focused directly
    MiniTest.expect.equality(h:query_is_nil("@session"), false)
  end
end)
