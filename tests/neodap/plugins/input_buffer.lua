-- Tests for input_buffer plugin (dap://input/ URI protocol with reactive frame binding)
local harness = require("helpers.test_harness")

local adapter = harness.for_adapter("javascript")

local T = MiniTest.new_set({
  hooks = adapter.hooks,
})

T["input_buffer"] = MiniTest.new_set()

T["input_buffer"]["opens dap://input buffer with correct settings"] = function()
  local h = adapter.harness()

  -- Setup plugins
  h:use_plugin("neodap.plugins.completion")
  h:use_plugin("neodap.plugins.input_buffer")

  -- Open a dap://input buffer
  h.child.cmd("edit dap://input/@frame")
  vim.loop.sleep(200)

  -- Check buffer settings
  local bufname = h.child.api.nvim_buf_get_name(0)
  local buftype = h.child.bo.buftype
  local modifiable = h.child.bo.modifiable
  local omnifunc = h.child.bo.omnifunc

  -- Check that buffer name contains dap://input/
  MiniTest.expect.equality(bufname:match("dap://input/") ~= nil, true)
  MiniTest.expect.equality(buftype, "acwrite") -- entity_buffer sets acwrite for buffers with submit
  MiniTest.expect.equality(modifiable, true)
  MiniTest.expect.equality(omnifunc ~= nil and omnifunc ~= "", true)
end

T["input_buffer"]["closeonsubmit option closes buffer after submit"] = function()
  local h = adapter.harness()
  h:fixture("debugger-vars")
  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Focus frame
  h:use_plugin("neodap.plugins.focus_cmd")
  h:cmd("DapFocus @frame")
  h:wait(50)

  h:use_plugin("neodap.plugins.completion")
  h:use_plugin("neodap.plugins.input_buffer")

  -- Open with closeonsubmit option
  h.child.cmd("edit dap://input/@frame?closeonsubmit")
  vim.loop.sleep(100)

  -- Store buffer number for later check
  local edit_bufnr = h.child.api.nvim_get_current_buf()

  -- Type and submit
  h.child.type_keys("x")
  vim.loop.sleep(50)
  h.child.type_keys("<CR>")
  vim.loop.sleep(300)

  -- Buffer should be closed
  local buf_valid = h.child.api.nvim_buf_is_valid(edit_bufnr)

  MiniTest.expect.equality(buf_valid, false)
end

T["input_buffer"]["shows virtual text indicator for frame"] = function()
  local h = adapter.harness()
  h:fixture("debugger-vars")
  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Focus frame
  h:use_plugin("neodap.plugins.focus_cmd")
  h:cmd("DapFocus @frame")
  h:wait(50)

  h:use_plugin("neodap.plugins.completion")
  h:use_plugin("neodap.plugins.input_buffer")

  -- Open input buffer
  h.child.cmd("edit dap://input/@frame")
  vim.loop.sleep(200)

  -- Check for virtual text extmark
  local bufnr = h.child.api.nvim_get_current_buf()
  local ns = h.child.api.nvim_get_namespaces()["neodap-input-buffer"]
  local extmarks = h.child.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

  MiniTest.expect.equality(#extmarks > 0, true)
  -- Should contain frame info (arrow and function name)
  local virt_text = extmarks[1][4].virt_text[1][1]
  MiniTest.expect.equality(virt_text:match("^→") ~= nil, true)
end

T["input_buffer"]["shows warning indicator when no frame"] = function()
  local h = adapter.harness()

  h:use_plugin("neodap.plugins.completion")
  h:use_plugin("neodap.plugins.input_buffer")

  -- Open input buffer without any debug session
  h.child.cmd("edit dap://input/@frame")
  vim.loop.sleep(200)

  -- Check for warning virtual text
  local bufnr = h.child.api.nvim_get_current_buf()
  local ns = h.child.api.nvim_get_namespaces()["neodap-input-buffer"]
  local extmarks = h.child.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

  local virt_text = extmarks[1][4].virt_text[1][1]
  local virt_hl = extmarks[1][4].virt_text[1][2]

  MiniTest.expect.equality(virt_text, "⚠ No frame")
  MiniTest.expect.equality(virt_hl, "WarningMsg")
end

T["input_buffer"]["evaluates expression in stopped frame"] = function()
  local h = adapter.harness()
  h:fixture("debugger-vars")
  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Focus frame
  h:use_plugin("neodap.plugins.focus_cmd")
  h:cmd("DapFocus @frame")
  h:wait(50)

  -- Setup input_buffer plugin
  h:use_plugin("neodap.plugins.input_buffer")

  -- Open input buffer (without closeonsubmit so buffer stays open)
  h.child.cmd("edit dap://input/@frame")
  vim.loop.sleep(100)

  -- Type an expression and submit
  h.child.type_keys("x + y")
  vim.loop.sleep(50)
  h.child.type_keys("<CR>")
  vim.loop.sleep(500) -- Wait for async evaluation

  -- Verify expression was added to history by pressing Up
  h.child.type_keys("<Up>")
  vim.loop.sleep(50)

  local lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Should show submitted expression from history
  MiniTest.expect.equality(lines[1], "x + y")
end

T["input_buffer"]["history navigation works"] = function()
  local h = adapter.harness()
  h:fixture("debugger-vars")
  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Focus frame
  h:use_plugin("neodap.plugins.focus_cmd")
  h:cmd("DapFocus @frame")
  h:wait(50)

  h:use_plugin("neodap.plugins.input_buffer")

  -- Open input buffer and submit a few expressions
  h.child.cmd("edit dap://input/@frame")
  vim.loop.sleep(100)

  h.child.type_keys("first expression")
  h.child.type_keys("<CR>")
  vim.loop.sleep(200)

  h.child.type_keys("second expression")
  h.child.type_keys("<CR>")
  vim.loop.sleep(200)

  -- Now navigate history with Up arrow
  h.child.type_keys("<Up>")
  vim.loop.sleep(50)

  local lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Should show "second expression" (most recent)
  MiniTest.expect.equality(lines[1], "second expression")

  -- Navigate to older history
  h.child.type_keys("<Up>")
  vim.loop.sleep(50)

  lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Should show "first expression"
  MiniTest.expect.equality(lines[1], "first expression")
end

T["input_buffer"]["clears buffer after submit"] = function()
  local h = adapter.harness()
  h:fixture("debugger-vars")
  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Focus frame
  h:use_plugin("neodap.plugins.focus_cmd")
  h:cmd("DapFocus @frame")
  h:wait(50)

  h:use_plugin("neodap.plugins.input_buffer")

  h.child.cmd("edit dap://input/@frame")
  vim.loop.sleep(100)

  h.child.type_keys("some expression")
  vim.loop.sleep(50)
  h.child.type_keys("<CR>")
  vim.loop.sleep(200)

  -- Buffer should be cleared (but may have empty line for virtual text)
  local lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)

  MiniTest.expect.equality(#lines, 1)
  MiniTest.expect.equality(lines[1] or "", "")
end

T["input_buffer"]["history stores multiple expressions"] = function()
  local h = adapter.harness()
  h:fixture("debugger-vars")
  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Focus frame
  h:use_plugin("neodap.plugins.focus_cmd")
  h:cmd("DapFocus @frame")
  h:wait(50)

  h:use_plugin("neodap.plugins.input_buffer")

  h.child.cmd("edit dap://input/@frame")
  vim.loop.sleep(100)

  -- Submit expressions
  h.child.type_keys("expr1")
  h.child.type_keys("<CR>")
  vim.loop.sleep(200)

  h.child.type_keys("expr2")
  h.child.type_keys("<CR>")
  vim.loop.sleep(200)

  h.child.type_keys("expr3")
  h.child.type_keys("<CR>")
  vim.loop.sleep(200)

  -- Verify all expressions are in history by navigating
  h.child.type_keys("<Up>")
  vim.loop.sleep(50)
  local lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(lines[1], "expr3")

  h.child.type_keys("<Up>")
  vim.loop.sleep(50)
  lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(lines[1], "expr2")

  h.child.type_keys("<Up>")
  vim.loop.sleep(50)
  lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(lines[1], "expr1")
end

T["input_buffer"]["reactive binding updates on focus change"] = function()
  local h = adapter.harness()
  h:fixture("debugger-stack")
  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Get frame URIs from stack
  local inner_frame_uri = h:query_uri("@thread/stack/frames[0]")
  local outer_frame_uri = h:query_uri("@thread/stack/frames[1]")

  -- Focus inner frame via DapFocus command
  h:use_plugin("neodap.plugins.focus_cmd")
  h:cmd("DapFocus " .. inner_frame_uri)
  h:wait(100)

  h:use_plugin("neodap.plugins.input_buffer")

  -- Open input buffer
  h.child.cmd("edit dap://input/@frame")
  vim.loop.sleep(200)

  -- Check initial bound frame via virtual text indicator
  local bufnr = h.child.api.nvim_get_current_buf()
  local ns = h.child.api.nvim_get_namespaces()["neodap-input-buffer"]
  local extmarks = h.child.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  local initial_virt_text = extmarks[1][4].virt_text[1][1]

  -- Frame name includes module prefix in JS debugger
  MiniTest.expect.equality(initial_virt_text:match("inner") ~= nil, true)

  -- Change focus to outer frame via DapFocus
  h:cmd("DapFocus " .. outer_frame_uri)
  h:wait(200)

  -- Re-enter the buffer to trigger virtual text update
  h.child.cmd("edit")
  h:wait(100)

  -- Check bound frame updated via virtual text
  extmarks = h.child.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  local updated_virt_text = extmarks[1][4].virt_text[1][1]

  MiniTest.expect.equality(updated_virt_text:match("outer") ~= nil, true)
end

T["input_buffer"]["pin option prevents reactive updates"] = function()
  local h = adapter.harness()
  h:fixture("debugger-stack")
  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Get frame URIs from stack
  local inner_frame_uri = h:query_uri("@thread/stack/frames[0]")
  local outer_frame_uri = h:query_uri("@thread/stack/frames[1]")

  -- Focus inner frame via DapFocus command
  h:use_plugin("neodap.plugins.focus_cmd")
  h:cmd("DapFocus " .. inner_frame_uri)
  h:wait(100)

  h:use_plugin("neodap.plugins.completion")
  h:use_plugin("neodap.plugins.input_buffer")

  -- Open input buffer WITH pin option
  h.child.cmd("edit dap://input/@frame?pin")
  vim.loop.sleep(200)

  -- Check initial bound frame via virtual text indicator
  local bufnr = h.child.api.nvim_get_current_buf()
  local ns = h.child.api.nvim_get_namespaces()["neodap-input-buffer"]
  local extmarks = h.child.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  local initial_virt_text = extmarks[1][4].virt_text[1][1]

  -- Frame name includes module prefix in JS debugger
  MiniTest.expect.equality(initial_virt_text:match("inner") ~= nil, true)

  -- Change focus to outer frame via DapFocus
  h:cmd("DapFocus " .. outer_frame_uri)
  h:wait(100)

  -- Check bound frame DID NOT change (pinned) via virtual text
  extmarks = h.child.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  local pinned_virt_text = extmarks[1][4].virt_text[1][1]

  -- Still inner, not outer (pinned)
  MiniTest.expect.equality(pinned_virt_text:match("inner") ~= nil, true)
end

T["input_buffer"]["shows input buffer with expression"] = function()
  local h = adapter.harness()
  h:fixture("debugger-vars")
  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Focus frame
  h:use_plugin("neodap.plugins.focus_cmd")
  h:cmd("DapFocus @frame")
  h:wait(50)

  h:use_plugin("neodap.plugins.completion")
  h:use_plugin("neodap.plugins.input_buffer")

  -- Hide statusline to avoid temp path in screenshot
  h.child.o.laststatus = 0

  -- Open input buffer in a split
  h.child.cmd("split")
  h.child.cmd("edit dap://input/@frame")
  vim.loop.sleep(100)

  -- Type a multi-character expression
  h.child.type_keys("data.name + ' has value ' + data.value")
  vim.loop.sleep(500) -- Wait for async completion

  -- Screenshot shows the input buffer with typed expression
  h.child.cmd("redraw")
  MiniTest.expect.reference_screenshot(h:take_screenshot())
end

return T
