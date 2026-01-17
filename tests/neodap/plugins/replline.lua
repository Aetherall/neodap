-- Tests for replline plugin (floating REPL input)
local harness = require("helpers.test_harness")

local adapter = harness.for_adapter("javascript")

local T = MiniTest.new_set({
  hooks = adapter.hooks,
})

T["replline"] = MiniTest.new_set()

T["replline"]["opens floating window with dap-input buffer"] = function()
  local h = adapter.harness()

  -- Setup plugins
  h:use_plugin("neodap.plugins.completion")
  h:use_plugin("neodap.plugins.input_buffer")
  h:use_plugin("neodap.plugins.replline")

  -- Open a regular file first to have a window context
  h:cmd("edit /tmp/test.txt")
  h.child.api.nvim_buf_set_lines(0, 0, -1, false, { "line 1", "line 2", "line 3", "line 4", "line 5" })
  h.child.api.nvim_win_set_cursor(0, { 2, 0 })
  h.child.cmd("set laststatus=0")

  -- Open replline via command
  h:cmd("DapReplLine")
  h:wait(200)

  -- Check that a floating window was created with dap-input buffer
  local config = h.child.api.nvim_win_get_config(0)
  local bufname = h.child.api.nvim_buf_get_name(0)
  local buftype = h.child.bo.buftype

  MiniTest.expect.equality(config.relative ~= '', true)
  MiniTest.expect.equality(bufname:match("dap://input/@frame$") ~= nil, true)
  MiniTest.expect.equality(buftype, "acwrite")

  -- Screenshot shows floating REPL line over the file content
  h.child.cmd("redraw")
  MiniTest.expect.reference_screenshot(h:take_screenshot())
end

T["replline"]["close() closes the floating window"] = function()
  local h = adapter.harness()

  h:use_plugin("neodap.plugins.completion")
  h:use_plugin("neodap.plugins.input_buffer")
  h:use_plugin("neodap.plugins.replline")

  h:cmd("edit /tmp/test.txt")

  -- Open replline
  h:cmd("DapReplLine")
  h:wait(100)
  local win_before = h.child.api.nvim_get_current_win()

  -- Close with Escape (user would press Escape in normal mode)
  h.child.type_keys("<Esc>")
  h:wait(50)
  h.child.type_keys("<Esc>")
  h:wait(100)

  -- Check window was closed
  local win_valid = h.child.api.nvim_win_is_valid(win_before)
  MiniTest.expect.equality(win_valid, false)
end

T["replline"]["DapReplLine command works"] = function()
  local h = adapter.harness()

  h:use_plugin("neodap.plugins.completion")
  h:use_plugin("neodap.plugins.input_buffer")
  h:use_plugin("neodap.plugins.replline")

  h:cmd("edit /tmp/test.txt")

  -- Use the command
  h:cmd("DapReplLine")
  h:wait(200)

  -- Check floating window exists
  local config = h.child.api.nvim_win_get_config(0)
  MiniTest.expect.equality(config.relative ~= '', true)
end

T["replline"]["submitting expression shows result in window"] = function()
  local h = adapter.harness()
  h:fixture("debugger-vars")
  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Setup plugins
  h:use_plugin("neodap.plugins.completion")
  h:use_plugin("neodap.plugins.input_buffer")
  h:use_plugin("neodap.plugins.replline")

  -- Open replline
  h:cmd("DapReplLine")
  h:wait(100)
  local floating_win = h.child.api.nvim_get_current_win()

  -- Type expression and submit
  h.child.type_keys("x")
  h:wait(50)
  h.child.type_keys("<CR>")
  h:wait(500)

  -- Check window is still open (result stays visible)
  local win_valid = h.child.api.nvim_win_is_valid(floating_win)
  MiniTest.expect.equality(win_valid, true)
end

T["replline"]["shows typed expression in floating window"] = function()
  local h = adapter.harness()
  h:fixture("debugger-vars")
  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  h:use_plugin("neodap.plugins.completion")
  h:use_plugin("neodap.plugins.input_buffer")
  h:use_plugin("neodap.plugins.replline")

  -- Hide statusline to avoid temp path in screenshot
  h.child.cmd("set laststatus=0")

  -- Open the source file in a split first for context
  h:edit_main()
  h:wait(100)

  -- Open replline and type expression
  h:cmd("DapReplLine")
  h:wait(100)

  h.child.type_keys("message + ' - ' + count")
  h:wait(100)

  -- Screenshot shows the floating REPL with typed expression
  h.child.cmd("redraw")
  MiniTest.expect.reference_screenshot(h:take_screenshot())
end

T["replline"]["Escape in normal mode closes window"] = function()
  local h = adapter.harness()

  h:use_plugin("neodap.plugins.completion")
  h:use_plugin("neodap.plugins.input_buffer")
  h:use_plugin("neodap.plugins.replline")

  h:cmd("edit /tmp/test.txt")

  h:cmd("DapReplLine")
  h:wait(100)
  local floating_win = h.child.api.nvim_get_current_win()

  -- Exit insert mode and press Escape
  h.child.type_keys("<Esc>")
  h:wait(50)
  h.child.type_keys("<Esc>")
  h:wait(100)

  local win_valid = h.child.api.nvim_win_is_valid(floating_win)
  MiniTest.expect.equality(win_valid, false)
end

return T
