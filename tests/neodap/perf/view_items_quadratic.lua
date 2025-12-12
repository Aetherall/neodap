-- Performance test: View:items() iteration is O(n²) instead of O(n)
--
-- Root cause: items() calls _resolve_position(virtual_pos) for each position
-- (1, 2, 3...), and each _resolve_position starts from the root and traverses
-- down, calling _expansion_size_at() repeatedly without caching.
--
-- For n visible items:
--   - Current: O(n²) - each position requires traversing from root
--   - Expected: O(n) - single traversal yielding items incrementally
--
-- This test measures _expansion_size_at call count to demonstrate the issue.

local harness = require("helpers.test_harness")

local T = harness.integration("view_items_quadratic", function(T, ctx)
  T["_expansion_size_at calls grow quadratically with visible items"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")

    -- Launch and stop at breakpoint to get a session with threads/stacks/frames
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(300)

    -- Inject counter for _expansion_size_at calls
    h.child.lua([[
      local neo = require("neograph")

      -- Store original function
      _G._orig_expansion_size_at = neo.View._expansion_size_at

      -- Counter
      _G._expansion_size_at_count = 0

      -- Patch to count calls
      neo.View._expansion_size_at = function(self, ...)
        _G._expansion_size_at_count = _G._expansion_size_at_count + 1
        return _G._orig_expansion_size_at(self, ...)
      end
    ]])

    -- Open tree at debugger root - this triggers items() iteration
    h:open_tree("@debugger")
    h:wait(300)

    -- Get call count after initial render
    local initial_count = h:get("_G._expansion_size_at_count")

    -- Reset counter
    h.child.lua([[ _G._expansion_size_at_count = 0 ]])

    -- Expand Threads to add more visible items
    h.child.fn.search("Threads")
    h:wait(100)
    h.child.lua([[
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
    ]])
    h:wait(300)

    local after_expand_count = h:get("_G._expansion_size_at_count")

    -- Reset counter
    h.child.lua([[ _G._expansion_size_at_count = 0 ]])

    -- Expand Scopes to add even more visible items
    h.child.fn.search("Scopes")
    h:wait(100)
    h.child.lua([[
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
    ]])
    h:wait(300)

    local after_scopes_count = h:get("_G._expansion_size_at_count")

    -- Get visible item count
    local visible_count = h.child.lua([[
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local count = 0
      for _, line in ipairs(lines) do
        if line ~= "" and not line:match("^~") then
          count = count + 1
        end
      end
      return count
    ]])

    -- Restore original function
    h.child.lua([[
      local neo = require("neograph")
      neo.View._expansion_size_at = _G._orig_expansion_size_at
    ]])

    -- Log results
    io.write(string.format("\nInitial render: %d _expansion_size_at calls\n", initial_count))
    io.write(string.format("After Threads expand: %d _expansion_size_at calls\n", after_expand_count))
    io.write(string.format("After Scopes expand: %d _expansion_size_at calls\n", after_scopes_count))
    io.write(string.format("Visible items: %d\n", visible_count))

    -- Calculate ratio - if O(n²), doubling visible items quadruples calls
    -- For O(n), calls should be roughly proportional to visible items
    local calls_per_item_initial = initial_count / math.max(1, visible_count / 3)
    local calls_per_item_final = after_scopes_count / math.max(1, visible_count)

    io.write(string.format("Calls per visible item (initial): %.1f\n", calls_per_item_initial))
    io.write(string.format("Calls per visible item (final): %.1f\n", calls_per_item_final))

    -- For O(n), calls_per_item should stay roughly constant
    -- For O(n²), calls_per_item increases with n
    -- We expect this test to FAIL currently, demonstrating the bug
    --
    -- With O(n) iteration, we'd expect maybe 2-5 calls per visible item
    -- With O(n²) iteration, we see 10-50+ calls per visible item
    MiniTest.expect.equality(calls_per_item_final < 10, true,
      string.format(
        "Expected < 10 _expansion_size_at calls per visible item (O(n) behavior), " ..
        "got %.1f calls/item (indicates O(n²) bug). " ..
        "Total calls: %d, visible items: %d",
        calls_per_item_final, after_scopes_count, visible_count))
  end

  T["items() iteration count scales linearly with visible items"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")

    -- Launch and stop at breakpoint
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(300)

    -- Inject counter for _resolve_position calls
    h.child.lua([[
      local neo = require("neograph")
      _G._orig_resolve_position = neo.View._resolve_position
      _G._resolve_position_count = 0

      neo.View._resolve_position = function(self, ...)
        _G._resolve_position_count = _G._resolve_position_count + 1
        return _G._orig_resolve_position(self, ...)
      end
    ]])

    -- Open tree
    h:open_tree("@debugger")
    h:wait(300)

    -- Reset counter
    h.child.lua([[ _G._resolve_position_count = 0 ]])

    -- Trigger a re-render by scrolling
    h.child.lua([[
      vim.cmd("normal! G")  -- Go to end
      vim.wait(100)
      vim.cmd("normal! gg") -- Go to start
    ]])
    h:wait(300)

    local resolve_count = h:get("_G._resolve_position_count")

    -- Get visible item count
    local visible_count = h.child.lua([[
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local count = 0
      for _, line in ipairs(lines) do
        if line ~= "" and not line:match("^~") then
          count = count + 1
        end
      end
      return count
    ]])

    -- Restore
    h.child.lua([[
      local neo = require("neograph")
      neo.View._resolve_position = _G._orig_resolve_position
    ]])

    io.write(string.format("\n_resolve_position calls: %d\n", resolve_count))
    io.write(string.format("Visible items: %d\n", visible_count))
    io.write(string.format("Ratio: %.1f\n", resolve_count / math.max(1, visible_count)))

    -- For O(n) iteration, _resolve_position should be called ~1x per visible item
    -- Currently it's called 1x per item, but each call is O(n), making total O(n²)
    -- This test verifies the call count is reasonable (the O(n²) is hidden inside)
    MiniTest.expect.equality(resolve_count <= visible_count * 2, true,
      string.format(
        "Expected <= %d _resolve_position calls (2x visible items), got %d",
        visible_count * 2, resolve_count))
  end

  T["measure render time with many expanded nodes"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")

    -- Launch and stop at breakpoint
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(300)

    -- Open tree
    h:open_tree("@debugger")
    h:wait(300)

    -- Expand multiple nodes to increase visible items
    local nodes_to_expand = { "Threads", "Scopes", "Local" }
    for _, node in ipairs(nodes_to_expand) do
      h.child.fn.search(node)
      h:wait(50)
      h.child.lua([[
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
      ]])
      h:wait(200)
    end

    -- Count visible items
    local visible_count = h.child.lua([[
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local count = 0
      for _, line in ipairs(lines) do
        if line ~= "" and not line:match("^~") then
          count = count + 1
        end
      end
      return count
    ]])

    -- Measure time for a full re-render by forcing cursor move
    local render_time_ms = h.child.lua([[
      -- Force re-render by moving cursor and measure the actual render time
      vim.cmd("normal! gg")
      vim.cmd("redraw!")

      local start = vim.loop.hrtime()
      vim.cmd("normal! G")
      vim.cmd("redraw!")
      local elapsed_ns = vim.loop.hrtime() - start

      return elapsed_ns / 1000000
    ]])

    io.write(string.format("\nVisible items: %d\n", visible_count))
    io.write(string.format("Render time: %.2f ms\n", render_time_ms))
    io.write(string.format("Time per item: %.2f ms\n", render_time_ms / math.max(1, visible_count)))

    -- With O(n) iteration, render should be fast even with many items
    -- With O(n²), render time grows quadratically
    -- For 20 items, O(n) should be < 50ms, O(n²) could be > 200ms
    local expected_max_ms = 100  -- Generous limit
    MiniTest.expect.equality(render_time_ms < expected_max_ms, true,
      string.format(
        "Render with %d visible items should complete in < %d ms, took %.2f ms. " ..
        "This may indicate O(n²) iteration in items().",
        visible_count, expected_max_ms, render_time_ms))
  end
end)

return T
