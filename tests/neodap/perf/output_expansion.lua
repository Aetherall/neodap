-- Performance test: measure output node expansion time with many logs
--
-- This test measures how long it takes to expand the Output node in the tree
-- when there are many structured log entries. The scripts generate 10k logs.
-- NOTE: query_count returns max 1000 due to view limit in url.lua

local harness = require("helpers.test_harness")

local T = harness.integration("output_expansion_perf", function(T, ctx)
  T["measure output expansion time with many logs"] = function()
    local h = ctx.create()
    h:fixture("massive-logs")
    h:use_plugin("neodap.plugins.tree_buffer")

    -- Launch and wait for termination (script generates 10k logs then exits)
    h:cmd("DapLaunch Debug")
    h:wait_terminated()

    -- Query output count (capped at ~1000 due to view limit)
    local output_count = h:query_count("/sessions/outputs")
    io.write(string.format("\nOutput count (capped): %d\n", output_count))

    -- Open tree at debugger root
    h:open_tree("@debugger")
    h:wait(500)

    -- Find Output node (Targets is already expanded showing session and its children)
    h.child.fn.search("Output")
    h:wait(100)

    -- Measure expansion time using Lua in the child process
    local timing_result = h.child.lua([[
      local start = vim.loop.hrtime()

      -- Simulate <CR> keypress to expand
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)

      -- Process all pending events (including tree re-render)
      vim.wait(10000, function()
        -- Wait for buffer to have output lines (indicates expansion completed)
        -- Output items from massive-logs are JSON lines containing "index"
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        for _, line in ipairs(lines) do
          if line:match('"index"') or line:match('"timestamp"') then
            return true
          end
        end
        return false
      end, 50)

      local elapsed_ns = vim.loop.hrtime() - start
      return elapsed_ns / 1000000  -- Convert to milliseconds
    ]])

    local elapsed_ms = timing_result

    -- Log the timing
    io.write(string.format("Time to expand Output node: %.2f ms\n", elapsed_ms))

    -- Get buffer lines to verify output items are visible
    local lines = h.child.api.nvim_buf_get_lines(0, 0, -1, false)
    local visible_output_count = 0
    for _, line in ipairs(lines) do
      if line:match('"index"') or line:match('"timestamp"') then
        visible_output_count = visible_output_count + 1
      end
    end

    io.write(string.format("Visible output lines: %d\n", visible_output_count))

    -- Should have some output lines visible
    MiniTest.expect.equality(visible_output_count > 0, true,
      string.format("Should have output lines visible after expansion. Found %d visible output lines.\nFirst 20 lines:\n%s",
        visible_output_count, table.concat(vim.list_slice(lines, 1, 20) or {}, "\n")))

    -- Performance assertion: expansion should complete quickly (< 500ms)
    -- After debouncing fix: Python ~11ms, JavaScript ~64ms
    MiniTest.expect.equality(elapsed_ms < 500, true,
      string.format("Output expansion should complete in < 500ms, took %.2f ms", elapsed_ms))
  end

  T["measure output count query time"] = function()
    local h = ctx.create()
    h:fixture("massive-logs")

    -- Launch and wait for termination
    h:cmd("DapLaunch Debug")
    h:wait_terminated()

    -- Measure query time for output count
    local start_time = h.child.fn.reltime()

    local output_count = h:query_count("/sessions/outputs")

    local elapsed = h.child.fn.reltimefloat(h.child.fn.reltime(start_time))
    local elapsed_ms = elapsed * 1000

    io.write(string.format("\nOutput count (capped): %d\n", output_count))
    io.write(string.format("Time to query output count: %.2f ms\n", elapsed_ms))

    -- Should have captured some outputs
    MiniTest.expect.equality(output_count > 0, true,
      string.format("Should have captured some outputs, got %d", output_count))
  end
end)

return T
