-- Tests for tree_buffer (entity_buffer-based implementation)
-- Verifies dap://tree/<url> opens tree at correct root entity with reactive resolution
local harness = require("helpers.test_harness")

local T = harness.integration("tree_buffer", function(T, ctx)

  -- Test dap://tree/@debugger opens at debugger root
  T["@debugger opens at debugger root"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.tree_buffer")

    h:open_tree("@debugger")
    h:wait(2000)

    local first_line = h.child.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
    local bufname = h.child.api.nvim_buf_get_name(0)
    -- Root is hidden by default, so first line should be Breakpoints or Targets (children of debugger)
    MiniTest.expect.equality(first_line:match("Breakpoints") ~= nil or first_line:match("Targets") ~= nil, true)
    MiniTest.expect.equality(bufname:match("dap://tree/") ~= nil, true)
  end

  -- Test dap://tree/@session opens at focused session
  T["@session opens at focused session"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Use show_root to verify root entity is correct
    h:use_plugin("neodap.plugins.tree_buffer", { show_root = true })

    h:focus("@session")
    local session_name = h:query_field("@session", "name")

    h:open_tree("@session")
    h:wait(2000)

    local first_line = h.child.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
    local escaped_name = session_name:gsub("([%[%]%(%)%.%+%-%*%?%^%$%%])", "%%%1")
    MiniTest.expect.equality(first_line:match(escaped_name) ~= nil, true)
    MiniTest.expect.equality(first_line:match("^◉") ~= nil, true)
  end

  -- Test dap://tree/@frame opens at focused frame
  T["@frame opens at focused frame"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Use show_root to verify root entity is correct
    h:use_plugin("neodap.plugins.tree_buffer", { show_root = true })

    h:focus("@frame")
    local frame_name = h:query_field("@frame", "name")

    h:open_tree("@frame")
    h:wait(2000)

    local first_line = h.child.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
    MiniTest.expect.equality(first_line:match(frame_name) ~= nil, true)
  end

  -- Test dap://tree/@session/threads[0] opens at first thread
  T["@session/threads[0] opens at first thread"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Use show_root to verify root entity is correct
    h:use_plugin("neodap.plugins.tree_buffer", { show_root = true })

    -- Focus the first frame to establish session/thread context

    -- Verify thread can be resolved
    local thread_count = h:query_count("@session/threads")
    MiniTest.expect.equality(thread_count >= 1, true)

    h:open_tree("@session/threads[0]")
    h:wait(2000)

    -- Tree should show thread
    local first_line = h.child.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
    MiniTest.expect.equality(first_line:match("Thread") ~= nil, true)
  end

  -- Test sessions:group opens virtual Sessions group
  T["sessions:group opens sessions-only tree"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Use show_root to see the Sessions group header
    h:use_plugin("neodap.plugins.tree_buffer", { show_root = true })

    h:open_tree("sessions:group")
    h:wait(2000)

    -- Sessions is collapsed by default, expand it
    h.child.type_keys("<CR>")
    h:wait(100)

    local lines = h.child.api.nvim_buf_get_lines(0, 0, 3, false)
    local first_line = lines[1] or ""
    local second_line = lines[2] or ""
    local bufname = h.child.api.nvim_buf_get_name(0)
    MiniTest.expect.equality(bufname:match("dap://tree/") ~= nil, true)
    MiniTest.expect.equality(first_line:match("Sessions") ~= nil, true)
    -- Check for state icons: ⏸ (stopped/paused), ▶ (running/play), ⏹ (terminated/stop)
    MiniTest.expect.equality(second_line:match("⏸") ~= nil or second_line:match("▶") ~= nil or second_line:match("⏹") ~= nil, true)
  end

  -- Test breakpoints:group opens virtual Breakpoints group
  T["breakpoints:group opens breakpoints-only tree"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    -- Use show_root to see the Breakpoints group header
    h:use_plugin("neodap.plugins.tree_buffer", { show_root = true })
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 1")
    h:wait_url("/breakpoints(line=1)")

    h:open_tree("breakpoints:group")
    h:wait(500)

    -- Verify tree opens with Breakpoints group visible (collapsed by default)
    h:assert_buffer_contains("Breakpoints", "Breakpoints group should be visible")

    -- Expand the Breakpoints group (manual expand like Stdio)
    h.child.type_keys("<CR>")
    h:wait(500)

    -- Now breakpoints should be visible (file:line format)
    h:assert_buffer_contains("main", "Breakpoint file should be visible after expand")
  end

  -- NEW FEATURE TEST: Reactive root resolution
  -- When session focus changes, tree should update to show new session
  T["tree updates when session focus changes"] = function()
    local h = ctx.create()
    h:fixture("multi-session")

    -- Launch two debug sessions (program_a = simple_vars, program_b = logging_steps)
    h:cmd("DapLaunch Debug A stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:cmd("DapLaunch Debug B stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Get session info via URL queries (sessions are indexed in order of creation)
    local session1_uri = h:query_field("/sessions[0]", "uri")
    local session1_name = h:query_field("/sessions[0]", "name")
    local session2_uri = h:query_field("/sessions[1]", "uri")
    local session2_name = h:query_field("/sessions[1]", "name")

    -- Use show_root to verify root entity changes reactively
    h:use_plugin("neodap.plugins.tree_buffer", { show_root = true })

    -- Focus first session and open tree
    h:focus(session1_uri)

    h:open_tree("@session")
    h:wait(2000)

    local first_tree_line = h.child.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
    local escaped_name1 = session1_name:gsub("([%[%]%(%)%.%+%-%*%?%^%$%%])", "%%%1")
    MiniTest.expect.equality(first_tree_line:match(escaped_name1) ~= nil, true)

    -- Change focus to second session
    h:focus(session2_uri)
    h:wait(2000)

    local second_tree_line = h.child.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
    local escaped_name2 = session2_name:gsub("([%[%]%(%)%.%+%-%*%?%^%$%%])", "%%%1")

    -- Tree should now show session2 (REACTIVE!)
    MiniTest.expect.equality(second_tree_line:match(escaped_name2) ~= nil, true)
  end

  -- Test show_root config option shows root node (hidden by default)
  T["root is hidden by default"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Use tree_buffer with default config (root hidden)
    h:use_plugin("neodap.plugins.tree_buffer")

    h:open_tree("@debugger")
    h:wait(2000)

    local first_line = h.child.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""

    -- First line should NOT be Debugger (root is hidden by default)
    -- Should be Breakpoints or Targets instead (first child)
    MiniTest.expect.equality(first_line:match("Debugger") == nil, true,
      "Root node (Debugger) should be hidden by default")
    MiniTest.expect.equality(first_line:match("Breakpoints") ~= nil or first_line:match("Targets") ~= nil, true,
      "First line should be a child node (Breakpoints or Targets)")
  end

  -- Test show_root = true shows root node
  T["show_root option shows root node"] = function()
    local h = ctx.create()

    -- Use tree_buffer with show_root enabled
    h:use_plugin("neodap.plugins.tree_buffer", { show_root = true })

    h:open_tree("@debugger")
    h:wait(2000)

    local first_line = h.child.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""

    -- First line SHOULD be Debugger (root is shown)
    MiniTest.expect.equality(first_line:match("Debugger") ~= nil, true,
      "Root node (Debugger) should be visible with show_root = true")
  end

end)

return T
