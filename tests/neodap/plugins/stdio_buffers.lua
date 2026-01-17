-- Tests for stdio_buffers plugin
local harness = require("helpers.test_harness")

-- Skip JavaScript for now - parent/child session structure needs special handling
local original_adapters = harness.enabled_adapters
harness.enabled_adapters = { "python" }

local T = harness.integration("stdio_buffers", function(T, ctx)
  T["creates stdout buffer for session"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.stdio_buffers")

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")

    -- Check that stdout buffer was created
    local has_stdout_buf = h.child.lua_get([[(function()
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name:match("dap://stdout/") then
          return true
        end
      end
      return false
    end)()]])

    MiniTest.expect.equality(has_stdout_buf, true)
  end

  T["stdout buffer receives output after stepping"] = function()
    local h = ctx.create()
    h:fixture("logging-steps")
    h:use_plugin("neodap.plugins.stdio_buffers")
    h:use_plugin("neodap.plugins.step_cmd")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Step to first log call
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=5)[0]")

    -- Step over log_step(1) call
    h:cmd("DapStep over")
    h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=6)[0]")

    -- Wait for output
    h:wait_url("@session/outputs[0]")
    h:wait(200)

    -- Get stdout buffer content
    local content = h.child.lua_get([[(function()
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name:match("dap://stdout/") then
          return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
        end
      end
      return ""
    end)()]])

    -- Should have "Step 1" output
    MiniTest.expect.equality(content:match("Step 1") ~= nil, true)
  end

  T["DapStdout command opens buffer"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:use_plugin("neodap.plugins.stdio_buffers")

    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Run DapStdout command
    h.child.cmd("DapStdout")
    h:wait(100)

    -- Check current buffer name
    local bufname = h.child.api.nvim_buf_get_name(0)
    MiniTest.expect.equality(bufname:match("dap://stdout/") ~= nil, true)
  end

  T["buffer marked as terminated when session ends"] = function()
    local h = ctx.create()
    h:fixture("logging-steps")
    h:use_plugin("neodap.plugins.stdio_buffers")

    h:edit_main()
    h:cmd("DapLaunch Debug stop")
    h:wait_url("/sessions/threads/stacks[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")

    -- Continue to completion
    h:cmd("DapContinue")
    h:wait_terminated(5000)
    h:wait(300)  -- Wait for termination handling

    -- Find stdout buffer and check name contains [terminated]
    local has_terminated = h.child.lua_get([[(function()
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name:match("dap://stdout/.*%[terminated%]") then
          return true
        end
      end
      return false
    end)()]])

    MiniTest.expect.equality(has_terminated, true)
  end
end)

-- Restore adapters
harness.enabled_adapters = original_adapters

return T
