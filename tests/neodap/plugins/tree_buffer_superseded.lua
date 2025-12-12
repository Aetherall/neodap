-- Tests for Config superseded logic and tree buffer filtering
-- Verifies that old terminated configs are hidden from the tree by default,
-- and that the T keymap toggles visibility of superseded configs.
local harness = require("helpers.test_harness")

-- Use Python-only for consistent tree layout
local original_adapters = harness.enabled_adapters
harness.enabled_adapters = { "python" }

local T = harness.integration("tree_buffer_superseded", function(T, ctx)

  -- Helper: count configs in the graph
  local function config_count(h)
    return h:query_count("/configs")
  end

  -- Helper: count visible configs (non-superseded)
  local function visible_config_count(h)
    return h:query_count("/visibleConfigs")
  end

  -- Helper: get tree buffer lines
  local function tree_lines(h)
    return h.child.api.nvim_buf_get_lines(0, 0, -1, false)
  end

  -- Helper: count Config lines in tree (match "Debug stop #N" pattern)
  local function count_config_lines(lines)
    local count = 0
    for _, line in ipairs(lines) do
      if line:find("Debug stop #%d") then count = count + 1 end
    end
    return count
  end

  -- Helper: launch and terminate a session completely
  local function launch_and_terminate(h)
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapContinue")
    h:wait_terminated()
  end

  T["new config marks older terminated configs as superseded"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")

    -- Launch #1 and let it complete
    launch_and_terminate(h)

    -- Should have 1 config, not superseded
    MiniTest.expect.equality(config_count(h), 1)
    MiniTest.expect.equality(visible_config_count(h), 1)

    -- Launch #2 — this should mark terminated #1 as superseded
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/configs[1]/targets")

    -- Should have 2 configs total, but only 1 visible (the new one)
    MiniTest.expect.equality(config_count(h), 2)
    MiniTest.expect.equality(visible_config_count(h), 1)
  end

  T["config marks itself superseded when it terminates after newer exists"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")

    -- Launch #1 (stops at entry, stays running)
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/configs[0]/targets[0]/threads")

    -- Launch #2 (also stops at entry)
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/configs[1]/targets")

    -- Both configs are active, both visible
    MiniTest.expect.equality(config_count(h), 2)
    MiniTest.expect.equality(visible_config_count(h), 2)

    -- Terminate #1 by continuing it (the short program finishes)
    h:cmd("DapFocus /configs[0]/targets[0]/threads[0]")
    h:cmd("DapContinue")
    h:wait_field("/configs[0]", "state", "terminated")

    -- Now #1 should be superseded (because #2 exists with higher index)
    MiniTest.expect.equality(config_count(h), 2)
    MiniTest.expect.equality(visible_config_count(h), 1)
  end

  T["latest terminated config is NOT superseded when no newer exists"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")

    -- Launch and let it complete
    launch_and_terminate(h)

    -- Config is terminated but NOT superseded (it's the latest)
    MiniTest.expect.equality(config_count(h), 1)
    MiniTest.expect.equality(visible_config_count(h), 1)
    local superseded = h:query_field("/configs[0]", "superseded")
    MiniTest.expect.equality(superseded, false)
  end

  T["tree hides superseded configs by default"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")

    -- Launch #1, let it terminate
    launch_and_terminate(h)

    -- Launch #2, let it terminate
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/configs[1]/targets[0]/threads/stacks[0]/frames[0]")

    -- Open tree at debugger root
    h:open_tree("@debugger")
    h:wait(300)

    local lines = tree_lines(h)

    -- Only Config #2 should be visible (latest), not #1 (superseded)
    local debug_count = count_config_lines(lines)
    MiniTest.expect.equality(debug_count, 1, "Only latest config should be visible")
  end

  T["T toggle reveals superseded configs"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")

    -- Launch #1, let it terminate
    launch_and_terminate(h)

    -- Launch #2, let it terminate
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/configs[1]/targets[0]/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /configs[1]/targets[0]/threads[0]")
    h:cmd("DapContinue")
    h:wait_field("/configs[1]", "state", "terminated")
    h:wait(200)

    -- Open tree
    h:open_tree("@debugger")
    h:wait(200)

    -- Default: only 1 Config visible
    local lines = tree_lines(h)
    local debug_count = count_config_lines(lines)
    MiniTest.expect.equality(debug_count, 1, "Default should show 1 config")

    -- Press T to toggle
    h.child.type_keys("T")
    h:wait(200)

    -- Now both should be visible
    lines = tree_lines(h)
    debug_count = count_config_lines(lines)
    MiniTest.expect.equality(debug_count, 2, "Toggle should show all 2 configs")

    -- Press T again to hide
    h.child.type_keys("T")
    h:wait(200)

    lines = tree_lines(h)
    debug_count = count_config_lines(lines)
    MiniTest.expect.equality(debug_count, 1, "Toggle back should hide superseded again")
  end

  T["active config is never superseded even with same name"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")

    -- Launch #1 (stops at entry, stays running)
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/configs[0]/targets[0]/threads")

    -- Launch #2 — should NOT mark active #1 as superseded
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/configs[1]")

    -- Both should be visible (both active)
    MiniTest.expect.equality(visible_config_count(h), 2)

    -- Verify #1 is not superseded
    local superseded = h:query_field("/configs[0]", "superseded")
    MiniTest.expect.equality(superseded, false)
  end

  T["restart reuses same config without superseding"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")

    -- Launch and stop at entry
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")

    -- Should have exactly 1 config
    MiniTest.expect.equality(config_count(h), 1)

    -- Restart
    h:cmd("DapRestartConfig")
    h:wait(1000)
    h:wait_url("/configs[0]/targets")

    -- Should STILL have exactly 1 config (reused, not a new one)
    MiniTest.expect.equality(config_count(h), 1)
    MiniTest.expect.equality(visible_config_count(h), 1)
  end
end)

harness.enabled_adapters = original_adapters

return T
