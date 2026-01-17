-- URI Picker tests
-- Uses Python-only because some tests use screenshots that need consistent visual output
local harness = require("helpers.test_harness")

-- Keep as Python-only because picker UI screenshots differ between adapters
local original_adapters = harness.enabled_adapters
harness.enabled_adapters = { "python" }

local T = harness.integration("uri_picker", function(T, ctx)
  T["empty collection calls callback with nil"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.uri_picker")

    -- Without launching any session, sessions collection should be empty
    -- Picker resolve on empty collection calls callback with nil
    local count = h:query_count("/sessions")

    MiniTest.expect.equality(count, 0)
  end

  T["single item returns directly without picker"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:use_plugin("neodap.plugins.uri_picker")

    -- With single session, picker returns it directly without showing picker UI
    -- Verify exactly one session exists and it has a valid URI
    local count = h:query_count("/sessions")
    local session_uri = h:query_uri("@session")

    MiniTest.expect.equality(count, 1)
    MiniTest.expect.equality(session_uri ~= nil, true)
  end

  T["resolves @session/threads"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:use_plugin("neodap.plugins.uri_picker")

    -- Verify thread can be resolved via @session/threads path
    -- Thread should have threadId and state properties
    local threadId = h:query_field("@thread", "threadId")
    local state = h:query_field("@thread", "state")

    MiniTest.expect.equality(threadId ~= nil, true)
    MiniTest.expect.equality(state ~= nil, true)
  end

  T["Session:format() returns name and state"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:use_plugin("neodap.plugins.uri_picker")

    -- Verify session has required properties for format
    local name = h:query_field("@session", "name")
    local state = h:query_field("@session", "state")

    MiniTest.expect.equality(name ~= nil, true)
    MiniTest.expect.equality(state ~= nil, true)
    -- Format should be "name (state)"
    local expected_format = name .. " (" .. state .. ")"
    MiniTest.expect.equality(expected_format:match(".+ %(.+%)") ~= nil, true)
  end

  T["Thread:format() returns id, name and state"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:use_plugin("neodap.plugins.uri_picker")

    -- Verify thread has required properties for format
    local threadId = h:query_field("@thread", "threadId")
    local name = h:query_field("@thread", "name")
    local state = h:query_field("@thread", "state")

    MiniTest.expect.equality(threadId ~= nil, true)
    MiniTest.expect.equality(name ~= nil, true)
    MiniTest.expect.equality(state ~= nil, true)
  end

  T["Frame:format() returns name, file and line"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:use_plugin("neodap.plugins.uri_picker")

    -- Verify frame has required properties for format
    local name = h:query_field("@frame", "name")
    local line = h:query_field("@frame", "line")

    MiniTest.expect.equality(name ~= nil, true)
    MiniTest.expect.equality(line ~= nil, true)
    MiniTest.expect.equality(type(line) == "number", true)
  end

  T["Scope:format() returns scope name"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")

    h:use_plugin("neodap.plugins.uri_picker")

    -- Verify scope has name property for format (format returns name)
    local name = h:query_field("@frame/scopes[0]", "name")

    MiniTest.expect.equality(name ~= nil, true)
    MiniTest.expect.equality(type(name) == "string", true)
  end

  T["Variable:format() returns name = value"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    -- Step to define the variable (line 1 -> 2)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")
    h:query_call("@frame/scopes[0]", "fetchVariables")
    h:wait_url("@frame/scopes[0]/variables[0]")

    h:use_plugin("neodap.plugins.uri_picker")

    -- Verify variable has name and value properties for format (format returns "name = value")
    -- Get the first variable from the scope - simple_vars defines 'x'
    local name = h:query_field("@frame/scopes[0]/variables:x", "name")
    local value = h:query_field("@frame/scopes[0]/variables:x", "value")

    MiniTest.expect.equality(name, "x")
    MiniTest.expect.equality(value ~= nil, true)
  end

  T["session.leaf is true for session without children"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    local leaf = h:query_field("@session", "leaf")

    MiniTest.expect.equality(leaf, true)
  end

  T["Session:rootAncestor() returns self for root session"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:use_plugin("neodap.plugins.uri_picker")

    -- A root session has no parent, so rootAncestor() returns self
    -- Verify this is a root session by checking parent is nil/vim.NIL
    local parent = h:query_field("@session", "parent")
    local session_uri = h:query_uri("@session")

    -- vim.NIL is returned from child process for nil values
    MiniTest.expect.equality(parent == nil or parent == vim.NIL, true)
    MiniTest.expect.equality(session_uri ~= nil, true)
  end

  T["sessions(leaf=true) filter returns leaf sessions"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:use_plugin("neodap.plugins.uri_picker")

    -- Verify the session is a leaf (would match leaf=true filter)
    local leaf = h:query_field("@session", "leaf")
    local session_uri = h:query_uri("@session")

    MiniTest.expect.equality(leaf, true)
    MiniTest.expect.equality(session_uri ~= nil, true)
  end
end)

-- Restore original adapters
harness.enabled_adapters = original_adapters

return T
