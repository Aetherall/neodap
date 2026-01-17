local harness = require("helpers.test_harness")

local T = harness.integration("tree_buffer_debugger_nav", function(T, ctx)
  T["debugger tree navigate to global scope children"] = function()
    -- JavaScript only - global scope has many built-in variables
    if ctx.adapter_name ~= "javascript" then
      return
    end

    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(200)

    -- Open tree at debugger level
    h:open_tree("@debugger")
    h:wait(300)

    -- Expand leaf session to show Threads and Output groups
    h.child.cmd("call search('main.js')")
    h.child.type_keys("<CR>")
    h:wait(100)

    -- Expand Threads group to show Thread
    h.child.cmd("call search('Threads')")
    h.child.type_keys("<CR>")
    h:wait(100)

    -- Screenshot 1: Initial @debugger tree state with Threads expanded showing Thread
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })

    -- Navigate to Thread entity
    h.child.cmd("call search('Thread \\\\d')")  -- Match "Thread 0:" or "Thread 17:"
    h.child.type_keys("0")
    h:wait(100)

    -- Screenshot 2: Cursor on Thread
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })

    -- Toggle Thread (collapse stacks, then expand)
    h.child.type_keys("<CR>")
    h:wait(100)
    h.child.type_keys("<CR>")
    h:wait(200)

    -- Screenshot 3: After toggling Thread - should show Stack
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })

    -- Navigate to Stack and expand to show Frames
    h.child.cmd("call search('Stack')")
    h.child.type_keys("0")
    h.child.type_keys("<CR>")
    h:wait(200)

    -- Screenshot 4: After expanding Stack - should show Frame
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })

    -- Navigate to Frame and expand to show Scopes
    h.child.cmd("call search('main')")
    h.child.type_keys("0")
    h.child.type_keys("<CR>")
    h:wait(200)

    -- Screenshot 5: After expanding Frame - should show Scopes
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })

    -- Navigate to Global scope and expand to show Variables
    h.child.cmd("call search('Global')")
    h.child.type_keys("0")
    h.child.type_keys("<CR>")
    h:wait(200)

    -- Screenshot 6: After expanding Global - should show variables
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })

    -- Scroll down to show virtualization
    for _ = 1, 6 do
      h.child.type_keys("<C-d>")
      h:wait(50)
    end
    h:wait(200)

    -- Screenshot 7: Scrolled down - shows virtualization working
    MiniTest.expect.reference_screenshot(h:take_screenshot(), nil, { ignore_attr = true })
  end
end)

return T
