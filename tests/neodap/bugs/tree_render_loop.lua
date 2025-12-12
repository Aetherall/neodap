-- Bug: tree_buffer render loop causes 100% CPU
--
-- Root cause: render_tree() is called re-entrantly through CursorMoved autocmd
-- without debouncing. The cycle is:
--   1. render_tree() calls nvim_buf_set_lines()
--   2. Buffer change triggers CursorMoved autocmd
--   3. update_viewport() is called
--   4. update_viewport() calls render_tree() DIRECTLY (no debounce!)
--   5. Back to step 1 - infinite loop
--
-- This test verifies that tree rendering completes within a reasonable time
-- and doesn't get stuck in an infinite render loop.

local harness = require("helpers.test_harness")

local T = harness.integration("tree_render_loop", function(T, ctx)
  T["render_tree does not cause infinite loop"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")

    -- Launch and stop at breakpoint
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(300)

    -- Inject render counter into tree_buffer module
    h.child.lua([[
      _G._render_count = 0
      _G._render_start_time = vim.loop.hrtime()

      -- Patch vim.api.nvim_buf_set_lines to count calls
      local original_set_lines = vim.api.nvim_buf_set_lines
      vim.api.nvim_buf_set_lines = function(...)
        _G._render_count = _G._render_count + 1
        return original_set_lines(...)
      end
    ]])

    -- Open tree at debugger root - this triggers initial render
    h:open_tree("@debugger")

    -- Wait for initial render to complete (should be fast if no loop)
    -- Use vim.wait with a timeout to detect infinite loops
    local completed = h.child.lua([[
      -- Wait up to 2 seconds for rendering to stabilize
      -- If there's an infinite loop, _render_count will keep increasing
      local stable_count = nil
      local stable_for = 0

      return vim.wait(2000, function()
        if stable_count == _G._render_count then
          stable_for = stable_for + 1
          -- Consider stable after 10 consecutive checks (~100ms) with no new renders
          if stable_for >= 10 then
            return true
          end
        else
          stable_count = _G._render_count
          stable_for = 0
        end
        return false
      end, 10)
    ]])

    -- Get final render count
    local render_count = h:get("_G._render_count")
    local elapsed_ns = h.child.lua([[ return vim.loop.hrtime() - _G._render_start_time ]])
    local elapsed_ms = elapsed_ns / 1000000

    io.write(string.format("\nRender count: %d, elapsed: %.2f ms\n", render_count, elapsed_ms))

    -- Test assertions:
    -- 1. Rendering should stabilize (not loop forever)
    MiniTest.expect.equality(completed, true,
      string.format("Rendering should stabilize, but render_count kept increasing. Final count: %d", render_count))

    -- 2. Render count should be reasonable (not thousands from a loop)
    -- A normal render cycle might call nvim_buf_set_lines multiple times,
    -- but an infinite loop would call it hundreds/thousands of times
    MiniTest.expect.equality(render_count < 200, true,
      string.format("Expected < 200 nvim_buf_set_lines calls, got %d (possible render loop)", render_count))
  end

  T["expanding tree node completes without hang"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")

    -- Launch and stop at breakpoint
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(300)

    -- Open tree at debugger root
    h:open_tree("@debugger")
    h:wait(300)

    -- Find and expand Threads (this triggers re-render)
    h.child.fn.search("Threads")
    h:wait(100)

    -- Measure time to expand
    local timing_result = h.child.lua([[
      local start = vim.loop.hrtime()

      -- Simulate <CR> keypress to expand
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)

      -- Wait for expansion to complete (should be fast)
      local ok = vim.wait(2000, function()
        -- Check if buffer has thread entity (indicates expansion completed)
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        for _, line in ipairs(lines) do
          if line:match("Thread %d+:") then
            return true
          end
        end
        return false
      end, 10)

      local elapsed_ns = vim.loop.hrtime() - start
      return { ok = ok, elapsed_ms = elapsed_ns / 1000000 }
    ]])

    io.write(string.format("\nExpand completed: %s, elapsed: %.2f ms\n",
      tostring(timing_result.ok), timing_result.elapsed_ms))

    -- Expansion should complete within timeout
    MiniTest.expect.equality(timing_result.ok, true,
      "Tree expansion should complete within 2 seconds")

    -- Expansion should be fast (no infinite loop causing delays)
    MiniTest.expect.equality(timing_result.elapsed_ms < 1000, true,
      string.format("Expansion should complete in < 1000ms, took %.2f ms", timing_result.elapsed_ms))
  end

  T["multiple rapid expansions do not cause exponential slowdown"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.tree_buffer")

    -- Launch and stop at breakpoint
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
    h:wait(300)

    -- Open tree at debugger root
    h:open_tree("@debugger")
    h:wait(300)

    -- Perform multiple expand/collapse cycles
    local timing_result = h.child.lua([[
      local start = vim.loop.hrtime()
      local iterations = 5

      for i = 1, iterations do
        -- Find Threads and toggle
        vim.fn.search("Threads")
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
        vim.wait(100)

        -- Find it again and toggle back
        vim.fn.search("Threads")
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
        vim.wait(100)
      end

      local elapsed_ns = vim.loop.hrtime() - start
      return elapsed_ns / 1000000
    ]])

    io.write(string.format("\n5 expand/collapse cycles: %.2f ms\n", timing_result))

    -- Multiple cycles should complete in reasonable time
    -- If there's a loop, each cycle would compound the problem
    MiniTest.expect.equality(timing_result < 5000, true,
      string.format("5 expand/collapse cycles should complete in < 5000ms, took %.2f ms", timing_result))
  end
end)

return T
