-- Performance test: measure output node toggle time with streaming logs
--
-- This test measures how long it takes to expand/collapse the Output node
-- when there are many log entries and more are streaming in.
-- Uses streaming-logs fixture: 1000 logs immediately, then 1 log per 100ms

local harness = require("helpers.test_harness")

-- Helper function to run toggle benchmark
local function run_toggle_benchmark(h, wait_time)
  -- Launch and wait for initial burst of logs
  h:cmd("DapLaunch Debug")
  h:wait(wait_time)

  -- Query output count to verify logs are captured
  local output_count = h:query_count("/sessions/outputs")
  io.write(string.format("\nOutput count: %d\n", output_count))

  -- Open tree at debugger root
  h:open_tree("@debugger")
  h:wait(500)

  -- Find Output node and expand parent if needed
  h.child.fn.search("Output")
  h:wait(100)

  local TOGGLE_COUNT = 10
  local timings = {}

  for i = 1, TOGGLE_COUNT do
    -- Count lines before toggle
    local lines_before = h.child.api.nvim_buf_line_count(0)

    -- Measure toggle time
    local result = h.child.lua(string.format([[
      local lines_before = %d
      local start = vim.loop.hrtime()

      -- Simulate <CR> keypress to toggle
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)

      -- Wait for line count to change (expansion adds lines, collapse removes them)
      local success = vim.wait(10000, function()
        local lines_after = vim.api.nvim_buf_line_count(0)
        return lines_after ~= lines_before
      end, 10)

      local elapsed_ns = vim.loop.hrtime() - start
      local lines_after = vim.api.nvim_buf_line_count(0)
      return {
        elapsed_ms = elapsed_ns / 1000000,
        lines_before = lines_before,
        lines_after = lines_after,
        success = success,
      }
    ]], lines_before))

    local diff = result.lines_after - result.lines_before
    local action = diff > 0 and "Expand" or "Collapse"
    table.insert(timings, { ms = result.elapsed_ms, action = action, diff = diff })

    io.write(string.format("%s %d: %.2f ms (lines: %d -> %d)%s\n",
      action, i, result.elapsed_ms, result.lines_before, result.lines_after,
      result.success and "" or " (timeout)"))

    -- Small wait between toggles to let streaming logs continue
    h:wait(200)
  end

  -- Calculate statistics
  local expand_times = {}
  local collapse_times = {}
  for _, t in ipairs(timings) do
    if t.action == "Expand" then
      table.insert(expand_times, t.ms)
    else
      table.insert(collapse_times, t.ms)
    end
  end

  local function stats(arr, label)
    if #arr == 0 then
      io.write(string.format("%s: no operations\n", label))
      return 0
    end
    local sum, min, max = 0, arr[1], arr[1]
    for _, v in ipairs(arr) do
      sum = sum + v
      if v < min then min = v end
      if v > max then max = v end
    end
    local avg = sum / #arr
    io.write(string.format("%s: avg=%.2f ms, min=%.2f ms, max=%.2f ms (%d ops)\n",
      label, avg, min, max, #arr))
    return avg
  end

  io.write("\n--- Statistics ---\n")
  local expand_avg = stats(expand_times, "Expand")
  stats(collapse_times, "Collapse")

  -- Terminate the streaming process
  h:query_call("/sessions[0]", "terminate")
  h:wait(500)

  return expand_avg
end

local T = harness.integration("output_toggle_perf", function(T, ctx)
  T["measure output toggle time with 1000 logs"] = function()
    local h = ctx.create()
    h:fixture("streaming-logs")
    h:use_plugin("neodap.plugins.tree_buffer")

    local expand_avg = run_toggle_benchmark(h, 3000) -- Wait 3s for 1000 logs

    -- Performance assertion
    MiniTest.expect.equality(expand_avg < 500, true,
      string.format("Average expand time should be < 500ms, got %.2f ms", expand_avg))
  end

  T["measure output toggle time with 10000 logs"] = function()
    local h = ctx.create()
    h:fixture("streaming-logs-10k")
    h:use_plugin("neodap.plugins.tree_buffer")

    local expand_avg = run_toggle_benchmark(h, 3000) -- Wait 3s for initial 10000 logs

    -- Performance assertion - should still be fast due to O(visible) expansion
    MiniTest.expect.equality(expand_avg < 500, true,
      string.format("Average expand time should be < 500ms, got %.2f ms", expand_avg))
  end
end)

return T
