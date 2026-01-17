-- Integration tests for Thread entity and stack behavior
local harness = require("helpers.test_harness")

return harness.integration("thread", function(T, ctx)
  -- ==========================================================================
  -- Thread State Tests (from test_neodap.lua)
  -- ==========================================================================

  T["Thread tracks state"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Thread should exist
    MiniTest.expect.equality(h:query_is_nil("@thread"), false)

    -- Thread should have state (stopped or running)
    local thread_state = h:query_field("@thread", "state")
    MiniTest.expect.equality(thread_state == "running" or thread_state == "stopped", true)

    -- Thread should have a name
    local thread_name = h:query_field("@thread", "name")
    MiniTest.expect.equality(thread_name ~= nil, true)

    -- Thread should have a threadId
    local thread_id = h:query_field("@thread", "threadId")
    MiniTest.expect.equality(thread_id ~= nil, true)

    -- Continue and verify session terminates
    h:cmd("DapContinue")
    h:wait_terminated(10000)
  end

  -- ==========================================================================
  -- Stack Rollup Tests (from test_latest_stack.lua)
  -- ==========================================================================

  T["stack rollup returns current stack"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- stack rollup should exist
    MiniTest.expect.equality(h:query_is_nil("@thread/stack"), false)

    -- stack should have frames
    MiniTest.expect.equality(h:query_count("@thread/stack/frames") > 0, true)
  end

  T["stack has frames"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Stack should have at least one frame (top frame)
    local frame_count = h:query_count("@thread/stack/frames")
    MiniTest.expect.equality(frame_count >= 1, true)

    -- topFrame rollup should exist
    MiniTest.expect.equality(h:query_is_nil("@thread/stack/topFrame"), false)
  end

  T["currentStack rollup matches stack"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- currentStack rollup should exist
    MiniTest.expect.equality(h:query_is_nil("@thread/currentStack"), false)

    -- currentStack and stack should be the same
    local current_stack_uri = h:query_uri("@thread/currentStack")
    local stack_uri = h:query_uri("@thread/stack")
    MiniTest.expect.equality(current_stack_uri, stack_uri)
  end

  -- ==========================================================================
  -- Stack Sorting Tests (from test_edge_sorting.lua)
  -- ==========================================================================

  T["stacks[0] is most recent stack"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step once to create a new stack (line 1 -> 2)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Get stack indices via URL
    local stack0_index = h:query_field("@thread/stacks[0]", "index")
    local stack1_index = h:query_field("@thread/stacks[1]", "index")

    -- Should have 2 stacks with indices 0 and 1
    MiniTest.expect.equality(stack0_index, 0)
    MiniTest.expect.equality(stack1_index, 1)

    -- stacks[0] should have lower index (more recent)
    MiniTest.expect.equality(stack0_index < stack1_index, true)
  end

  T["stacks[0]/frames[0] navigates to top frame of latest stack"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Get frame URI via stacks edge navigation
    local frame_via_stacks = h:query_uri("@thread/stacks[0]/frames[0]")

    -- Get frame URI via stack rollup (one-to-one)
    local frame_via_stack = h:query_uri("@thread/stack/frames[0]")

    -- Both should exist
    MiniTest.expect.equality(frame_via_stacks ~= nil, true)
    MiniTest.expect.equality(frame_via_stack ~= nil, true)

    -- Both methods should return the same frame
    MiniTest.expect.equality(frame_via_stacks, frame_via_stack)
  end
end)
