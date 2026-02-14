-- Tests for multi-session behavior
-- Tests that multiple debug sessions can coexist and be managed
--
-- Note: These tests are Python-only because js-debug uses a complex bootstrap
-- session pattern that makes multi-session testing significantly more complex.
local harness = require("helpers.test_harness")

-- Temporarily restrict to Python only
local original_adapters = harness.enabled_adapters
harness.enabled_adapters = { "python" }

local T = harness.integration("multi_session", function(T, ctx)
  -- User scenario: Launch two debug sessions simultaneously
  T["two sessions can exist simultaneously"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")

    -- Launch first session
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    local session1_uri = h:query_field("@session", "uri")

    -- Launch second session (wait for session index 1 specifically)
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")
    local session2_uri = h:query_field("@session", "uri")

    -- Verify two different sessions exist
    MiniTest.expect.equality(session1_uri ~= session2_uri, true)

    -- Count sessions
    local session_count = h:query_count("/sessions")
    MiniTest.expect.equality(session_count, 2)
  end

  -- User scenario: DapFocus switches between sessions
  T["DapFocus switches between sessions"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.focus_cmd")

    -- Launch first session and save URI
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    local session1_uri = h:query_field("@session", "uri")

    -- Launch second session and save URI (wait for session index 1 specifically)
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")
    local session2_uri = h:query_field("@session", "uri")

    -- Focus first session
    h:cmd("DapFocus " .. session1_uri)
    h:wait(50)
    local focused1 = h:query_field("@session", "uri")
    MiniTest.expect.equality(focused1, session1_uri)

    -- Switch to second session
    h:cmd("DapFocus " .. session2_uri)
    h:wait(50)
    local focused2 = h:query_field("@session", "uri")
    MiniTest.expect.equality(focused2, session2_uri)

    -- Switch back to first session
    h:cmd("DapFocus " .. session1_uri)
    h:wait(50)
    local focused3 = h:query_field("@session", "uri")
    MiniTest.expect.equality(focused3, session1_uri)
  end

  -- User scenario: @thread and @frame update when focus switches
  T["@thread and @frame update with session focus switch"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.focus_cmd")

    -- Launch first session
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    local session1_uri = h:query_field("@session", "uri")
    local thread1_uri = h:query_field("@thread", "uri")

    -- Launch second session (wait for session index 1 specifically)
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")
    local session2_uri = h:query_field("@session", "uri")
    local thread2_uri = h:query_field("@thread", "uri")

    -- Threads should be different
    MiniTest.expect.equality(thread1_uri ~= thread2_uri, true)

    -- Focus session1 and verify thread
    h:cmd("DapFocus " .. session1_uri)
    h:wait(50)
    local focused_thread1 = h:query_field("@thread", "uri")
    MiniTest.expect.equality(focused_thread1, thread1_uri)

    -- Focus session2 and verify thread changes
    h:cmd("DapFocus " .. session2_uri)
    h:wait(50)
    local focused_thread2 = h:query_field("@thread", "uri")
    MiniTest.expect.equality(focused_thread2, thread2_uri)
  end

  -- User scenario: Session termination is tracked
  T["session termination is tracked"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.cursor_focus")

    -- Launch session with stopOnEntry so cursor_focus can focus
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Verify we have a session focused
    MiniTest.expect.equality(h:query_is_nil("@session"), false)

    -- Continue to termination
    h:cmd("DapContinue")
    h:wait_terminated(10000)

    -- Session state should be terminated (use absolute URI since focus clears on termination)
    local index = h.adapter.name == "javascript" and 1 or 0
    local state = h:query_field(string.format("/sessions[%d]", index), "state")
    MiniTest.expect.equality(state, "terminated")
  end

  -- User scenario: Three sessions can be managed
  T["three sessions can be managed simultaneously"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.focus_cmd")

    -- Launch three sessions
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    local uri1 = h:query_field("@session", "uri")

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")
    local uri2 = h:query_field("@session", "uri")

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions[2]/threads(state=stopped)/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions[2]/threads(state=stopped)/stacks[0]/frames[0]")
    local uri3 = h:query_field("@session", "uri")

    -- Verify count
    local session_count = h:query_count("/sessions")
    MiniTest.expect.equality(session_count, 3)

    -- Focus each session and verify
    h:cmd("DapFocus " .. uri1)
    h:wait(50)
    MiniTest.expect.equality(h:query_field("@session", "uri"), uri1)

    h:cmd("DapFocus " .. uri2)
    h:wait(50)
    MiniTest.expect.equality(h:query_field("@session", "uri"), uri2)

    h:cmd("DapFocus " .. uri3)
    h:wait(50)
    MiniTest.expect.equality(h:query_field("@session", "uri"), uri3)
  end

  -- User scenario: Focus persists when other session terminates
  T["focus persists after other session terminates"] = function()
    local h = ctx.create()
    h:fixture("hello") -- hello fixture runs and terminates quickly
    h:use_plugin("neodap.plugins.focus_cmd")

    -- Launch long-running session with stopOnEntry
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    local session1_uri = h:query_field("@session", "uri")

    -- Focus session1 explicitly
    h:cmd("DapFocus " .. session1_uri)
    h:wait(50)

    -- Launch short-lived session (no stopOnEntry - runs and terminates)
    h:cmd("DapLaunch Debug")

    -- Wait for second session to terminate
    h:wait(500)

    -- Focus should still be on session1
    local focused_uri = h:query_field("@session", "uri")
    MiniTest.expect.equality(focused_uri, session1_uri)
  end

  -- User scenario: cursor_focus and leaf_session plugins work together
  T["cursor_focus and leaf_session work with multiple sessions"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.cursor_focus")
    h:use_plugin("neodap.plugins.leaf_session")

    -- Launch first session
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    local session1_uri = h:query_field("@session", "uri")

    -- Verify cursor_focus focused the session
    MiniTest.expect.equality(h:query_is_nil("@session"), false)

    -- Launch second session (wait for session index 1 specifically)
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")
    local session2_uri = h:query_field("@session", "uri")

    -- Since these are independent sessions (not parent-child),
    -- leaf_session shouldn't affect focus behavior
    -- The second session launch should update _G.session but focus depends on cursor_focus
    MiniTest.expect.equality(session1_uri ~= session2_uri, true)
  end

  -- User scenario: Query sessions by index
  T["query sessions by index works"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")

    -- Launch two sessions
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")

    -- Query sessions by index
    local session0_exists = not h:query_is_nil("/sessions[0]")
    local session1_exists = not h:query_is_nil("/sessions[1]")
    local session2_exists = not h:query_is_nil("/sessions[2]")

    MiniTest.expect.equality(session0_exists, true)
    MiniTest.expect.equality(session1_exists, true)
    MiniTest.expect.equality(session2_exists, false)
  end
end)

-- Restore original adapters
harness.enabled_adapters = original_adapters

return T
