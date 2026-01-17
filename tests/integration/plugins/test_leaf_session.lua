-- Tests for leaf_session plugin
-- Uses js-debug which spawns real child sessions
local harness = require("helpers.test_harness")

-- Skip all tests if js-debug not available in PATH
if vim.fn.executable("js-debug") ~= 1 then
  return MiniTest.new_set()
end

local js = harness.for_adapter("javascript")
local T = MiniTest.new_set()

T["leaf_session"] = MiniTest.new_set({ hooks = js.hooks })

T["leaf_session"]["plugin loads and returns cleanup function"] = function()
  local h = js.harness()
  h:use_plugin("neodap.plugins.leaf_session", "leaf_api")
  -- Plugin returns cleanup function, init_plugin stores it
  -- If we get here without error, plugin loaded successfully
end

T["leaf_session"]["js-debug creates real parent-child session relationship"] = function()
  local h = js.harness()
  h:start_jsdbg_dual()

  local has_root, has_child = h:has_jsdbg_sessions()
  MiniTest.expect.equality(has_root, true)
  MiniTest.expect.equality(has_child, true)
  MiniTest.expect.equality(h:query_same(h:session_uri("child") .. "/parent", h:session_uri("root")), true)
  MiniTest.expect.equality(h:query_count(h:session_uri("root") .. "/children") > 0, true)

  h:cleanup_jsdbg_dual()
end

T["leaf_session"]["parent session has leaf=false, child session has leaf=true"] = function()
  local h = js.harness()
  h:start_jsdbg_dual()

  MiniTest.expect.equality(h:query_field(h:session_uri("root"), "leaf"), false)
  MiniTest.expect.equality(h:query_field(h:session_uri("child"), "leaf"), true)

  h:cleanup_jsdbg_dual()
end

T["leaf_session"]["Session:rootAncestor() returns root for child session"] = function()
  local h = js.harness()
  h:start_jsdbg_dual()

  -- rootAncestor() is a method, not an edge - use query_method_uri
  local child_root = h:query_method_uri(h:session_uri("child"), "rootAncestor")
  local root_root = h:query_method_uri(h:session_uri("root"), "rootAncestor")
  local root_uri = h:session_uri("root")

  MiniTest.expect.equality(child_root, root_uri)
  MiniTest.expect.equality(root_root, root_uri)

  h:cleanup_jsdbg_dual()
end

T["leaf_session"]["Session:format() shows root name for child session"] = function()
  local h = js.harness()
  h:use_plugin("neodap.plugins.uri_picker")

  h:start_jsdbg_dual()

  -- Child session format should include root session name
  MiniTest.expect.equality(h:child_format_includes_root_name(), true)

  h:cleanup_jsdbg_dual()
end

T["leaf_session"]["sessions(leaf=true) only returns child sessions"] = function()
  local h = js.harness()
  h:start_jsdbg_dual()

  -- Child is leaf=true, root is leaf=false
  -- So /sessions(leaf=true) should return only child (count=1)
  MiniTest.expect.equality(h:query_count("/sessions(leaf=true)"), 1)
  MiniTest.expect.equality(h:query_count("/sessions(leaf=false)"), 1)

  h:cleanup_jsdbg_dual()
end

T["leaf_session"]["leaf_session auto-focuses child session when spawned"] = function()
  local h = js.harness()
  h:use_plugin("neodap.plugins.leaf_session")

  h:start_jsdbg_dual()

  -- Allow vim.schedule callbacks to run (leaf_session uses vim.schedule)
  h:yield()

  -- start_jsdbg_dual waits for child, leaf_session should have auto-focused it
  -- Wait for focused session to be a leaf (child session)
  h:wait_field("@session", "leaf", true)
  MiniTest.expect.equality(h:query_uri("@session"), h:session_uri("child"))

  h:cleanup_jsdbg_dual()
end

T["leaf_session"]["parent regains focus when child terminates"] = function()
  local h = js.harness()
  h:use_plugin("neodap.plugins.leaf_session")

  h:start_jsdbg_dual()

  -- Allow vim.schedule callbacks to run (leaf_session uses vim.schedule)
  h:yield()

  -- Wait for focused session to be a leaf (child session)
  h:wait_field("@session", "leaf", true)
  MiniTest.expect.equality(h:query_uri("@session"), h:session_uri("child"))

  -- Continue child to let it terminate
  h:continue_child_session()
  h:wait_child_terminated()

  MiniTest.expect.equality(h:query_field(h:session_uri("child"), "state"), "terminated")

  -- Wait for focused session to be non-leaf (parent regained focus)
  h:wait_field("@session", "leaf", false)
  MiniTest.expect.equality(h:query_uri("@session"), h:session_uri("root"))

  h:terminate_root_session()
end

T["leaf_session"]["without leaf_session plugin, child does not auto-focus"] = function()
  local h = js.harness()
  -- NOTE: NOT enabling leaf_session plugin

  h:start_jsdbg_dual()

  -- start_jsdbg_dual focuses root session; without leaf_session, focus stays on root
  -- Wait for focused session to be non-leaf (root)
  h:wait_field("@session", "leaf", false)

  -- Without leaf_session, focus should stay on root
  MiniTest.expect.equality(h:query_uri("@session"), h:session_uri("root"))

  h:cleanup_jsdbg_dual()
end

T["leaf_session"]["unfocused parent's child spawn does not steal focus"] = function()
  local h = js.harness()
  h:use_plugin("neodap.plugins.leaf_session")

  -- Start a python session first and focus it using py-sleeper fixture
  h:start_py_sleeper()
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
  local py_uri = h:query_uri("@session")

  -- Now start jsdbg (creates root + child, but shouldn't steal focus)
  -- Don't focus root - we want to test that unfocused parent's child doesn't steal focus
  h:start_jsdbg_dual({ focus_root = false })

  -- leaf_session only auto-focuses child when parent is focused
  -- Since js-debug root is not focused, child shouldn't be auto-focused
  -- Python session should still be focused
  MiniTest.expect.equality(h:query_uri("@session"), py_uri)

  -- Cleanup
  h:cleanup_jsdbg_dual()
  h:query_call(py_uri, "disconnect")
end

return T
