local harness = require("helpers.test_harness")

return harness.integration("dap_cmd", function(T, ctx)
  -- ============================================================================
  -- Quickfix Builder Tests
  -- ============================================================================

  T["Dap list breakpoints populates quickfix with valid entries"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:use_plugin("neodap.plugins.command_router")
    h:use_plugin("neodap.plugins.list_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")

    -- Use Dap list command to populate quickfix
    h:cmd("Dap list breakpoints")

    -- Get the first quickfix entry and check it has expected fields
    local entry = h.child.fn.getqflist()[1]
    MiniTest.expect.equality(entry.filename ~= nil or entry.bufnr ~= nil, true)
    MiniTest.expect.equality(entry.lnum, 2)
    MiniTest.expect.equality(entry.text:match("verified") ~= nil, true)
    MiniTest.expect.equality(entry.user_data ~= nil, true)
  end

  T["Dap list threads populates quickfix with valid entries"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.command_router")
    h:use_plugin("neodap.plugins.list_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Use Dap list command to populate quickfix with threads
    h:cmd("Dap list /sessions/threads")

    local qf = h.child.fn.getqflist()
    MiniTest.expect.equality(#qf >= 1, true)

    local entry = qf[1]
    MiniTest.expect.equality(entry ~= nil, true)

    -- Thread entry has no filename (threads don't have source locations)
    MiniTest.expect.equality(entry.filename == nil or entry.filename == "", true)

    -- Check text contains thread info
    MiniTest.expect.equality(entry.text ~= nil, true)
  end

  -- ============================================================================
  -- List Command Tests
  -- ============================================================================

  T["list populates quickfix with breakpoints"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:use_plugin("neodap.plugins.command_router")
    h:use_plugin("neodap.plugins.list_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:cmd("DapBreakpoint 10")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")
    h:wait_url("/breakpoints(line=10)/bindings(verified=true)")

    -- Use :Dap list which delegates to :DapList
    h:cmd("Dap list breakpoints")

    local qf_count = #h.child.fn.getqflist()
    MiniTest.expect.equality(qf_count, 2)
  end

  T["list with filter populates quickfix correctly"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:use_plugin("neodap.plugins.command_router")
    h:use_plugin("neodap.plugins.list_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:cmd("DapBreakpoint 10")
    h:wait_url("/breakpoints(line=2)/bindings(verified=true)")
    h:wait_url("/breakpoints(line=10)/bindings(verified=true)")

    -- Disable breakpoint at line 2
    h:cmd("DapBreakpoint disable 2")
    h:wait_url("/breakpoints(enabled=false)")

    -- Use :Dap list with filter to only list enabled breakpoints
    h:cmd("Dap list breakpoints(enabled=true)")

    local qf_count = #h.child.fn.getqflist()
    MiniTest.expect.equality(qf_count, 1)
  end

  -- ============================================================================
  -- Dap<Command> Delegation Tests
  -- ============================================================================

  T["Dap delegates to DapJump when it exists"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.command_router")
    h:use_plugin("neodap.plugins.jump_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Get expected location from frame
    local expected_file = h:query_field("@frame/source[0]", "path")
    local expected_line = h:query_field("@frame", "line")

    -- Use :Dap jump which should delegate to :DapJump
    h:cmd("Dap jump @frame")

    local current_file = h.child.api.nvim_buf_get_name(0)
    local current_line = h.child.api.nvim_win_get_cursor(0)[1]

    MiniTest.expect.equality(current_file, expected_file)
    MiniTest.expect.equality(current_line, expected_line)
  end

  T["Dap jump @frame+1 delegates and navigates to caller"] = function()
    local h = ctx.create()
    h:fixture("with-function")
    h:use_plugin("neodap.plugins.command_router")
    h:use_plugin("neodap.plugins.jump_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Test if we have multiple frames
    local frame_count = h:query_count("@thread/stack/frames")
    if frame_count >= 2 then
      h:cmd("Dap jump @frame+1")
    end
  end
end)
