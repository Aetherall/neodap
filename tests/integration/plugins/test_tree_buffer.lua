local harness = require("helpers.test_harness")

local T = harness.integration("visual", function(T, ctx)
  T["tree_buffer renders frame with scopes"] = function()
    local h = ctx.create()
    h:setup_visual()
    h:use_plugin("neodap.plugins.tree_buffer", { show_root = true })

    h:fixture("nested-dict")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step to define the variable (so nested dict is defined)
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)")
    h:wait(200)  -- Wait for new stack to be created
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:query_call("@frame", "fetchScopes")
    h:wait_url("@frame/scopes[0]")

    -- Open tree buffer at frame
    h:open_tree("@frame")

    -- With show_root=true and Frame as root, scopes edge is made eager by build_query
    -- so scopes are already visible (Frame + 2 Scopes = 3 items minimum)
    h:wait(100)

    -- Verify tree has content (frame shows scopes)
    MiniTest.expect.equality(h:line_count() >= 2, true)
  end

  T["tree_buffer renders thread with stack"] = function()
    local h = ctx.create()
    h:setup_visual()
    h:use_plugin("neodap.plugins.tree_buffer")

    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Open tree buffer at thread
    h:open_tree("@thread")

    -- Verify tree has content
    MiniTest.expect.equality(h:line_count() >= 1, true)
  end
end)

return T
