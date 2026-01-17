-- Visual test for Targets group in tree buffer
-- Shows how Targets group displays only leaf sessions (actual debug targets)
local harness = require("helpers.test_harness")

-- JavaScript only - creates parent/child session hierarchy
local original_adapters = harness.enabled_adapters
harness.enabled_adapters = { "javascript" }

local T = harness.integration("targets_visual", function(T, ctx)
  T["Targets group shows only leaf sessions"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Open tree at Targets group
    h:open_tree("@debugger/targets")
    -- Wait for UI to settle (js-debug child session timing)
    h:wait(300)

    -- Expand leaf session to show Threads and Output groups
    h.child.type_keys("<CR>")
    h:wait(100)

    -- Navigate to Threads group and expand to show Thread
    h.child.cmd("call search('Threads')")
    h.child.type_keys("<CR>")
    h:wait(100)

    -- Expand Thread to show Stack
    h.child.type_keys("j")
    h.child.type_keys("<CR>")
    h:wait(100)

    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end

  T["tree shows Targets group with leaf sessions under it"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Open tree at debugger root to show all groups
    h:open_tree("@debugger")
    -- Wait for UI to settle (js-debug child session timing)
    h:wait(300)

    -- Expand leaf session under Targets to show Threads and Output groups
    h.child.cmd("call search('main.js')")
    h.child.type_keys("<CR>")
    h:wait(100)

    -- Navigate to Threads group and expand to show Thread
    h.child.cmd("call search('Threads')")
    h.child.type_keys("<CR>")
    h:wait(100)

    -- Expand Thread to show Stack
    h.child.type_keys("j")
    h.child.type_keys("<CR>")
    h:wait(100)

    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end
end)

-- Restore adapters
harness.enabled_adapters = original_adapters

return T
