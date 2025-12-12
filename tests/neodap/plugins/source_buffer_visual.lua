-- Visual tests for source_buffer plugin
-- JavaScript only - tests virtual source loading
local harness = require("helpers.test_harness")

local adapter = harness.for_adapter("javascript")

local T = MiniTest.new_set({
  hooks = adapter.hooks,
})

T["source_buffer_visual"] = MiniTest.new_set()

T["source_buffer_visual"]["loads eval'd code source content"] = function()
  local h = adapter.harness()
  h:fixture("eval-source")
  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  h:use_plugin("neodap.plugins.source_buffer")

  -- Verify we stopped in the eval'd function
  local frame_name = h:query_field("@frame", "name")
  MiniTest.expect.equality(frame_name, "global.evalFunction")

  -- Get the source key (should be <eval>/VM...)
  local source_key = h:query_field("@frame/source[0]", "key")
  MiniTest.expect.equality(source_key:match("^<eval>/") ~= nil, true)

  -- Open the source buffer
  h.child.cmd("edit dap://source/source:" .. source_key)

  -- Wait for async content to load (poll until not "-- Loading...")
  local loaded = false
  for _ = 1, 40 do  -- 40 * 50ms = 2000ms max
    h:wait(50)
    local lines = h.child.api.nvim_buf_get_lines(0, 0, 1, false)
    if lines[1] and lines[1] ~= "-- Loading..." then
      loaded = true
      break
    end
  end
  MiniTest.expect.equality(loaded, true)

  -- Verify content contains the eval'd function
  local content = table.concat(h.child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  MiniTest.expect.equality(content:match("function evalFunction") ~= nil, true)
  MiniTest.expect.equality(content:match("debugger") ~= nil, true)
  MiniTest.expect.equality(content:match("const secret = 42") ~= nil, true)
end

T["source_buffer_visual"]["renders js source with functions"] = function()
  local h = adapter.harness()
  h:fixture("with-function")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  h:use_plugin("neodap.plugins.source_buffer")

  -- The frame's source is the file we're debugging
  local source_key = h:query_field("@frame/source[0]", "key")
  MiniTest.expect.equality(source_key ~= nil, true)

  -- Open the source buffer
  h.child.cmd("edit dap://source/source:" .. source_key)
  h:wait(500)

  h.child.cmd("redraw")
  MiniTest.expect.reference_screenshot(h:take_screenshot())
end

T["source_buffer_visual"]["renders error for non-existent source"] = function()
  local h = adapter.harness()
  h:fixture("simple-vars")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  h:use_plugin("neodap.plugins.source_buffer")

  -- Try to open a non-existent source
  h.child.cmd("edit dap://source/source:nonexistent-key-12345")

  h.child.cmd("redraw")
  MiniTest.expect.reference_screenshot(h:take_screenshot())
end

return T
