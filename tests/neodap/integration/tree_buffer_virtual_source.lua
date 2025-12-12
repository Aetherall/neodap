-- Tests for gd navigation in tree_buffer
local harness = require("helpers.test_harness")

local adapter = harness.for_adapter("javascript")

local T = MiniTest.new_set({
  hooks = adapter.hooks,
})

T["tree_buffer_virtual_source"] = MiniTest.new_set()

T["tree_buffer_virtual_source"]["gd on frame with file source opens file buffer"] = function()
  local h = adapter.harness()
  h:setup_visual()
  local fixture_path = h:fixture("simple-vars")

  h:use_plugin("neodap.plugins.tree_buffer", { show_root = true })

  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Get expected line before opening tree
  local expected_line = h:query_field("@frame", "line")

  -- Open tree at frame (harness helper)
  h:open_tree("@frame")

  -- Press gd on frame to go to source
  h.child.type_keys("gd")
  -- Use parent-side sleep to avoid child blocking issues
  vim.loop.sleep(200)

  -- Verify we're in the source file (not dap://source)
  local bufname = h.child.api.nvim_buf_get_name(0)
  local cursor = h.child.api.nvim_win_get_cursor(0)
  local expected_path = fixture_path .. "/main.js"

  MiniTest.expect.equality(bufname, expected_path)
  MiniTest.expect.equality(bufname:match("^dap://source/") == nil, true)
  MiniTest.expect.equality(cursor[1], expected_line)
end

return T
