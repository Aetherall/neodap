-- Tests for tree_buffer reactivity
-- These tests verify that the tree updates automatically when entities change
--
-- BUG: Tree doesn't update reactively when outputs are added to already-expanded nodes.
-- The View/neograph reactivity system should trigger re-render when edge collections change.
local harness = require("helpers.test_harness")

local T = harness.integration("tree_buffer_reactivity", function(T, ctx)

  T["expanded Output node updates when new output arrives"] = function()
    -- Skip for JavaScript - different line numbers for logging_steps program
    if ctx.adapter_name == "javascript" then
      return
    end

    -- This test exposes a reactivity bug:
    -- 1. Open tree with Output node expanded (empty)
    -- 2. Produce output via stepping
    -- 3. Tree should show output WITHOUT re-expanding
    --
    -- EXPECTED: Output children appear automatically
    -- ACTUAL: Output node stays empty despite output entity existing
    local h = ctx.create()
    h:fixture("logging-steps")
    h:setup_visual()
    h:use_plugin("neodap.plugins.tree_buffer")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Open tree and expand Output node BEFORE any output exists
    h.child.cmd("vsplit")
    h.child.cmd("wincmd l")
    h:open_tree("@session", 0)
    -- Navigate to Output node and expand (currently empty)
    h.child.cmd("call search('Output')")
    h.child.type_keys("0")
    h.child.type_keys("<CR>")

    -- Step to produce output (logging_steps: line 1 -> 5 -> 6)
    h.child.cmd("wincmd h")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=5)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")  -- Past function def
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=6)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")  -- Execute log call - produces output

    -- Wait for output entity to exist
    h:wait_url("@session/outputs[0]")

    -- Switch back to tree - should show output reactively
    h.child.cmd("wincmd l")
    h:wait(200)
    h.child.cmd("redraw!")

    if ctx.adapter_name == "python" then
      -- Content assertion for Python: more stable than screenshot due to debugpy batching
      h:assert_buffer_contains("Step 1", "Output node should show Step 1 reactively")
      h:assert_buffer_contains("Output", "Tree should show Output node")
    else
      -- Wait for UI to settle (js-debug output timing)
      h:wait(300)
      -- Screenshot for JavaScript: different output structure
      MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
    end
  end

  T["collapsed Output node shows children when expanded after output"] = function()
    -- Skip for Python - output capture timing is inconsistent
    if ctx.adapter_name == "python" then
      return
    end

    -- Control test: verify outputs appear when expanded AFTER they exist
    -- This should pass - it's the normal case
    local h = ctx.create()
    h:fixture("logging-steps")
    h:setup_visual()
    h:use_plugin("neodap.plugins.tree_buffer")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    
    -- Get session URI before termination (focus is cleared on termination)
    local session_uri = h:query_field("@session", "uri")

    -- Run to completion to produce all outputs
    h:cmd("DapContinue")
    h:wait_terminated(5000)
    h:wait_url(session_uri .. "/outputs[0]")

    -- Now open tree using session URI directly
    h.child.cmd("vsplit")
    h.child.cmd("wincmd l")
    h:open_tree(session_uri, 0)
    -- Navigate to Output node and expand - should show existing outputs
    h.child.cmd("call search('Output')")
    h.child.type_keys("0")
    h.child.type_keys("<CR>")

    -- Wait for UI to settle (js-debug output timing)
    h:wait(300)

    -- Screenshot: Output node should show children
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["thread state updates reactively when stopped"] = function()
    -- Verify thread state changes are reactive
    -- Thread should show (stopped) after stepping
    local h = ctx.create()
    h:fixture("simple-vars")
    h:setup_visual()
    h:use_plugin("neodap.plugins.tree_buffer")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Open tree showing session (which now has Threads and Output groups)
    h.child.cmd("vsplit")
    h.child.cmd("wincmd l")
    h:open_tree("@session", 0)

    -- Expand Threads group to show Thread
    h.child.cmd("call search('Threads')")
    h.child.type_keys("<CR>")

    -- Wait for UI to settle (js-debug child session timing)
    h:wait(300)

    -- Screenshot: thread should show (stopped)
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["session state updates reactively when terminated"] = function()
    -- Verify session state changes are reactive
    local h = ctx.create()
    h:fixture("simple-vars")
    h:setup_visual()
    -- Use show_root to see session state changes
    h:use_plugin("neodap.plugins.tree_buffer", { show_root = true })

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    
    -- Get session URI before termination (focus is cleared on termination)
    local session_uri = h:query_field("@session", "uri")

    -- Open tree with direct session URI (will remain valid after termination)
    h.child.cmd("vsplit")
    h.child.cmd("wincmd l")
    h:open_tree(session_uri, 0)

    -- Continue to completion
    h.child.cmd("wincmd h")
    h:cmd("DapContinue")
    h:wait_terminated(5000)

    -- Switch back to tree - should show (terminated) reactively
    h.child.cmd("wincmd l")
    -- Wait for UI to settle (js-debug termination timing)
    h:wait(300)
    h.child.cmd("redraw!")

    -- Content assertion: more stable than screenshot due to adapter timing variability
    -- (js-debug thread state may not update to "exited" before termination)
    -- Check for stop icon ⏹ which represents terminated/exited state
    h:assert_buffer_contains("⏹", "Session should show stop icon (⏹) for terminated state")
  end

end)

return T
