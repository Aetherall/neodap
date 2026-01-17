-- Tree buffer entity keybinds tests
-- Uses Python-only because tests use screenshots that need consistent visual output
local harness = require("helpers.test_harness")

-- Keep as Python-only because tree UI screenshots differ between adapters
local original_adapters = harness.enabled_adapters
harness.enabled_adapters = { "python" }

local T = harness.integration("tree_buffer_keybinds", function(T, ctx)
  -- Tests expand/collapse toggle AND verifies the fix for neograph's stale item.expanded
  T["Enter toggles expand collapse"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 1")
    h:wait_url("/breakpoints(line=1)")

    h:open_tree("@debugger")
    h:wait(100)

    -- Take initial screenshot (should show Debugger expanded with breakpoint)
    h.child.cmd("redraw")
    local initial_screenshot = h:take_screenshot()

    -- Press Enter to collapse
    h.child.type_keys("<CR>")
    h:wait(100)

    h.child.cmd("redraw")
    local collapsed_screenshot = h:take_screenshot()

    -- Press Enter again to expand
    h.child.type_keys("<CR>")
    h:wait(100)

    h.child.cmd("redraw")
    local expanded_screenshot = h:take_screenshot()

    -- Verify initial state matches reference
    MiniTest.expect.reference_screenshot(initial_screenshot)
    -- Collapsed should be different from initial (children hidden)
    assert(collapsed_screenshot.text ~= initial_screenshot.text, "Collapsed state should be different from initial")
    -- Expanded should be different from collapsed (children visible again)
    -- Note: expanded may differ from initial because child expansion state isn't preserved
    assert(expanded_screenshot.text ~= collapsed_screenshot.text, "Expanded state should be different from collapsed")
  end

  -- Tests gd navigation with real debug session - verifies Frame navigation works
  T["gd on Frame opens source file"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Use show_root=true so the Frame is visible at root level
    h:use_plugin("neodap.plugins.tree_buffer", { show_root = true })

    h:focus("@frame")
    local expected_line = h:query_field("@frame", "line")

    -- Open tree at frame
    h:open_tree("@frame")
    h:wait(100)

    -- Press gd on frame
    h.child.type_keys("gd")
    h:wait(100)

    -- Verify we're in the source file at the correct line
    local bufname = h.child.api.nvim_buf_get_name(0)
    local cursor = h.child.api.nvim_win_get_cursor(0)
    local expected_path = h:query_field("@frame/source[0]", "path")

    MiniTest.expect.equality(bufname, expected_path)
    MiniTest.expect.equality(cursor[1], expected_line)
  end
end)

-- Restore original adapters
harness.enabled_adapters = original_adapters

return T
