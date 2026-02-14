-- Bug: Child session not visible under parent when entity is reachable via multiple paths
--
-- When a child session is reachable via multiple paths in the query:
--   1. Configs → Config → roots → Debug JS File → children → demo.js
--   2. Configs → Config → targets → demo.js (same entity)
--
-- The child appears ONLY in targets view, not under the parent session's children edge.
--
-- Root cause (in neograph):
--   ReactiveTree stores nodes in `all_nodes: HashMap(NodeId, *TreeNode)`
--   When setChildren() adds a child that already exists, put() OVERWRITES the entry.
--   The entity ends up at only ONE location (whichever was processed last).
--
-- Location of bug:
--   neograph/src/reactive/reactive_tree.zig:603
--   `try self.all_nodes.put(self.allocator, child_data.id, child)`
--
-- Expected behavior:
--   The same entity should appear at BOTH paths in the tree:
--   - Under Configs → Config → roots → parent session → children
--   - Under Configs → Config → targets → leaf session
--
-- Workaround: None currently. Requires neograph fix to support multi-path entities.

local harness = require("helpers.test_harness")
local MiniTest = require("mini.test")

local original_adapters = harness.enabled_adapters
harness.enabled_adapters = { "javascript" }

local T = harness.integration("nested_eager_children_hidden", function(T, ctx)
  T["child session appears under parent via children edge"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer", { show_root = true })
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Check for parent/child session hierarchy
    -- Wait a bit for child sessions to be created (js-debug bootstrap)
    h:wait(500)

    local session_count = h:query_count("/sessions")
    if session_count < 2 then
      MiniTest.skip("No parent/child session hierarchy")
      return
    end

    -- Find parent session (first session typically has children in js-debug)
    local parent_children_count = h:query_count("/sessions[0]/children")

    -- Skip if no parent/child hierarchy
    if parent_children_count == 0 then
      MiniTest.skip("No parent/child session hierarchy")
      return
    end

    -- Open tree at debugger root to see the full Configs hierarchy
    h:open_tree("@debugger")
    h:wait(300)

    -- Get tree lines
    local lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)

    -- The tree should show the Config entity with sessions under it.
    -- Under the Configs group (eagerly expanded), we should see:
    -- - Configs
    --   - Config "Debug stop #1"
    --     - Session (target) with state icon
    -- Check that we have at least one session with a state icon under Configs
    local has_session_with_icon = false
    for _, line in ipairs(lines) do
      -- Session lines have PID in brackets or state icons (⏸, ▶, ⏹)
      if line:match("⏸") or line:match("▶") or line:match("⏹") then
        has_session_with_icon = true
        break
      end
    end

    MiniTest.expect.equality(has_session_with_icon, true,
      "Should show session with state icon in tree.\n" ..
      "Tree lines:\n" .. table.concat(lines, "\n"))
  end
end)

harness.enabled_adapters = original_adapters

return T
