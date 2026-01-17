-- Integration tests for URI format and resolution
-- Tests that URIs have correct format and can be used for entity lookup
local harness = require("helpers.test_harness")
local uri = require("neodap.uri")

local T = harness.integration("uri", function(T, ctx)
  -- ==========================================================================
  -- URI Format Tests
  -- ==========================================================================

  T["session URI has correct format and components"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local session_uri = h:query_field("@session", "uri")
    local session_id = h:query_field("@session", "sessionId")

    -- URI starts with correct prefix
    MiniTest.expect.equality(session_uri:match("^session:") ~= nil, true)

    -- Parse and verify components
    local parsed = uri.parse(session_uri)
    MiniTest.expect.equality(parsed.type, "session")
    MiniTest.expect.equality(parsed.components.sessionId, session_id)
  end

  T["thread URI has correct format and components"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local thread_uri = h:query_field("@thread", "uri")
    local thread_id = h:query_field("@thread", "threadId")
    local session_id = h:query_field("@session", "sessionId")

    -- URI starts with correct prefix
    MiniTest.expect.equality(thread_uri:match("^thread:") ~= nil, true)

    -- Parse and verify components
    local parsed = uri.parse(thread_uri)
    MiniTest.expect.equality(parsed.type, "thread")
    MiniTest.expect.equality(parsed.components.sessionId, session_id)
    MiniTest.expect.equality(parsed.components.threadId, thread_id)
  end

  T["frame URI has correct format and components"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local frame_uri = h:query_field("@frame", "uri")
    local frame_id = h:query_field("@frame", "frameId")
    local session_id = h:query_field("@session", "sessionId")

    -- URI starts with correct prefix
    MiniTest.expect.equality(frame_uri:match("^frame:") ~= nil, true)

    -- Parse and verify components
    local parsed = uri.parse(frame_uri)
    MiniTest.expect.equality(parsed.type, "frame")
    MiniTest.expect.equality(parsed.components.sessionId, session_id)
    MiniTest.expect.equality(parsed.components.frameId, frame_id)
  end

  T["scope URI has correct format and components"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")

    local scope_uri = h:query_field("@frame/scopes[0]", "uri")
    local scope_name = h:query_field("@frame/scopes[0]", "name")
    local frame_id = h:query_field("@frame", "frameId")
    local session_id = h:query_field("@session", "sessionId")

    -- URI starts with correct prefix
    MiniTest.expect.equality(scope_uri:match("^scope:") ~= nil, true)

    -- Parse and verify components
    local parsed = uri.parse(scope_uri)
    MiniTest.expect.equality(parsed.type, "scope")
    MiniTest.expect.equality(parsed.components.sessionId, session_id)
    MiniTest.expect.equality(parsed.components.frameId, frame_id)
    MiniTest.expect.equality(parsed.components.name, scope_name)
  end

  T["variable URI has correct format"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks(seq=1)[0]/frames[0]")  -- First stop
    h:cmd("DapFocus /sessions/threads/stacks(seq=1)[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads/stacks(seq=2)[0]/frames[0]")  -- Wait for NEW stack after step
    h:cmd("DapFocus /sessions/threads/stacks(seq=2)[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")

    -- Query first variable in locals scope
    local var_uri = h:query_field("@frame/scopes[0]/variables[0]", "uri")

    -- URI starts with correct prefix
    MiniTest.expect.equality(var_uri:match("^variable:") ~= nil, true)

    -- Parse and verify type
    local parsed = uri.parse(var_uri)
    MiniTest.expect.equality(parsed.type, "variable")
  end

  T["breakpoint URI has correct format and components"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.breakpoint_cmd")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:wait_url("/breakpoints(line=2)")

    local bp_uri = h:query_field("/breakpoints[0]", "uri")
    local bp_line = h:query_field("/breakpoints[0]", "line")

    -- URI starts with correct prefix
    MiniTest.expect.equality(bp_uri:match("^breakpoint:") ~= nil, true)

    -- Parse and verify components
    local parsed = uri.parse(bp_uri)
    MiniTest.expect.equality(parsed.type, "breakpoint")
    MiniTest.expect.equality(parsed.components.line, bp_line)
  end

  T["source URI has correct format"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local source_uri = h:query_field("/sources[0]", "uri")

    -- URI starts with correct prefix
    MiniTest.expect.equality(source_uri:match("^source:") ~= nil, true)

    -- Parse and verify type
    local parsed = uri.parse(source_uri)
    MiniTest.expect.equality(parsed.type, "source")
  end

  T["sourceBinding URI has correct format and components"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local sb_uri = h:query_field("@session/sourceBindings[0]", "uri")
    local session_id = h:query_field("@session", "sessionId")

    -- URI starts with correct prefix
    MiniTest.expect.equality(sb_uri:match("^sourcebinding:") ~= nil, true)

    -- Parse and verify components
    local parsed = uri.parse(sb_uri)
    MiniTest.expect.equality(parsed.type, "sourcebinding")
    MiniTest.expect.equality(parsed.components.sessionId, session_id)
  end

  -- ==========================================================================
  -- URI Resolution Tests (from test_resolve_uri.lua)
  -- ==========================================================================

  T["debugger has URI"] = function()
    local h = ctx.create()

    -- Debugger URI should be "debugger"
    local debugger_uri = h:query_uri("/")
    MiniTest.expect.equality(debugger_uri, "debugger")
  end

  T["resolves debugger URI"] = function()
    local h = ctx.create()

    -- Query by URI "debugger" should return the debugger (not nil)
    MiniTest.expect.equality(h:query_is_nil("debugger"), false)
    -- Round-trip: querying by URI returns same URI
    MiniTest.expect.equality(h:query_uri("debugger"), "debugger")
  end

  T["resolves session URI roundtrip"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Session URI should exist and round-trip correctly
    MiniTest.expect.equality(h:query_is_nil("/sessions[0]"), false)
    MiniTest.expect.equality(h:query_uri_roundtrips("/sessions[0]"), true)
  end

  T["resolves source URI roundtrip"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Source URI should exist and round-trip correctly
    MiniTest.expect.equality(h:query_is_nil("/sources[0]"), false)
    MiniTest.expect.equality(h:query_uri_roundtrips("/sources[0]"), true)
  end

  T["resolves thread URI roundtrip"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Thread URI should exist and round-trip correctly
    MiniTest.expect.equality(h:query_is_nil("@thread"), false)
    MiniTest.expect.equality(h:query_uri_roundtrips("@thread"), true)
  end

  T["stack has URI via navigation"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Stack should exist (accessible via navigation)
    MiniTest.expect.equality(h:query_is_nil("@thread/stack"), false)
    -- Stack should have a URI (navigated via thread, not direct lookup)
    local stack_uri = h:query_uri("@thread/stack")
    MiniTest.expect.equality(stack_uri ~= nil, true)
  end

  T["resolves frame URI roundtrip"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Frame URI should exist and round-trip correctly
    MiniTest.expect.equality(h:query_is_nil("@frame"), false)
    MiniTest.expect.equality(h:query_uri_roundtrips("@frame"), true)
  end

  T["resolves scope URI roundtrip"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")

    -- Scope URI should exist and round-trip correctly
    MiniTest.expect.equality(h:query_is_nil("@frame/scopes[0]"), false)
    MiniTest.expect.equality(h:query_uri_roundtrips("@frame/scopes[0]"), true)
  end

  T["returns nil for non-existent URI"] = function()
    local h = ctx.create()

    -- Query by non-existent URI should return nil
    MiniTest.expect.equality(h:query_is_nil("session:nonexistent"), true)
  end

  T["returns nil for invalid URI"] = function()
    local h = ctx.create()

    -- Query by invalid URI should return nil
    MiniTest.expect.equality(h:query_is_nil("invalid"), true)
  end
end)

return T
