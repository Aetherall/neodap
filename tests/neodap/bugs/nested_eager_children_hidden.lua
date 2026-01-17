-- Bug: Child session not visible under parent when entity is reachable via multiple paths
--
-- When a child session is reachable via multiple paths in the query:
--   1. Sessions → Debug JS File → children → demo.js
--   2. Targets → leafSessions → demo.js (same entity)
--
-- The child appears ONLY under Targets, not under the parent session's children edge.
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
--   - Under Sessions → Debug JS File → children
--   - Under Targets → leafSessions
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
    local parent_name = h:query_field("/sessions[0]", "name")
    local parent_children_count = h:query_count("/sessions[0]/children")

    -- Skip if no parent/child hierarchy
    if parent_children_count == 0 then
      MiniTest.skip("No parent/child session hierarchy")
      return
    end

    local parent_session = { name = parent_name, children = parent_children_count }

    -- Open tree at sessions:group to see session hierarchy directly
    -- (Sessions is hidden under @debugger when not eager)
    h:open_tree("sessions:group")
    h:wait(300)

    -- Expand Sessions node to show sessions (children edge is eager, so children auto-expand)
    h.child.type_keys("<CR>")
    h:wait(200)

    -- Get tree lines
    local lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)

    -- Find the parent session line (escape special chars for pattern matching)
    local parent_line_idx = nil
    local escaped_name = parent_session.name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    for i, line in ipairs(lines) do
      if line:match(escaped_name) then
        parent_line_idx = i
        break
      end
    end

    MiniTest.expect.no_equality(parent_line_idx, nil,
      "Parent session '" .. parent_session.name .. "' should be in tree.\nTree lines:\n" .. table.concat(lines, "\n"))

    -- Check if child session appears after parent (in sessions:group tree, no Targets section)
    local child_under_parent = false
    for i = parent_line_idx + 1, #lines do
      local line = lines[i]
      -- Child session has specific format with PID in brackets and state icon
      if line:match("%[%d+%]") and (line:match("⏸") or line:match("▶") or line:match("⏹")) then
        child_under_parent = true
        break
      end
    end

    MiniTest.expect.equality(child_under_parent, true,
      "Child session should appear under parent session's children edge.\n" ..
      "Tree lines:\n" .. table.concat(lines, "\n"))
  end
end)

harness.enabled_adapters = original_adapters

return T
