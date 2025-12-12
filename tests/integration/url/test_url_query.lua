-- Integration tests for debugger:query(url) - URL resolution to entity collections
-- Tests follow URL_COMPLIANCE.md specification
local harness = require("helpers.test_harness")

local T = harness.integration("url_query", function(T, ctx)
  -- ============================================================================
  -- Group 1: URL Type × Accessor Type (1.1-1.4: Absolute URLs)
  -- ============================================================================

  T["1.1 absolute bare edge /sessions returns collection"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("/sessions"), true)
    MiniTest.expect.equality(h:query_count("/sessions") >= 1, true)
    MiniTest.expect.equality(h:query_type("/sessions"), "Session")
  end

  T["1.2 absolute key /sessions:id returns single or nil"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Key lookup with valid ID returns matching session
    MiniTest.expect.equality(h:query_session_by_key_matches("/sessions"), true)

    -- Non-existent key returns nil
    MiniTest.expect.equality(h:query_is_nil("/sessions:nonexistent_key_12345"), true)
  end

  T["1.3 absolute filter /breakpoints(enabled=true) returns collection"] = function()
    -- Skip for JavaScript - multiple breakpoint sync causes timeouts
    if ctx.adapter_name == "javascript" then
      return
    end

    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Create mix of enabled/disabled breakpoints
    h:edit_main()
    h:cmd("DapBreakpoint 5")
    h:wait_url("/breakpoints(line=5)/bindings(verified=true)")
    h:cmd("DapBreakpoint 10")
    h:wait_url("/breakpoints(line=10)/bindings(verified=true)")
    -- Disable the second breakpoint
    h:cmd("DapBreakpoint disable 10")
    h:wait_url("/breakpoints(line=10,enabled=false)")

    -- Verify total breakpoints
    MiniTest.expect.equality(h:query_count("/breakpoints"), 2)

    -- Filter by enabled state
    MiniTest.expect.equality(h:query_is_table("/breakpoints(enabled=true)"), true)
    MiniTest.expect.equality(h:query_is_table("/breakpoints(enabled=false)"), true)
    MiniTest.expect.equality(h:query_count("/breakpoints(enabled=true)"), 1)
    MiniTest.expect.equality(h:query_count("/breakpoints(enabled=false)"), 1)
  end

  T["1.4 absolute index on sorted edge returns single or nil"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Index syntax only works on edges with sort defined in schema (stacks, frames, outputs)
    MiniTest.expect.equality(h:query_type("@thread/stacks[0]"), "Stack")
    MiniTest.expect.equality(h:query_is_nil("@thread/stacks[999]"), true)
  end

  -- ============================================================================
  -- Group 1 (continued): Contextual URLs (1.5-1.11)
  -- ============================================================================

  T["1.5 @session/threads returns threads in focused session"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("@session/threads"), true)
    MiniTest.expect.equality(h:query_count("@session/threads") >= 1, true)
    MiniTest.expect.equality(h:query_type("@session/threads"), "Thread")
  end

  T["1.6 @session/threads:id returns single thread"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local thread_id = h:query_field("@session/threads[0]", "threadId")
    MiniTest.expect.equality(thread_id ~= nil, true)
    MiniTest.expect.equality(h:query_type("@session/threads:" .. thread_id), "Thread")
  end

  T["1.7 @session/threads(state=stopped) returns filtered threads"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("@session/threads(state=stopped)"), true)
    MiniTest.expect.equality(h:query_count("@session/threads(state=stopped)") >= 1, true)
    MiniTest.expect.equality(h:query_all_type("@session/threads(state=stopped)", "Thread"), true)
  end

  T["1.8 @session/threads[0] returns first thread"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_type("@session/threads[0]"), "Thread")
    MiniTest.expect.equality(h:query_matches_first("@session/threads[0]", "@session/threads"), true)
  end

  T["1.9 @thread/stack/frames returns frames"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("@thread/stack/frames"), true)
    MiniTest.expect.equality(h:query_count("@thread/stack/frames") >= 1, true)
    MiniTest.expect.equality(h:query_type("@thread/stack/frames"), "Frame")
  end

  T["1.10 @frame/scopes returns scopes"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")

    MiniTest.expect.equality(h:query_is_table("@frame/scopes"), true)
    MiniTest.expect.equality(h:query_count("@frame/scopes") >= 1, true)
    MiniTest.expect.equality(h:query_type("@frame/scopes"), "Scope")
  end

  T["1.11 @debugger/breakpoints returns all breakpoints"] = function()
    -- Skip for JavaScript - multiple breakpoint sync causes timeouts
    if ctx.adapter_name == "javascript" then
      return
    end

    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 5")
    h:wait_url("/breakpoints(line=5)/bindings(verified=true)")
    h:cmd("DapBreakpoint 10")
    h:wait_url("/breakpoints(line=10)/bindings(verified=true)")

    MiniTest.expect.equality(h:query_is_table("@debugger/breakpoints"), true)
    MiniTest.expect.equality(h:query_count("@debugger/breakpoints"), 2)
    MiniTest.expect.equality(h:query_type("@debugger/breakpoints"), "Breakpoint")
  end

  T["1.12 @frame+1 returns caller frame"] = function()
    local h = ctx.create()
    h:fixture("with-function")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Focus the innermost frame (index 0)
    
    -- Get frame count to know if we have a call stack
    local frame_count = h:query_count("@thread/stack/frames")
    if frame_count >= 2 then
      -- @frame+1 should return the caller frame (index 1)
      MiniTest.expect.equality(h:query_type("@frame+1"), "Frame")
      MiniTest.expect.equality(h:query_is_nil("@frame+1"), false)
    end
  end

  T["1.13 @frame-1 out of bounds returns nil"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- @frame-1 from index 0 should be out of bounds
    MiniTest.expect.equality(h:query_is_nil("@frame-1"), true)
  end

  T["1.14 @frame+999 out of bounds returns nil"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- @frame+999 should be out of bounds
    MiniTest.expect.equality(h:query_is_nil("@frame+999"), true)
  end

  T["1.15 @frame+1/scopes traverses from caller frame"] = function()
    local h = ctx.create()
    h:fixture("with-function")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Get frame count to know if we have a call stack
    local frame_count = h:query_count("@thread/stack/frames")
    if frame_count >= 2 then
      -- Fetch scopes for the caller frame
      h:query_call("@frame+1", "fetchScopes")
      h:wait_url("@frame+1/scopes[0]")

      -- @frame+1/scopes should return scopes from caller frame
      MiniTest.expect.equality(h:query_is_table("@frame+1/scopes"), true)
      MiniTest.expect.equality(h:query_type("@frame+1/scopes"), "Scope")
    end
  end

  -- ============================================================================
  -- Group 2: Segment Depth Tests
  -- ============================================================================

  T["2.1 depth 1 /sessions works"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("/sessions"), true)
    MiniTest.expect.equality(h:query_count("/sessions") >= 1, true)
  end

  T["2.2 depth 2 @session/threads works"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("@session/threads"), true)
    MiniTest.expect.equality(h:query_count("@session/threads") >= 1, true)
  end

  T["2.3 depth 3+ @thread/stack/frames works"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("@thread/stack/frames"), true)
    MiniTest.expect.equality(h:query_count("@thread/stack/frames") >= 1, true)
  end

  T["2.4 depth 2 contextual @session/threads works"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("@session/threads"), true)
    MiniTest.expect.equality(h:query_count("@session/threads") >= 1, true)
  end

  T["2.5 depth 3+ contextual @session/threads/stack/frames works"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("@session/threads/stack/frames"), true)
    MiniTest.expect.equality(h:query_count("@session/threads/stack/frames") >= 1, true)
    MiniTest.expect.equality(h:query_type("@session/threads/stack/frames"), "Frame")
  end

  -- ============================================================================
  -- Group 3: Filter Value Types
  -- ============================================================================

  T["3.1 filter boolean true /breakpoints(enabled=true)"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 5")
    h:wait_url("/breakpoints(line=5)/bindings(verified=true)")

    MiniTest.expect.equality(h:query_is_table("/breakpoints(enabled=true)"), true)
    MiniTest.expect.equality(h:query_count("/breakpoints(enabled=true)"), 1)
  end

  T["3.2 filter boolean false /breakpoints(enabled=false)"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 5")
    h:wait_url("/breakpoints(line=5)/bindings(verified=true)")
    h:cmd("DapBreakpoint disable 5")
    h:wait_url("/breakpoints(line=5,enabled=false)")

    MiniTest.expect.equality(h:query_is_table("/breakpoints(enabled=false)"), true)
    MiniTest.expect.equality(h:query_count("/breakpoints(enabled=false)"), 1)
  end

  T["3.3 filter number @session/threads(threadId=N)"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local thread_id = h:query_field("@session/threads[0]", "threadId")
    MiniTest.expect.equality(thread_id ~= nil, true)

    local url = "@session/threads(threadId=" .. tostring(thread_id) .. ")"
    MiniTest.expect.equality(h:query_is_table(url), true)
    MiniTest.expect.equality(h:query_count(url), 1)
  end

  T["3.4 filter string bare /sessions(state=stopped)"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("/sessions(state=stopped)"), true)
    MiniTest.expect.equality(h:query_count("/sessions(state=stopped)") >= 1, true)
  end

  T["3.5 filter quoted string /breakpoints(condition=quoted)"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint condition 5 x > 10")
    h:wait_url("/breakpoints(line=5)/bindings(verified=true)")

    MiniTest.expect.equality(h:query_is_table('/breakpoints(condition="x > 10")'), true)
    MiniTest.expect.equality(h:query_count('/breakpoints(condition="x > 10")'), 1)
  end

  -- ============================================================================
  -- Group 4: Result Cardinality
  -- ============================================================================

  T["4.1 empty collection for no matches /sessions(state=exploding)"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("/sessions(state=exploding)"), true)
    MiniTest.expect.equality(h:query_count("/sessions(state=exploding)"), 0)
  end

  T["4.2 single entity for key lookup /sessions:id"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_session_by_key_matches("/sessions"), true)
    local session_id = h:query_field("/sessions[0]", "sessionId")
    MiniTest.expect.equality(h:query_is_entity("/sessions:" .. session_id), true)
  end

  T["4.3 multiple entities /breakpoints returns collection"] = function()
    -- Skip for JavaScript - multiple breakpoint sync causes timeouts
    if ctx.adapter_name == "javascript" then
      return
    end

    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 5")
    h:wait_url("/breakpoints(line=5)/bindings(verified=true)")
    h:cmd("DapBreakpoint 10")
    h:wait_url("/breakpoints(line=10)/bindings(verified=true)")
    h:cmd("DapBreakpoint 15")
    h:wait_url("/breakpoints(line=15)/bindings(verified=true)")

    MiniTest.expect.equality(h:query_is_table("/breakpoints"), true)
    MiniTest.expect.equality(h:query_count("/breakpoints"), 3)
  end

  T["4.4 nil for nonexistent key /sessions:nonexistent"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_nil("/sessions:nonexistent_session_id_12345"), true)
  end

  T["4.5 nil for out of bounds index on sorted edge"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Index syntax only works on edges with sort defined in schema
    MiniTest.expect.equality(h:query_is_nil("@thread/stacks[999]"), true)
  end

  -- ============================================================================
  -- Group 5: Edge Cardinality
  -- ============================================================================

  T["5.1 one-to-many flattens @session/threads"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("@session/threads"), true)
    MiniTest.expect.equality(h:query_count("@session/threads") >= 1, true)
  end

  T["5.2 one-to-one @thread/stack"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- stack is a reference rollup, returns single entity (not collection)
    MiniTest.expect.equality(h:query_is_nil("@thread/stack"), false)
    MiniTest.expect.equality(h:query_type("@thread/stack"), "Stack")
  end

  T["5.3 mixed edges /sessions/threads/stack flattens"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("/sessions/threads/stack"), true)
    MiniTest.expect.equality(h:query_count("/sessions/threads/stack") >= 1, true)
    MiniTest.expect.equality(h:query_all_type("/sessions/threads/stack", "Stack"), true)
  end

  T["5.4 one-to-one chain @frame/source"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Source is one-to-one, should return collection with 0 or 1 Source items
    MiniTest.expect.equality(h:query_frame_source_valid(), true)
  end

  -- ============================================================================
  -- Group 6: Accessor Chaining
  -- ============================================================================

  T["6.1 single filter /breakpoints(enabled=true)"] = function()
    -- Skip for JavaScript - multiple breakpoint sync causes timeouts
    if ctx.adapter_name == "javascript" then
      return
    end

    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 5")
    h:wait_url("/breakpoints(line=5)/bindings(verified=true)")
    h:cmd("DapBreakpoint 10")
    h:wait_url("/breakpoints(line=10)/bindings(verified=true)")
    h:cmd("DapBreakpoint disable 10")
    h:wait_url("/breakpoints(line=10,enabled=false)")

    MiniTest.expect.equality(h:query_count("/breakpoints(enabled=true)"), 1)
  end

  T["6.2 filter + index /sessions(state=stopped)[0]"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_type("/sessions(state=stopped)[0]"), "Session")
    MiniTest.expect.equality(h:query_field("/sessions(state=stopped)[0]", "state"), "stopped")
  end

  T["6.3 multiple filters /breakpoints(enabled=true,line=5)"] = function()
    -- Skip for JavaScript - multiple breakpoint sync causes timeouts
    if ctx.adapter_name == "javascript" then
      return
    end

    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Create breakpoints at different lines
    h:edit_main()
    h:cmd("DapBreakpoint 5")
    h:wait_url("/breakpoints(line=5)/bindings(verified=true)")
    h:cmd("DapBreakpoint 10")
    h:wait_url("/breakpoints(line=10)/bindings(verified=true)")

    MiniTest.expect.equality(h:query_is_table("/breakpoints(enabled=true,line=5)"), true)
    MiniTest.expect.equality(h:query_count("/breakpoints(enabled=true,line=5)"), 1)
    MiniTest.expect.equality(h:query_field("/breakpoints(enabled=true,line=5)[0]", "line"), 5)
  end

  T["6.4 filter on final segment with flattening @session/threads(state=stopped)[0]"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_type("@session/threads(state=stopped)[0]"), "Thread")
    MiniTest.expect.equality(h:query_field("@session/threads(state=stopped)[0]", "state"), "stopped")
  end

  -- ============================================================================
  -- Group 7: Flattening Behavior
  -- ============================================================================

  T["7.1 flattening collects all entities /sessions/threads"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")

    -- Use wait_url to properly wait for URL resolution
    local ok = h:wait_url("/sessions/threads")
    MiniTest.expect.equality(ok, true)

    MiniTest.expect.equality(h:query_is_table("/sessions/threads"), true)
    MiniTest.expect.equality(h:query_count("/sessions/threads") >= 1, true)
    MiniTest.expect.equality(h:query_all_type("/sessions/threads", "Thread"), true)
  end

  T["7.2 index on sorted edge then traverse stacks[0]/frames"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Use wait_url for proper URL resolution with context
    local ok = h:wait_url("@thread/stacks[0]/frames")
    MiniTest.expect.equality(ok, true)

    -- Index works on sorted edges (stacks has sort by index)
    MiniTest.expect.equality(h:query_count("@thread/stacks[0]/frames") >= 1, true)
    MiniTest.expect.equality(h:query_all_type("@thread/stacks[0]/frames", "Frame"), true)
  end

  T["7.3 index on sorted edge frames[0]"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Index works on sorted edges (frames has sort by index)
    MiniTest.expect.equality(h:query_type("@thread/stacks[0]/frames[0]"), "Frame")
  end

  T["7.4 index chain on sorted edges stacks[0]/frames[0]"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Chain of indices on sorted edges (stacks and frames both have sort by index)
    MiniTest.expect.equality(h:query_type("@thread/stacks[0]/frames[0]"), "Frame")
  end

  T["7.5 deep flattening /sessions/threads/stack/frames"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("/sessions/threads/stack/frames"), true)
    MiniTest.expect.equality(h:query_count("/sessions/threads/stack/frames") >= 1, true)
    MiniTest.expect.equality(h:query_all_type("/sessions/threads/stack/frames", "Frame"), true)
  end

  -- ============================================================================
  -- Group 9: Error Cases (parser validation)
  -- ============================================================================

  T["9.1 root path returns debugger"] = function()
    local h = ctx.create()
    -- "/" returns the debugger entity (same as @debugger per URL_SPEC)
    MiniTest.expect.equality(h:query_type("/"), "Debugger")
  end

  T["9.2 unclosed filter returns nil or error"] = function()
    local h = ctx.create()
    MiniTest.expect.equality(h:query_is_nil_or_empty("/sessions("), true)
  end

  T["9.3 unclosed index returns nil or error"] = function()
    local h = ctx.create()
    MiniTest.expect.equality(h:query_is_nil_or_empty("/sessions["), true)
  end

  T["9.4 missing field name (=value) returns nil or error"] = function()
    local h = ctx.create()
    MiniTest.expect.equality(h:query_is_nil_or_empty("/sessions(=value)"), true)
  end

  T["9.5 missing value (field=) returns nil or error"] = function()
    local h = ctx.create()
    MiniTest.expect.equality(h:query_is_nil_or_empty("/sessions(field=)"), true)
  end

  T["9.6 non-numeric index returns nil or error"] = function()
    local h = ctx.create()
    MiniTest.expect.equality(h:query_is_nil_or_empty("/sessions[abc]"), true)
  end

  T["9.7 unknown edge returns nil or empty"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_nil_or_empty("/nonexistent_edge"), true)
  end

  T["9.8 unknown focus @invalid returns nil"] = function()
    local h = ctx.create()
    MiniTest.expect.equality(h:query_is_nil("@invalid"), true)
  end

  T["9.9 empty segment //sessions returns nil or error"] = function()
    local h = ctx.create()
    -- Empty segment at start should fail
    MiniTest.expect.equality(h:query_is_nil_or_empty("//sessions"), true)
  end

  -- ============================================================================
  -- Hotspot Tests: Complex Scenarios
  -- ============================================================================

  T["H1.3 deep traversal with index /sessions/threads/stack/frames[0]"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_type("/sessions/threads/stack/frames[0]"), "Frame")
    MiniTest.expect.equality(
      h:query_matches_first("/sessions/threads/stack/frames[0]", "/sessions/threads/stack/frames"),
      true
    )
  end

  T["H2.1 contextual with filter and index @session/threads(state=stopped)[0]/stack/frames"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Complex query: get first stopped thread, then its frames
    local url = "@session/threads(state=stopped)[0]/stack/frames"
    MiniTest.expect.equality(h:query_is_table(url), true)
    MiniTest.expect.equality(h:query_count(url) >= 1, true)
    MiniTest.expect.equality(h:query_all_type(url, "Frame"), true)
  end

  T["H5.1 empty filter propagates /sessions(state=exploding)/threads returns empty"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("/sessions(state=exploding)/threads"), true)
    MiniTest.expect.equality(h:query_count("/sessions(state=exploding)/threads"), 0)
  end

  T["H5.2 filter at deep level returns empty /sessions/threads(state=exploding)"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_table("/sessions/threads(state=exploding)"), true)
    MiniTest.expect.equality(h:query_count("/sessions/threads(state=exploding)"), 0)
  end

  T["H5.4 index after empty filter returns nil /sessions(state=exploding)[0]"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_is_nil("/sessions(state=exploding)[0]"), true)
  end

  T["H5.5 index OOB on sorted edge returns empty"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Out of bounds index filters to 0 stacks, so frames returns empty array
    MiniTest.expect.equality(h:query_count("@thread/stacks[999]/frames"), 0)
  end

  T["H5.6 filter+index chain with no matches returns nil"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Filter for non-existent state, then try to index -> nil
    MiniTest.expect.equality(h:query_is_nil("/sessions/threads(state=exploding)[0]"), true)
  end

  T["H3.1 one-to-one stack in chain /sessions/threads/stack/frames[0]"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    MiniTest.expect.equality(h:query_type("/sessions/threads/stack/frames[0]"), "Frame")
    MiniTest.expect.equality(
      h:query_matches_first("/sessions/threads/stack/frames[0]", "/sessions/threads/stack/frames"),
      true
    )
  end

  T["H2.4 deep index chain @session/threads[0]/stack/frames[0]/scopes[0]"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@session/threads[0]/stack/frames[0]", "fetchScopes")
    h:wait_url("@session/threads[0]/stack/frames[0]/scopes[0]")

    local scope_url = "@session/threads[0]/stack/frames[0]/scopes[0]"
    local scopes_url = "@session/threads[0]/stack/frames[0]/scopes"
    MiniTest.expect.equality(h:query_type(scope_url), "Scope")
    MiniTest.expect.equality(h:query_matches_first(scope_url, scopes_url), true)
  end

  T["H8.1 flat variables @frame/scopes/variables"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")

    -- Use wait_url for proper URL resolution
    local ok = h:wait_url("@frame/scopes/variables")
    MiniTest.expect.equality(ok, true)

    MiniTest.expect.equality(h:query_count("@frame/scopes/variables") >= 1, true)
    MiniTest.expect.equality(h:query_all_type("@frame/scopes/variables", "Variable"), true)
  end

  -- ============================================================================
  -- wait_url helper tests (from test_wait_url.lua)
  -- ============================================================================

  T["wait_url resolves after stopped event"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")

    -- Just wait for the frame to exist (auto-fetch handles it)
    -- Use absolute URL (no context needed)
    local ok = h:wait_url("/sessions/threads/stack/frames[0]")
    MiniTest.expect.equality(ok, true)

    -- Frame should now be queryable
    MiniTest.expect.equality(h:query_type("/sessions/threads/stack/frames[0]"), "Frame")
  end

  T["wait_url with filter for stopped thread"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")

    -- Wait for a stopped thread's frame using filter
    local ok = h:wait_url("/sessions/threads(state=stopped)/stack/frames[0]")
    MiniTest.expect.equality(ok, true)

    -- Thread state should be stopped
    MiniTest.expect.equality(h:query_type("/sessions/threads(state=stopped)[0]"), "Thread")
  end

  T["wait_url returns false on timeout for non-existent path"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stack/frames[0]")

    -- This path doesn't exist - should timeout
    local ok = h:wait_url("/nonexistent/path", 100)
    MiniTest.expect.equality(ok, false)
  end

  T["wait_url for threads"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")

    -- Wait for threads to exist
    local ok = h:wait_url("/sessions/threads")
    MiniTest.expect.equality(ok, true)

    -- Should have at least one thread
    MiniTest.expect.equality(h:query_count("/sessions/threads") >= 1, true)
  end

  -- ============================================================================
  -- Contextual URL without focus (from test_resolve_url.lua)
  -- ============================================================================

  T["returns nil for contextual URL without focus"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    -- Wait for session to be stopped but don't set focus
    h:wait_url("/sessions(state=stopped)")

    -- @session should return nil without focus
    MiniTest.expect.equality(h:query_is_nil("@session"), true)
  end
end)

return T
