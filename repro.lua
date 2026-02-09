-- Repro script for tree_buffer profiling with sampling
-- Source this from nvim MCP: :source repro.lua
-- Results written to /tmp/profiler_output.txt

-- 1. cd to monorepo
vim.cmd("cd ~/workspace/kraaft/monorepo")

-- 2. Open workspace file (needed for launch.json discovery)
vim.cmd("edit monorepo.code-workspace")

-- 3. Run overseer task "fullstack local" (compound with 6 configs)
vim.defer_fn(function()
  vim.cmd([[OverseerRun Debug:\ fullstack\ local]])

  -- 4. Wait for sessions to start, then open tree with profiling
  vim.defer_fn(function()
    local profiler = require("neograph.profiler")
    local output_file = "/tmp/profiler_output.txt"

    -- Start profiling in SAMPLING mode (much lower overhead)
    profiler.start_sampling(1000)  -- Sample every 1000 instructions

    local f = io.open(output_file, "w")
    f:write("=== PROFILING TREE BUFFER OPEN (SAMPLING) ===\n")
    f:write("Starting profiler at " .. os.date() .. "\n\n")
    f:close()

    vim.cmd("e dap://tree/@debugger")

    -- Stop profiling after tree renders
    vim.defer_fn(function()
      profiler.stop()

      -- Write flamegraph report to file (for sampling mode)
      local f = io.open(output_file, "a")
      local old_print = print
      print = function(...)
        local args = {...}
        for i, v in ipairs(args) do args[i] = tostring(v) end
        f:write(table.concat(args, "\t") .. "\n")
      end

      f:write("\n=== SAMPLING FLAMEGRAPH ===\n")
      profiler.flamegraph()
      f:write("========================\n")

      print = old_print
      f:close()

      vim.notify("Profiler output written to " .. output_file, vim.log.levels.INFO)
    end, 5000)  -- Wait 5s for render to complete
  end, 5000)
end, 500)
