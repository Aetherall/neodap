-- Comprehensive tests for frame_highlights plugin
-- Tests highlight display, focus tracking, configuration, and cleanup
local harness = require("helpers.test_harness")

local T = harness.integration("frame_highlights", function(T, ctx)
  -------------------------------------------------------------------------------
  -- Configuration Tests
  -------------------------------------------------------------------------------

  T["accepts custom priority"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:init_plugin("neodap.plugins.frame_highlights", { priority = 200 }, "hl_api")
    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:focus("@frame")

    local bufnr = h.child.api.nvim_get_current_buf()
    local ns = h.child.api.nvim_get_namespaces()["neodap_frame_highlights"]
    local marks = h.child.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
    local priority = marks[1] and marks[1][4].priority

    MiniTest.expect.equality(priority, 200)
  end

  -------------------------------------------------------------------------------
  -- Highlight Display Tests (Visual)
  -------------------------------------------------------------------------------

  T["shows highlight for focused frame"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:setup_visual()
    h:use_plugin("neodap.plugins.frame_highlights")
    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:focus("@frame")
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["context frame changes color when focus changes"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:setup_visual()
    h:use_plugin("neodap.plugins.frame_highlights")
    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Focus frame (green), then unfocus (should become blue since same session)
    h:focus("@frame")
    h:unfocus()

    -- Screenshot should show frame in blue (no context = same session color)
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["updates highlight when stepping"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:setup_visual()
    h:use_plugin("neodap.plugins.frame_highlights")
    h:use_plugin("neodap.plugins.step_cmd")
    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:focus("@frame")

    -- Step over to line 2
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:focus("@frame", 300)

    -- Screenshot should show highlight on line 2 (after step)
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  -------------------------------------------------------------------------------
  -- Stack Frame Tests (Visual) - Validates bug fix for multiple green highlights
  -- These tests use REALISTIC scenarios with multiple frames in the same buffer
  -------------------------------------------------------------------------------

  T["recursive call shows multiple frames with one green"] = function()
    -- Skip for JavaScript - different line numbers for recursive program
    if ctx.adapter_name == "javascript" then
      return
    end

    -- REALISTIC: Recursive function creates multiple stack frames in same file
    local h = ctx.create()
    h:fixture("recursive")
    h:setup_visual()
    h:use_plugin("neodap.plugins.frame_highlights")
    h:use_plugin("neodap.plugins.step_cmd")
    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step to build up multiple stack frames in the same file
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=6)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]") -- move past function def to line 6
    h:cmd("DapStep into")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]") -- enter countdown(3), land on if check
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=4)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]") -- past if check to return statement
    h:cmd("DapStep into")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]") -- enter countdown(2)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=4)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]") -- past if check
    h:cmd("DapStep into")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]") -- enter countdown(1)

    h:focus("@frame", 300)

    -- Screenshot validates: only ONE green, multiple blues
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["stepping clears stale frames from same buffer"] = function()
    -- Skip for JavaScript - different line numbers for recursive program
    if ctx.adapter_name == "javascript" then
      return
    end

    -- REALISTIC: Step through recursive calls, verifying cleanup
    local h = ctx.create()
    h:fixture("recursive")
    h:setup_visual()
    h:use_plugin("neodap.plugins.frame_highlights")
    h:use_plugin("neodap.plugins.step_cmd")
    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step into recursive calls to build stack
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=6)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]") -- past function def
    h:cmd("DapStep into")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]") -- countdown(3)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=4)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]") -- past if check
    h:cmd("DapStep into")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]") -- countdown(2)

    h:focus("@frame", 100)

    -- Count extmarks matches stack frames - verified by screenshot
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["blue gradient visible in deep recursion"] = function()
    -- Skip for JavaScript - different line numbers for recursive program
    if ctx.adapter_name == "javascript" then
      return
    end

    -- REALISTIC: Deep recursion showing the blue gradient
    local h = ctx.create()
    h:fixture("recursive")
    h:setup_visual()
    h:use_plugin("neodap.plugins.frame_highlights")
    h:use_plugin("neodap.plugins.step_cmd")
    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Build deep stack
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=6)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]") -- to call site (line 6)
    h:cmd("DapStep into")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=4)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep into")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=4)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep into")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=4)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep into")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:focus("@frame", 300)

    -- Screenshot shows green for top, progressively darker blues
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  -------------------------------------------------------------------------------
  -- Multi-Session Tests (Visual) - Purple for other sessions
  -- Note: Python-only due to js-debug bootstrap complexity
  -------------------------------------------------------------------------------

  T["two sessions same file shows purple for other session"] = function()
    -- Skip for JavaScript - js-debug bootstrap makes multi-session complex
    if ctx.adapter_name == "javascript" then
      return
    end

    -- REALISTIC: Two debug sessions on the SAME file
    local h = ctx.create()
    h:fixture("recursive")
    h:setup_visual()
    h:use_plugin("neodap.plugins.frame_highlights")
    h:use_plugin("neodap.plugins.step_cmd")
    h:use_plugin("neodap.plugins.focus_cmd")
    h:edit_main()

    -- Launch first session
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    local session1_uri = h:query_field("@session", "uri")

    -- Step session1 into recursion (to line 2 inside countdown)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=6)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep into")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Launch second session on SAME file (wait for session index 1 specifically)
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")
    local session2_uri = h:query_field("@session", "uri")

    -- Explicitly focus session2 before stepping (ensures @thread is session2's)
    h:cmd("DapFocus " .. session2_uri)
    h:wait(50)

    -- Step session2 to different position (to line 6)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=6)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Focus session2's frame (second session becomes context)
    h:focus("@frame")
    h:wait(300)

    -- Screenshot should show:
    -- - Green: session2's context frame (line 6)
    -- - Purple: session1's frames (different session, line 2)
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  -------------------------------------------------------------------------------
  -- Cleanup Tests
  -------------------------------------------------------------------------------

  T["cleanup removes highlight"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.frame_highlights")
    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:focus("@frame")

    -- Check marks exist before cleanup
    local bufnr = h.child.api.nvim_get_current_buf()
    local ns = h.child.api.nvim_get_namespaces()["neodap_frame_highlights"]
    local marks_before = h.child.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})

    MiniTest.expect.equality(#marks_before >= 1, true)

    -- Cleanup via debugger:dispose()
    h:dispose()

    -- Check marks removed
    local marks_after = h.child.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})

    MiniTest.expect.equality(#marks_after, 0)
  end

  -------------------------------------------------------------------------------
  -- No Focused Frame Tests (Visual)
  -------------------------------------------------------------------------------

  T["no highlight when no focused frame"] = function()
    local h = ctx.create()

    h:setup_visual()
    h:use_plugin("neodap.plugins.frame_highlights")

    -- Create buffer with code but no debug session
    local buf = h.child.api.nvim_create_buf(false, true)
    h.child.api.nvim_set_current_buf(buf)
    h.child.api.nvim_buf_set_lines(buf, 0, -1, false, { "x = 1", "print(x)" })
    h.child.cmd("setlocal filetype=python")
    h:wait(100)

    -- Screenshot should show clean buffer with no highlight
    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end
end)

return T
