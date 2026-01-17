-- Tests for dap_completion plugin (DAP-powered omnifunc)
local harness = require("helpers.test_harness")

local adapter = harness.for_adapter("javascript")

local T = MiniTest.new_set({
  hooks = adapter.hooks,
})

T["dap_completion"] = MiniTest.new_set()

T["dap_completion"]["shows completion menu for variable prefix"] = function()
  local h = adapter.harness()
  h:fixture("debugger-vars")
  h:use_plugin("neodap.plugins.completion")
  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  -- Hide statusline to avoid temp path in screenshot
  h.child.cmd("set laststatus=0")

  -- Create a scratch buffer and enable completion
  h:cmd("enew")
  h.child.cmd("setlocal buftype=nofile")
  h:cmd("DapCompleteEnable")

  -- Type "my" and trigger completion
  h.child.type_keys("i", "my")
  vim.loop.sleep(50)
  h.child.type_keys("<C-x><C-o>")
  vim.loop.sleep(500) -- Wait for async completions

  h.child.cmd("redraw")
  MiniTest.expect.reference_screenshot(h:take_screenshot())
end

T["dap_completion"]["shows completion menu for property access"] = function()
  local h = adapter.harness()
  h:fixture("debugger-vars")
  h:use_plugin("neodap.plugins.completion")
  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  h.child.cmd("set laststatus=0")

  h:cmd("enew")
  h.child.cmd("setlocal buftype=nofile")
  h:cmd("DapCompleteEnable")

  -- Type "myObject." and trigger completion for properties
  h.child.type_keys("i", "myObject.")
  vim.loop.sleep(50)
  h.child.type_keys("<C-x><C-o>")
  vim.loop.sleep(500)

  h.child.cmd("redraw")
  MiniTest.expect.reference_screenshot(h:take_screenshot())
end

T["dap_completion"]["shows no completions without debug session"] = function()
  local h = adapter.harness()

  -- Setup dap_completion WITHOUT launching a debug session
  h:use_plugin("neodap.plugins.completion")
  h.child.cmd("set laststatus=0")

  h:cmd("enew")
  h.child.cmd("setlocal buftype=nofile")
  h:cmd("DapCompleteEnable")

  -- Type and trigger completion - should show nothing
  h.child.type_keys("i", "test")
  vim.loop.sleep(50)
  h.child.type_keys("<C-x><C-o>")
  vim.loop.sleep(200)

  h.child.cmd("redraw")
  MiniTest.expect.reference_screenshot(h:take_screenshot())
end

T["dap_completion"]["DapCompleteEnable command enables completion"] = function()
  local h = adapter.harness()
  h:fixture("debugger-vars")
  h:use_plugin("neodap.plugins.completion")
  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

  h.child.cmd("set laststatus=0")

  h:cmd("enew")
  h.child.cmd("setlocal buftype=nofile")

  -- Use command to enable completion
  h:cmd("DapCompleteEnable")

  -- Type and trigger completion
  h.child.type_keys("i", "val")
  vim.loop.sleep(50)
  h.child.type_keys("<C-x><C-o>")
  vim.loop.sleep(500)

  h.child.cmd("redraw")
  MiniTest.expect.reference_screenshot(h:take_screenshot())
end

return T
