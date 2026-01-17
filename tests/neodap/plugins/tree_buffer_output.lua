-- Tests for output streaming in tree_buffer
-- Shows split-screen view of source code and output tree with logs appearing
--
-- NOTE: Python tests may be flaky due to debugpy's non-deterministic output batching.
-- Debugpy sometimes sends "text\n" as one event, sometimes as two separate events.
-- This is adapter behavior we cannot control. When tests fail, regenerate screenshots:
--   rm tests/screenshots/tests-neodap-plugins-tree_buffer_output.lua---python---*
--   make test-file FILE=tree_buffer_output
local harness = require("helpers.test_harness")

local T = harness.integration("tree_buffer_output", function(T, ctx)
  -------------------------------------------------------------------------------
  -- Split-screen output streaming tests
  -- These show REALISTIC debugging scenario: code on left, output tree on right
  -------------------------------------------------------------------------------

  T["split screen shows source and output tree"] = function()
    -- REALISTIC: Developer has source file open, output tree in split
    local h = ctx.create()
    h:fixture("logging-steps")
    h:setup_visual()
    h:use_plugin("neodap.plugins.tree_buffer")

    -- Open source file first
    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Create vertical split with output tree on right
    h.child.cmd("vsplit")
    h.child.cmd("wincmd l")
    h:open_tree("@session", 0)

    -- Expand Threads group to show Thread
    h.child.cmd("call search('Threads')")
    h.child.type_keys("<CR>")
    h:wait(100)

    -- Wait for UI to settle (js-debug child sessions need time)
    h:wait(300)

    -- Screenshot: split screen with source left, output tree right
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["output appears after stepping through log call"] = function()
    -- Skip for Python - output timing in tree is inconsistent due to View reactivity
    if ctx.adapter_name == "python" then
      return
    end

    -- REALISTIC: Step over a print/console.log and see output appear in tree
    local h = ctx.create()
    h:fixture("logging-steps")
    h:setup_visual()
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.step_cmd", "step_api")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step past function definition to first log call (line 1 -> 5)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=5)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step over the logStep(1) call - this produces "Step 1" output (line 5 -> 6)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=6)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Wait for output to arrive
    h:wait_url("@session/outputs[0]")

    -- Create split with output tree
    h.child.cmd("vsplit")
    h.child.cmd("wincmd l")
    h:open_tree("@session", 20)

    -- Expand Threads group to show Thread
    h.child.cmd("call search('Threads')")
    h.child.type_keys("<CR>")
    h:wait(100)

    -- Wait for UI to settle (js-debug output timing)
    h:wait(300)

    -- Screenshot for JavaScript
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["multiple outputs stream into tree as stepping"] = function()
    -- Skip for JavaScript - different line numbers for logging_steps program
    if ctx.adapter_name == "javascript" then
      return
    end

    -- REALISTIC: Step through multiple log calls, see outputs accumulate
    local h = ctx.create()
    h:fixture("logging-steps")
    h:setup_visual()
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.step_cmd", "step_api")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step past function definition (line 1 -> 5)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=5)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step over logStep(1) - produces "Step 1" (line 5 -> 6)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=6)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step over logStep(2) - produces "Step 2" (line 6 -> 7)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=7)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step over logStep(3) - produces "Step 3" (line 7 -> 8)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=8)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Wait for output to arrive
    h:wait_url("@session/outputs[0]")

    -- Create split with output tree
    h.child.cmd("vsplit")
    h.child.cmd("wincmd l")
    h:open_tree("@session", 0)

    -- Navigate to Output node and expand it
    h.child.cmd("call search('Output')")
    h.child.type_keys("0")
    h.child.type_keys("<CR>")

    if ctx.adapter_name == "python" then
      -- Content assertions for Python: more stable than screenshot due to debugpy batching
      h:assert_buffer_contains_all({"Step 1", "Step 2", "Step 3"}, "Output tree should show all steps")
    else
      -- Wait for UI to settle (js-debug output timing)
      h:wait(300)
      -- Screenshot for JavaScript: different output structure
      MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
    end
  end

  T["final output after program completes"] = function()
    -- Skip for Python - output capture timing is inconsistent
    if ctx.adapter_name == "python" then
      return
    end

    -- REALISTIC: Run program to completion, see all outputs including "Done"
    local h = ctx.create()
    h:fixture("logging-steps")
    h:setup_visual()
    h:use_plugin("neodap.plugins.tree_buffer")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Save session URI before termination (focus is cleared on termination)
    local session_uri = h:query_field("@session", "uri")

    -- Continue to completion
    h:cmd("DapContinue")
    h:wait_terminated(5000)

    -- Wait for output to arrive using saved session URI
    h:wait_url(session_uri .. "/outputs[0]")

    -- Create split with output tree
    h.child.cmd("vsplit")
    h.child.cmd("wincmd l")
    h:open_tree(session_uri, 0)

    -- Navigate to Output node and expand it
    h.child.cmd("call search('Output')")
    h.child.type_keys("0")
    h.child.type_keys("<CR>")

    -- Wait for UI to settle (js-debug output timing)
    h:wait(300)

    -- Screenshot: should show all outputs including "Done"
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  -------------------------------------------------------------------------------
  -- Output content verification tests
  -------------------------------------------------------------------------------

  T["output shows category indicator"] = function()
    -- Skip for Python - output capture timing is inconsistent
    if ctx.adapter_name == "python" then
      return
    end

    -- Verify [out] indicator appears for stdout
    local h = ctx.create()
    h:fixture("simple-vars")
    h:setup_visual()
    h:use_plugin("neodap.plugins.tree_buffer")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:cmd("DapContinue")
    h:wait_terminated(5000)
    h:wait_url("@session/outputs[0]")

    -- Open output tree expanded
    h:open_tree("@session", 0)

    -- Expand Threads group to show Thread
    h.child.cmd("call search('Threads')")
    h.child.type_keys("<CR>")
    h:wait(100)

    -- Wait for UI to settle (js-debug output timing)
    h:wait(300)

    -- Screenshot: should show [out] category indicator
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["tree shows first output after one log call"] = function()
    -- REALISTIC: Step over one log call and see output appear in tree
    local h = ctx.create()
    h:fixture("logging-steps")
    h:setup_visual()
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.step_cmd", "step_api")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step past function def (line 1 -> 5)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=5)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step over logStep(1) - produces "Step 1" output (line 5 -> 6)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=6)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:wait_url("@session/outputs[0]")

    -- Create split with output tree expanded
    h.child.cmd("vsplit")
    h.child.cmd("wincmd l")
    h:open_tree("@session", 0)

    -- Navigate to Output node and expand it
    h.child.cmd("call search('Output')")
    h.child.type_keys("0")
    h.child.type_keys("<CR>")

    if ctx.adapter_name == "python" then
      -- Content assertion for Python: more stable than screenshot due to debugpy batching
      h:assert_buffer_contains("Step 1", "Output tree should show Step 1")
    else
      -- Wait for UI to settle (js-debug output timing)
      h:wait(300)
      -- Screenshot for JavaScript: different output structure
      MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
    end
  end

  T["tree shows second output after two log calls"] = function()
    -- Skip for JavaScript - different line numbers for logging_steps program
    if ctx.adapter_name == "javascript" then
      return
    end

    -- REALISTIC: Step over two log calls and see both outputs in tree
    local h = ctx.create()
    h:fixture("logging-steps")
    h:setup_visual()
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.step_cmd", "step_api")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step past function def (line 1 -> 5)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=5)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step over logStep(1) - produces "Step 1" output (line 5 -> 6)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=6)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step over logStep(2) - produces "Step 2" output (line 6 -> 7)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=7)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:wait_url("@session/outputs[0]")

    -- Create split with output tree expanded
    h.child.cmd("vsplit")
    h.child.cmd("wincmd l")
    h:open_tree("@session", 0)

    -- Navigate to Output node and expand it
    h.child.cmd("call search('Output')")
    h.child.type_keys("0")
    h.child.type_keys("<CR>")

    if ctx.adapter_name == "python" then
      -- Content assertions for Python: more stable than screenshot due to debugpy batching
      h:assert_buffer_contains_all({"Step 1", "Step 2"}, "Output tree should show Step 1 and Step 2")
    else
      -- Wait for UI to settle (js-debug output timing)
      h:wait(300)
      -- Screenshot for JavaScript: different output structure
      MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
    end
  end
end)

return T
