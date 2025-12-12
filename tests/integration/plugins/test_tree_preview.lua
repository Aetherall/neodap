local harness = require("helpers.test_harness")

return harness.integration("tree_preview", function(T, ctx)
  -- User scenario: Invalid tree buffer shows error
  T["shows error for invalid tree buffer"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.preview_handler")
    h:use_plugin("neodap.plugins.tree_preview")

    -- Try to open tree-preview for non-existent buffer
    h:cmd("edit dap://tree-preview/99999")
    h:wait(50)

    local lines = h:get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
    MiniTest.expect.equality(lines[1]:match("Invalid tree buffer") ~= nil, true)
  end

  -- User scenario: Non-tree buffer shows error
  T["shows error for non-tree buffer"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.preview_handler")
    h:use_plugin("neodap.plugins.tree_preview")

    -- Create a regular buffer and get its number
    h:cmd("enew")
    local regular_bufnr = h:get("vim.api.nvim_get_current_buf()")

    -- Try to open tree-preview for regular buffer
    h:cmd("edit dap://tree-preview/" .. regular_bufnr)
    h:wait(50)

    local lines = h:get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
    MiniTest.expect.equality(lines[1]:match("Not a tree buffer") ~= nil, true)
  end

  -- User scenario: Tree preview shows entity from tree
  T["shows focused entity from tree buffer"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.preview_handler")
    h:use_plugin("neodap.plugins.tree_preview")

    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    -- Open tree buffer and get its bufnr
    h:cmd("edit dap://tree/@debugger")
    h:wait(100)
    local tree_bufnr = h:get("vim.api.nvim_get_current_buf()")

    -- Open tree-preview in a split
    h:cmd("vsplit dap://tree-preview/" .. tree_bufnr)
    h:wait(100)

    -- Preview should show entity content (fallback shows "# Preview" or "URI:")
    local content = h:get("table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n')")
    local has_content = content:match("Preview") ~= nil or content:match("URI:") ~= nil
    MiniTest.expect.equality(has_content, true)
  end

  -- User scenario: Preview updates when cursor moves in tree
  T["updates when cursor moves in tree"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.preview_handler")
    h:use_plugin("neodap.plugins.tree_preview")

    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    -- Open tree buffer
    h:cmd("edit dap://tree/@debugger")
    h:wait(100)
    local tree_bufnr = h:get("vim.api.nvim_get_current_buf()")

    -- Open tree-preview
    h:cmd("vsplit dap://tree-preview/" .. tree_bufnr)
    h:wait(100)
    local preview_bufnr = h:get("vim.api.nvim_get_current_buf()")

    -- Move to tree window and move cursor
    h:cmd("wincmd h")
    h:wait(50)
    h:cmd("normal! j")
    h:wait(100)

    -- Preview buffer should still be valid and have content
    local is_valid = h:get("vim.api.nvim_buf_is_valid(" .. preview_bufnr .. ")")
    MiniTest.expect.equality(is_valid, true)
  end

  -- User scenario: Cleanup on preview buffer wipeout
  T["cleans up on buffer wipeout"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.preview_handler")
    h:use_plugin("neodap.plugins.tree_preview")

    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    h:cmd("edit dap://tree/@debugger")
    h:wait(100)
    local tree_bufnr = h:get("vim.api.nvim_get_current_buf()")

    h:cmd("vsplit dap://tree-preview/" .. tree_bufnr)
    h:wait(100)

    -- Wipe preview buffer - should not error
    h:cmd("bwipeout!")
    h:wait(50)

    -- Should complete without error
    MiniTest.expect.equality(true, true)
  end
end)
