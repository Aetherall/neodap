local harness = require("helpers.test_harness")

return harness.integration("ctx", function(T, ctx)
  -- User scenario: @frame is nil without a debug session
  T["@frame resolves nil when no session"] = function()
    local h = ctx.create()

    -- Without launching a session, @frame should return nil
    MiniTest.expect.equality(h:query_is_nil("@frame"), true)
    MiniTest.expect.equality(h:query_is_nil("@thread"), true)
    MiniTest.expect.equality(h:query_is_nil("@session"), true)
  end

  -- User scenario: After stopping, @frame resolves to current frame
  T["@frame resolves to focused frame after stop"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- After stop, context URLs should resolve
    MiniTest.expect.equality(h:query_is_nil("@frame"), false)
    MiniTest.expect.equality(h:query_is_nil("@thread"), false)
    MiniTest.expect.equality(h:query_is_nil("@session"), false)

    -- Frame should have expected properties
    local frame_line = h:query_field("@frame", "line")
    MiniTest.expect.equality(frame_line >= 1, true)
  end

  -- User scenario: DapFocus changes what @frame resolves to
  T["DapFocus changes @frame resolution"] = function()
    -- Skip for JavaScript - breakpoint sync timing causes issues
    if ctx.adapter_name == "javascript" then
      return
    end

    local h = ctx.create()

    h:use_plugin("neodap.plugins.focus_cmd")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:fixture("with-function")

    -- Set breakpoint inside function to get multiple frames
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Continue to breakpoint at line 2
    h:cmd("DapContinue")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Get URIs of first two frames
    local frame0_uri = h:query_field("@thread/stack/frames[0]", "uri")
    local frame1_uri = h:query_field("@thread/stack/frames[1]", "uri")

    -- Focus first frame
    h:cmd("DapFocus " .. frame0_uri)
    h:wait(50)
    local focused_uri_1 = h:query_field("@frame", "uri")
    MiniTest.expect.equality(focused_uri_1, frame0_uri)

    -- Focus second frame - @frame should now resolve differently
    h:cmd("DapFocus " .. frame1_uri)
    h:wait(50)
    local focused_uri_2 = h:query_field("@frame", "uri")
    MiniTest.expect.equality(focused_uri_2, frame1_uri)
  end

  -- User scenario: @frame updates after stepping
  T["@frame updates after stepping"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local initial_line = h:query_field("@frame", "line")

    -- Step to new location (line 1 -> 2 -> 3)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=3)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local new_line = h:query_field("@frame", "line")

    -- Frame should have moved to new line
    MiniTest.expect.equality(new_line > initial_line, true)
  end

  -- User scenario: DapJump uses current @frame context
  T["DapJump @frame uses current focus context"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.jump_cmd")
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local frame_line = h:query_field("@frame", "line")

    -- Jump should go to focused frame location
    h:cmd("DapJump @frame")
    h:wait(100)

    local cursor = h.child.api.nvim_win_get_cursor(0)
    MiniTest.expect.equality(cursor[1], frame_line)
  end

  -- User scenario: @session/threads resolves relative to focused session
  T["@session/threads resolves relative to focused session"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Query threads relative to focused session
    local thread_count = h:query_count("@session/threads")
    MiniTest.expect.equality(thread_count >= 1, true)

    -- Thread should have expected properties
    local thread_id = h:query_field("@session/threads[0]", "threadId")
    MiniTest.expect.equality(thread_id ~= nil, true)
  end

  -- User scenario: Context persists across operations
  T["context persists through continue and stop"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:fixture("simple-vars")

    -- Set breakpoint at line 2
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Session should be focused
    local session_uri_1 = h:query_field("@session", "uri")
    MiniTest.expect.equality(session_uri_1 ~= nil, true)

    -- Continue to breakpoint at line 2
    h:cmd("DapContinue")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Same session should still be focused
    local session_uri_2 = h:query_field("@session", "uri")
    MiniTest.expect.equality(session_uri_2, session_uri_1)

    -- But frame should be at new location (line 2)
    local frame_line = h:query_field("@frame", "line")
    MiniTest.expect.equality(frame_line, 2)
  end

  -- User scenario: Query with absolute URL doesn't need focus
  T["absolute URL query works without focus"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Get session URI for absolute query
    local session_uri = h:query_field("@session", "uri")

    -- Query using absolute URL (not @session)
    local session_name = h:query_field(session_uri, "name")
    MiniTest.expect.equality(session_name ~= nil, true)
  end

  -- User scenario: URL path after context marker
  T["@session with path suffix resolves correctly"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Query @session/threads/stack - should resolve the path
    local stack_exists = not h:query_is_nil("@session/threads[0]/stack")
    MiniTest.expect.equality(stack_exists, true)
  end

  -- ==========================================================================
  -- Additional contextual URL tests (from test_watch.lua)
  -- ==========================================================================

  T["@frame/scopes:Name resolves scope by name"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")

    -- Get scope name first
    local scope_name = h:query_field("@frame/scopes[0]", "name")

    -- Query by name should resolve
    local resolved_name = h:query_field("@frame/scopes:" .. scope_name, "name")
    MiniTest.expect.equality(resolved_name, scope_name)
  end
end)
