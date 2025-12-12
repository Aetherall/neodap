-- Visual tests for inline_values plugin
-- Tests inline variable value display as virtual text
local harness = require("helpers.test_harness")

local T = harness.integration("inline_values", function(T, ctx)
  -------------------------------------------------------------------------------
  -- Basic Display Tests
  -------------------------------------------------------------------------------

  T["shows inline values when stopped"] = function()
    local h = ctx.create()
    -- Use typed_vars - single-char vars like x,y are filtered out
    h:fixture("typed-vars")
    h:setup_visual()
    h:init_plugin("neodap.plugins.inline_values", nil, "iv_api")
    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step to have variables in scope (typed_vars: 6 lines, stepping 1->2->3->4)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=3)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=4)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:focus("@frame", 300)
    h:wait(500)

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["updates values after stepping"] = function()
    local h = ctx.create()
    h:fixture("typed-vars")
    h:setup_visual()
    h:init_plugin("neodap.plugins.inline_values", nil, "iv_api")
    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step to have variables in scope (3 steps = 3 variables, 1->2->3->4)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=3)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=4)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:focus("@frame", 300)
    -- Wait for inline values to render (async virtual text placement)
    h:wait(500)

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  T["shows multiple variables"] = function()
    local h = ctx.create()
    h:fixture("typed-vars")
    h:setup_visual()
    h:init_plugin("neodap.plugins.inline_values", nil, "iv_api")
    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step to have variables in scope (3 steps = 3 variables, 1->2->3->4)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=3)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=4)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:focus("@frame", 300)
    -- Wait for inline values to render (async virtual text placement)
    h:wait(500)

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  -------------------------------------------------------------------------------
  -- Cleanup Tests
  -------------------------------------------------------------------------------

  T["api.clear clears all values"] = function()
    local h = ctx.create()
    h:fixture("typed-vars")
    h:setup_visual()
    h:init_plugin("neodap.plugins.inline_values", nil, "iv_api")
    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step through typed_vars (6 lines, 1->2->3->4)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=3)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=4)[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:focus("@frame", 300)
    h:wait(500)

    -- Clear via API - values should disappear
    h:call_plugin("iv_api", "clear")
    h:wait(100)

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  -------------------------------------------------------------------------------
  -- No Values Tests
  -------------------------------------------------------------------------------

  T["no values when no focused frame"] = function()
    local h = ctx.create()

    h:setup_visual()
    h:init_plugin("neodap.plugins.inline_values", nil, "iv_api")

    local buf = h.child.api.nvim_create_buf(false, true)
    h.child.api.nvim_set_current_buf(buf)
    h.child.api.nvim_buf_set_lines(buf, 0, -1, false, { "x = 1", "y = 2", "print(x + y)" })
    h.child.cmd("setlocal filetype=python")
    h:wait(200)

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end

  -------------------------------------------------------------------------------
  -- Configuration Tests
  -------------------------------------------------------------------------------

  T["respects max_length truncation"] = function()
    local h = ctx.create()
    h:fixture("nested-dict")
    h:setup_visual()
    h:init_plugin("neodap.plugins.inline_values", { max_length = 15 }, "iv_api")
    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")  -- nested_dict: line 1 -> 2
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:focus("@frame", 300)
    h:wait(500)

    MiniTest.expect.reference_screenshot(h:take_screenshot())
  end
end)

return T
