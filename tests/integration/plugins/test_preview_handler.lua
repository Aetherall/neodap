local harness = require("helpers.test_harness")

return harness.integration("preview_handler", function(T, ctx)
  -- User scenario: Preview buffer shows entity not found for invalid URI
  T["shows error for invalid entity URI"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.preview_handler")

    -- Try to open preview for non-existent entity
    h:cmd("edit dap://preview/nonexistent:abc123")
    h:wait(50)

    -- Buffer should show error
    local lines = h:get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
    MiniTest.expect.equality(lines[1]:match("Entity not found") ~= nil, true)
  end

  -- User scenario: Preview buffer displays entity with fallback
  T["fallback renders entity properties"] = function()
    local h = ctx.create()

    h:use_plugin("neodap.plugins.focus_cmd")
    h:use_plugin("neodap.plugins.preview_handler")
    h:fixture("simple-vars")

    -- Launch debug session
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    -- Get a frame entity URI using harness helper
    local frame_uri = h:query_uri("@frame")

    -- Open preview for frame (no handler registered, should use fallback)
    h:cmd("edit dap://preview/" .. frame_uri)
    h:wait(50)

    -- Buffer should show fallback content with URI and Type
    local content = h:get("table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n')")
    MiniTest.expect.equality(content:match("Preview") ~= nil, true)
    MiniTest.expect.equality(content:match("URI:") ~= nil, true)
    MiniTest.expect.equality(content:match("Type:") ~= nil, true)
  end

  -- User scenario: Preview shows session entity
  T["shows session entity"] = function()
    local h = ctx.create()
    h:use_plugin("neodap.plugins.focus_cmd")
    h:use_plugin("neodap.plugins.preview_handler")
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    local session_uri = h:query_uri("@session")

    h:cmd("edit dap://preview/" .. session_uri)
    h:wait(50)

    -- Should show session info
    local content = h:get("table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n')")
    MiniTest.expect.equality(content:match("Session") ~= nil, true)
  end

  -- User scenario: Preview shows thread entity
  T["shows thread entity"] = function()
    local h = ctx.create()
    h:use_plugin("neodap.plugins.focus_cmd")
    h:use_plugin("neodap.plugins.preview_handler")
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    local thread_uri = h:query_uri("@thread")

    h:cmd("edit dap://preview/" .. thread_uri)
    h:wait(50)

    -- Should show thread info
    local content = h:get("table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n')")
    MiniTest.expect.equality(content:match("Thread") ~= nil, true)
  end

  -- User scenario: Buffer name reflects entity URI
  T["buffer name contains entity URI"] = function()
    local h = ctx.create()
    h:use_plugin("neodap.plugins.focus_cmd")
    h:use_plugin("neodap.plugins.preview_handler")
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(50)

    local frame_uri = h:query_uri("@frame")

    h:cmd("edit dap://preview/" .. frame_uri)
    h:wait(50)

    local bufname = h:get("vim.api.nvim_buf_get_name(0)")
    MiniTest.expect.equality(bufname:match("dap://preview/") ~= nil, true)
    MiniTest.expect.equality(bufname:match(frame_uri) ~= nil, true)
  end
end)
