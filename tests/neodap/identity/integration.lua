local harness = require("helpers.test_harness")

return harness.integration("identity", function(T, ctx)
  --------------------------------------------------------------------------------
  -- URI Resolution
  --------------------------------------------------------------------------------

  T["URI resolves session"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")  -- Sets focus for @session to work

    h:install_identity()
    MiniTest.expect.equality(h:query_uri_roundtrips("@session"), true)
  end

  T["URI resolves thread"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")  -- Sets focus for @session/@thread to work

    h:install_identity()
    MiniTest.expect.equality(h:query_uri_roundtrips("@session/threads[0]"), true)
  end

  T["URI resolves frame"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:install_identity()
    MiniTest.expect.equality(h:query_uri_roundtrips("@frame"), true)
  end

  --------------------------------------------------------------------------------
  -- URL Query
  --------------------------------------------------------------------------------

  T["URL query /sessions returns sessions"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:install_identity()
    -- js-debug creates 2 sessions (launcher + child), python creates 1
    local count = h:query_count("/sessions")
    MiniTest.expect.equality(count >= 1, true)
    MiniTest.expect.equality(h:query_type("/sessions"), "Session")
  end

  T["URL query @session returns focused session"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:install_identity()
    MiniTest.expect.equality(h:query_is_entity("@session"), true)
    MiniTest.expect.equality(h:query_type("@session"), "Session")
  end

  T["URL query @session/threads returns threads"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:install_identity()
    local count = h:query_count("@session/threads")
    MiniTest.expect.equality(count >= 1, true)
    MiniTest.expect.equality(h:query_type("@session/threads"), "Thread")
  end

  T["URL query @session/threads[0] returns first thread"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:install_identity()
    MiniTest.expect.equality(h:query_is_entity("@session/threads[0]"), true)
    MiniTest.expect.equality(h:query_type("@session/threads[0]"), "Thread")
  end

  T["URL query @thread returns focused thread"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:install_identity()
    MiniTest.expect.equality(h:query_is_entity("@thread"), true)
    MiniTest.expect.equality(h:query_type("@thread"), "Thread")
  end

  T["URL query @frame returns focused frame"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:install_identity()
    MiniTest.expect.equality(h:query_is_entity("@frame"), true)
    MiniTest.expect.equality(h:query_type("@frame"), "Frame")
  end

  T["URL query @frame/scopes returns scopes"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")

    h:install_identity()
    local count = h:query_count("@frame/scopes")
    MiniTest.expect.equality(count >= 1, true)
  end

  --------------------------------------------------------------------------------
  -- Field Access via URL
  --------------------------------------------------------------------------------

  T["query_field returns session state"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")  -- Sets focus for @session to work

    h:install_identity()
    MiniTest.expect.equality(h:query_field("@session", "state"), "stopped")
  end

  T["query_field returns frame line"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:install_identity()
    local line = h:query_field("@frame", "line")
    MiniTest.expect.equality(type(line), "number")
    MiniTest.expect.equality(line >= 1, true)
  end

  T["query_field returns thread id"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:install_identity()
    local id = h:query_field("@thread", "threadId")
    MiniTest.expect.equality(type(id), "number")
  end

  --------------------------------------------------------------------------------
  -- URI Field Access
  --------------------------------------------------------------------------------

  T["query_uri returns session URI"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")  -- Sets focus for @session to work

    h:install_identity()
    local uri = h:query_uri("@session")
    MiniTest.expect.equality(type(uri), "string")
    MiniTest.expect.equality(uri:match("^session:") ~= nil, true)
  end

  T["query_uri returns frame URI"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:install_identity()
    local uri = h:query_uri("@frame")
    MiniTest.expect.equality(type(uri), "string")
    MiniTest.expect.equality(uri:match("^frame:") ~= nil, true)
  end

  --------------------------------------------------------------------------------
  -- query_same for entity comparison
  --------------------------------------------------------------------------------

  T["query_same compares entities"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:install_identity()
    -- @frame and @thread/stack/frames[0] should be the same (focused frame)
    MiniTest.expect.equality(h:query_same("@frame", "@thread/stack/frames[0]"), true)
    -- @session and @thread should not be the same
    MiniTest.expect.equality(h:query_same("@session", "@thread"), false)
  end

  --------------------------------------------------------------------------------
  -- Edge Cases
  --------------------------------------------------------------------------------

  T["query on non-existent URL returns nil"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")  -- Sets focus (though not needed for /nonexistent test)

    h:install_identity()
    MiniTest.expect.equality(h:query_is_nil("/nonexistent"), true)
    -- query_field on non-existent URL should also indicate no result
    MiniTest.expect.equality(h:query_is_nil("/nonexistent/state"), true)
  end

  T["query_uri_roundtrips works for nested entities"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")

    h:install_identity()
    -- Scopes should also roundtrip
    local count = h:query_count("@frame/scopes")
    if count > 0 then
      MiniTest.expect.equality(h:query_uri_roundtrips("@frame/scopes[0]"), true)
    end
  end
end)
