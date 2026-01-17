local harness = require("helpers.test_harness")

local T = harness.integration("tree_buffer_visual", function(T, ctx)
  T["renders debugger tree with session"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:open_tree("@debugger")
    -- Wait for UI to settle (js-debug child session timing)
    h:wait(300)
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["renders expanded session with threads"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:open_tree("@session")
    -- Wait for UI to settle (js-debug child session timing)
    h:wait(300)
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["renders stack frames and scopes"] = function()
    -- Skip for JavaScript - js-debug bootstrap and breakpoint sync timing causes timeouts
    if ctx.adapter_name == "javascript" then
      return
    end

    local h = ctx.create()
    h:fixture("with-function")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Set breakpoint inside the function and continue to it (line 2)
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    h:cmd("DapContinue")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")

    h:open_tree("@frame")
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["renders variables with values"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step to define variables (line 1 -> 2 -> 3)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=3)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")

    h:focus("@frame")
    h:open_tree("@frame")
    -- Wait for UI to settle
    h:wait(300)
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  --
  -- Breakpoint rendering tests
  --

  T["renders breakpoint in debugger tree"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    h:open_tree("@debugger")
    -- Wait for UI to settle
    h:wait(300)
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["renders conditional breakpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")
    h:cmd("DapBreakpoint condition 2 x == 5")

    h:open_tree("@debugger")
    -- Wait for UI to settle
    h:wait(300)
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["renders logpoint"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 1")
    h:wait_url("/breakpoints(line=1)")
    h:cmd("DapBreakpoint log 1 x value is {x}")

    h:open_tree("@debugger")
    -- Wait for UI to settle
    h:wait(300)
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["renders multiple breakpoints"] = function()
    local h = ctx.create()
    h:fixture("multi-file")

    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    -- Add breakpoint on file1, line 2
    h:edit_file("file1")
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    -- Add breakpoints on file2, line 1 and line 2 with condition
    h:edit_file("file2")
    h:cmd("DapBreakpoint 1")
    h:wait(50)
    h:cmd("DapBreakpoint 2")
    h:wait(50)
    h:cmd("DapBreakpoint condition 2 x > 0")

    h:open_tree("@debugger")
    -- Wait for UI to settle
    h:wait(300)
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["renders breakpoint binding when verified"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Add and sync breakpoint
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Wait for child session thread to be fully populated (js-debug timing)
    h:wait(500)
    h:open_tree("@debugger")

    -- Wait for tree to show Thread (js-debug child session propagation)
    h:wait(3000)

    -- Navigate to the breakpoint (under Breakpoints group) and expand it
    -- Line 2 should be the breakpoint (line 1 is Breakpoints group)
    h.child.cmd("normal! 2G")
    h:wait(100)
    h.child.type_keys("<CR>")
    -- Wait for bindings to load (not eager, requires expand)
    h:wait(500)

    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["renders outputs in expanded Output node"] = function()
    local h = ctx.create()
    -- simple_vars produces console output via console.log/print
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Store session ID before termination (focus will be cleared)
    local session_id = h:query_field("@session", "sessionId")

    -- Continue to let console.log run and produce output
    h:cmd("DapContinue")
    h:wait_terminated(5000)

    -- Wait for outputs to be captured
    h:wait(500)

    -- Open tree at session level to see Output node
    -- Use key lookup since focus is cleared on termination
    h:open_tree("/sessions:" .. session_id, 0)

    -- Navigate to Output node (should be last item) and expand it
    h.child.type_keys("G")
    h.child.type_keys("<CR>")
    h:wait(100)

    -- Verify child didn't crash and tree expanded (line count > 2)
    assert(h.child.is_running(), "Child should not crash")
    local lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)
    -- Count non-empty, non-tilde lines (actual tree content)
    local content_lines = 0
    for _, line in ipairs(lines) do
      if line ~= "" and not line:match("^~") and not line:match("^dap://tree/") then
        content_lines = content_lines + 1
      end
    end
    assert(content_lines >= 2, "Expected tree with outputs, got " .. content_lines .. " content lines")
  end

  T["toggling Output node does not crash"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Store session ID before termination (focus will be cleared)
    local session_id = h:query_field("@session", "sessionId")

    -- Continue to produce output
    h:cmd("DapContinue")
    h:wait_terminated(5000)
    h:wait(500)

    -- Open tree at session level
    -- Use key lookup since focus is cleared on termination
    h:open_tree("/sessions:" .. session_id, 0)

    -- Navigate to Output node and press Enter multiple times
    -- Output node uses virtual hop so it's not collapsible, just stays expanded
    h.child.type_keys("G")
    h.child.type_keys("<CR>")
    h:wait(100)
    h.child.type_keys("<CR>")
    h:wait(100)

    -- Verify child didn't crash
    assert(h.child.is_running(), "Child crashed during Output node toggle")
  end

  T["thread stacks edge can be toggled"] = function()
    -- Thread has stacks edge (eager, visible) - Stack nodes appear under Thread
    -- Stack has frames edge (not eager) - frames show on manual expand
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Open tree at debugger level
    h:open_tree("@debugger")
    h:wait(300)

    -- Navigate to Threads group (under Targets/Session) and expand it
    h.child.cmd("call search('Threads')")
    h.child.type_keys("<CR>")  -- Expand Threads to show Thread
    h:wait(100)

    -- Navigate to Thread and toggle twice
    h.child.cmd("call search('Thread \\\\d')")  -- Match "Thread 0:" or "Thread 17:"
    h.child.type_keys("0")
    h.child.type_keys("<CR>")  -- First toggle: collapse stacks
    h:wait(100)
    h.child.type_keys("<CR>")  -- Second toggle: expand stacks again
    h:wait(200)

    -- Screenshot: Thread should show Stack [0] underneath (stacks edge expanded)
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["debugger tree with full hierarchy"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    -- Use show_root to show full hierarchy from Debugger down
    h:use_plugin("neodap.plugins.tree_buffer", { show_root = true })
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Open tree at debugger root
    h:open_tree("@debugger")
    h:wait(300)

    -- Expand Threads group to show Thread
    h.child.cmd("call search('Threads')")
    h.child.type_keys("<CR>")
    h:wait(100)

    -- Expand Thread to show Stack
    h.child.cmd("call search('Thread \\\\d')")
    h.child.type_keys("<CR>")
    h:wait(100)

    -- Expand Stack [0] to show Frames
    h.child.cmd("call search('Stack')")
    h.child.type_keys("<CR>")
    h:wait(200)

    -- Screenshot: Debugger tree showing full hierarchy from Debugger to Frames
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["frame tree with scopes and variables"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer", { show_root = true })
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step to define variables (line 1 -> 2 -> 3)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=3)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Fetch scopes and variables for all scopes
    -- Note: scope order varies by adapter (Local may be index 0 or 1)
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")

    -- Fetch variables for Local scope (first scope with meaningful variables)
    -- Try both indices to ensure we get Local variables
    local scope_count = h:query_count("@frame/scopes")
    for i = 0, scope_count - 1 do
      h:query_call("@frame/scopes[" .. i .. "]", "fetchVariables")
    end
    h:wait(100)

    -- Open tree at frame level - shows frame with scopes and variables
    h:open_tree("@frame")
    h:wait(200)

    -- Expand Local scope (line 2) to show variables
    h.child.type_keys("2gg")
    h.child.type_keys("<CR>")
    h:wait(200)

    -- Screenshot: Frame tree showing scopes expanded with variables
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["debugger tree with multiple stack frames"] = function()
    local h = ctx.create()
    h:fixture("with-function")
    h:use_plugin("neodap.plugins.tree_buffer", { show_root = true })
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    -- Set breakpoint inside inner() function (line 2)
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    -- Launch and run to breakpoint inside inner()
    -- Call stack will be: inner() -> outer() -> <module>
    h:cmd("DapLaunch Debug")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Open tree at thread level - shows Stack with frames directly
    h:open_tree("@thread")
    h:wait(300)

    -- Expand Stack [0] to show all frames (inner, outer, <module>)
    h.child.cmd("call search('Stack')")
    h.child.type_keys("0")     -- Go to start of line
    h.child.type_keys("<CR>")  -- Expand Stack [0]
    h:wait(200)

    -- Screenshot: Shows multiple stack frames (inner, outer, <module>)
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["global scope virtualisation on scroll"] = function()
    -- JavaScript only - global scope has many built-in variables
    if ctx.adapter_name ~= "javascript" then
      return
    end

    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Fetch scopes and global variables
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")

    -- Find and fetch the Global scope (usually index 1 in JS)
    local scope_count = h:query_count("@frame/scopes")
    local global_scope_idx = nil
    for i = 0, scope_count - 1 do
      local scope_name = h:query_field("@frame/scopes[" .. i .. "]", "name")
      if scope_name and scope_name:match("Global") then
        h:query_call("@frame/scopes[" .. i .. "]", "fetchVariables")
        global_scope_idx = i
        break
      end
    end

    -- Wait for global variables to be loaded
    if global_scope_idx then
      h:wait_url("@frame/scopes[" .. global_scope_idx .. "]/variables[0]")
    end
    h:wait(200)

    -- Open tree at scope level (Global scope directly) to see variables
    h:open_tree("@frame/scopes[" .. global_scope_idx .. "]")
    h:wait(500)

    -- Scroll down to show virtualization (many global variables)
    for _ = 1, 6 do
      h.child.type_keys("<C-d>")
      h:wait(50)
    end
    h:wait(200)

    -- Screenshot: Shows middle of global scope with virtualized content
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })

    -- Go to end of buffer
    h.child.type_keys("G")
    h:wait(200)

    -- Screenshot: Shows end of global scope
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end
end)

return T
