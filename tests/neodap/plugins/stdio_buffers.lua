-- Tests for stdio_buffers plugin
local harness = require("helpers.test_harness")

-- Skip JavaScript for now - parent/child session structure needs special handling
local original_adapters = harness.enabled_adapters
harness.enabled_adapters = { "python" }

local T = harness.integration("stdio_buffers", function(T, ctx)
  T["DapOutput command opens log file buffer"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.stdio_buffers")

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Run DapOutput command
    h.child.cmd("DapOutput")
    h:wait(100)

    -- Check current buffer name - should be the output.log file
    local bufname = h.child.api.nvim_buf_get_name(0)
    MiniTest.expect.equality(bufname:match("output%.log") ~= nil, true)
  end

  T["output log receives output after stepping"] = function()
    local h = ctx.create()
    h:fixture("logging-steps")
    h:use_plugin("neodap.plugins.stdio_buffers")
    h:use_plugin("neodap.plugins.step_cmd")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Open output buffer first
    h.child.cmd("DapOutput")
    h:wait(100)

    -- Step to first log call
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=5)[0]")

    -- Step over log_step(1) call
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=6)[0]")

    -- Wait for output
    h:wait_url("@session/outputs[0]")
    h:wait(200)

    -- Get output buffer content (should be reloaded with new content)
    local content = h.child.lua_get([[(function()
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name:match("output%.log") then
          -- Force reload to get latest content
          vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("silent! checktime")
          end)
          return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
        end
      end
      return ""
    end)()]])

    -- Should have "Step 1" output
    MiniTest.expect.equality(content:match("Step 1") ~= nil, true)
  end
end)

-- Restore adapters
harness.enabled_adapters = original_adapters

return T
