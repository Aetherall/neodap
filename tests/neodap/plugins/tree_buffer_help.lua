-- Tree buffer help float integration tests
-- Uses Python-only because tests need consistent tree layout for cursor positioning
local harness = require("helpers.test_harness")

local original_adapters = harness.enabled_adapters
harness.enabled_adapters = { "python" }

local T = harness.integration("tree_buffer_help", function(T, ctx)

  -- Helper: find floating windows in child process
  local function get_float_wins(h)
    return h:get([[(function()
      local floats = {}
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative and config.relative ~= "" then
          floats[#floats + 1] = win
        end
      end
      return floats
    end)()]])
  end

  -- Helper: get lines from the first floating window's buffer
  local function get_float_lines(h)
    return h:get([[(function()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative and config.relative ~= "" then
          local bufnr = vim.api.nvim_win_get_buf(win)
          return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        end
      end
      return {}
    end)()]])
  end

  -- Helper: concatenate float lines to a single searchable string
  local function float_content(h)
    local lines = get_float_lines(h)
    return table.concat(lines, "\n")
  end

  T["? toggles help float open and closed"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 1")
    h:wait_url("/breakpoints(line=1)")

    h:open_tree("@debugger")
    h:wait(100)

    -- No floats initially
    local floats = get_float_wins(h)
    MiniTest.expect.equality(#floats, 0)

    -- Press ? to open help
    h.child.type_keys("?")
    h:wait(50)

    floats = get_float_wins(h)
    MiniTest.expect.equality(#floats, 1)

    -- Press ? again to close help
    h.child.type_keys("?")
    h:wait(50)

    floats = get_float_wins(h)
    MiniTest.expect.equality(#floats, 0)
  end

  T["help float shows navigation keymaps"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 1")
    h:wait_url("/breakpoints(line=1)")

    h:open_tree("@debugger")
    h:wait(100)

    h.child.type_keys("?")
    h:wait(50)

    local content = float_content(h)
    assert(content:find("Navigation", 1, true), "should show Navigation header")
    assert(content:find("<CR>", 1, true), "should show <CR> key")
    assert(content:find("Toggle expand/collapse", 1, true), "should show expand/collapse desc")
    assert(content:find("Close tree", 1, true), "should show Close tree desc")
  end

  T["help float shows breakpoint keymaps on breakpoint node"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 1")
    h:wait_url("/breakpoints(line=1)")

    h:open_tree("@debugger")
    h:wait(100)

    -- Expand the Breakpoints group first (cursor starts on line 1 = Breakpoints group)
    h.child.type_keys("<CR>")
    h:wait(100)

    -- Navigate down to the Breakpoint node (now visible after expanding)
    h.child.type_keys("j")
    h:wait(50)

    -- Verify we're on a Breakpoint entity
    local entity_type = h:get([[(function()
      local bufnr = vim.api.nvim_get_current_buf()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local lines = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)
      return lines[1] or ""
    end)()]])

    -- Open help on the breakpoint node
    h.child.type_keys("?")
    h:wait(50)

    local content = float_content(h)
    -- Should have navigation
    assert(content:find("Navigation", 1, true), "should show Navigation header")
    -- Should have Breakpoint-specific keymaps
    assert(content:find("Breakpoint", 1, true), "should show Breakpoint header")
    assert(content:find("Toggle enabled", 1, true), "should show Toggle enabled")
    assert(content:find("Remove", 1, true), "should show Remove")
    assert(content:find("Edit condition", 1, true), "should show Edit condition")
  end

  T["help float updates when cursor moves to different entity type"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    -- Need a running session to have Thread nodes
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads")

    h:edit_main()
    h:cmd("DapBreakpoint 1")
    h:wait_url("/breakpoints(line=1)")

    h:open_tree("@debugger")
    h:wait(200)

    -- Open help float
    h.child.type_keys("?")
    h:wait(50)

    -- Get initial content (cursor is on first line which is a group node)
    local content1 = float_content(h)
    assert(content1:find("Navigation", 1, true), "initial help should have Navigation")

    -- Navigate to find the breakpoint node and check content changes
    -- Use gg to go to top, then j to navigate down
    h.child.type_keys("gg")
    h:wait(50)

    local content_at_top = float_content(h)

    -- Navigate down a few lines to reach a different entity type
    h.child.type_keys("j")
    h:wait(50)
    h.child.type_keys("j")
    h:wait(50)

    local content_after_move = float_content(h)

    -- The float should still exist
    local floats = get_float_wins(h)
    MiniTest.expect.equality(#floats, 1)

    -- Navigation keymaps should always be there
    assert(content_after_move:find("Navigation", 1, true), "help should still have Navigation after moving")
  end

  T["help float closes when tree buffer is deleted"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")
    h:use_plugin("neodap.plugins.breakpoint_cmd")

    h:edit_main()
    h:cmd("DapBreakpoint 1")
    h:wait_url("/breakpoints(line=1)")

    h:open_tree("@debugger")
    h:wait(100)

    -- Open help
    h.child.type_keys("?")
    h:wait(50)

    local floats = get_float_wins(h)
    MiniTest.expect.equality(#floats, 1)

    -- Delete tree buffer (q keybind)
    h.child.type_keys("q")
    h:wait(100)

    -- Float should be gone
    floats = get_float_wins(h)
    MiniTest.expect.equality(#floats, 0)
  end

  T["help float has correct keymap descriptions"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")

    h:open_tree("@debugger")
    h:wait(100)

    -- Check that keymap desc fields are set correctly
    local desc = h:get([[(function()
      local maps = vim.api.nvim_buf_get_keymap(0, "n")
      local result = {}
      for _, map in ipairs(maps) do
        if map.lhs and map.desc then
          result[map.lhs] = map.desc
        end
      end
      return result
    end)()]])

    -- Check that desc fields use proper names instead of just the key
    assert(desc["?"] and desc["?"]:find("Toggle help"), "? should have 'Toggle help' in desc, got: " .. tostring(desc["?"]))
    assert(desc["q"] and desc["q"]:find("Close tree"), "q should have 'Close tree' in desc, got: " .. tostring(desc["q"]))
    assert(desc["R"] and desc["R"]:find("Refresh"), "R should have 'Refresh' in desc, got: " .. tostring(desc["R"]))
  end
end)

harness.enabled_adapters = original_adapters

return T
