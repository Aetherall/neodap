local sdk = require("neodap.sdk")
local neostate = require("neostate")
local jump_stop = require("neodap.plugins.jump_stop")
local auto_stack = require("neodap.plugins.auto_stack")

local function verified_it(name, fn, timeout_ms)
  timeout_ms = timeout_ms or 30000
  return it(name, function()
    local completed, test_error, test_result = false, nil, nil
    neostate.void(function()
      local ok, result = pcall(fn)
      if not ok then test_error = result else test_result = result end
      completed = true
    end)()
    assert(vim.wait(timeout_ms, function() return completed end, 100),
      string.format("Test '%s' timed out", name))
    if test_error then error(test_error) end
    assert(test_result == true, "Test must return true")
  end)
end

---Get current buffer and cursor position
---@return { bufname: string, line: number, col: number }
local function current_position()
  local bufnr = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  return {
    bufname = vim.api.nvim_buf_get_name(bufnr),
    line = pos[1],
    col = pos[2],
  }
end

describe("JumpStop Plugin", function()
  local script_path = vim.fn.getcwd() .. "/tests/fixtures/stack_test.py"

  describe("basic functionality", function()

    verified_it("jumps to source on breakpoint hit", function()
      local debugger = sdk:create_debugger()
      auto_stack(debugger)
      local cleanup = jump_stop(debugger)

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      debugger:add_breakpoint({ path = script_path }, 7)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(10000, function() return session.state:get() == "stopped" end)

      -- Wait for jump_stop to do its work
      vim.wait(1000, function()
        local pos = current_position()
        return pos.bufname:match("stack_test.py$") and pos.line == 7
      end, 50)

      local pos = current_position()
      assert.is_truthy(pos.bufname:match("stack_test.py$"))
      assert.equals(7, pos.line)

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      cleanup()
      debugger:dispose()
      vim.cmd("bufdo bwipeout!")
      return true
    end)

    verified_it("does not jump when disabled", function()
      local debugger = sdk:create_debugger()
      auto_stack(debugger)
      local cleanup = jump_stop(debugger, { enabled = false })

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      debugger:add_breakpoint({ path = script_path }, 7)

      -- Note initial buffer
      local initial_bufname = vim.api.nvim_buf_get_name(0)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(10000, function() return session.state:get() == "stopped" end)

      -- Give it time to potentially jump (it shouldn't)
      vim.wait(500)

      -- Buffer should NOT have changed to stack_test.py
      local pos = current_position()
      assert.is_falsy(pos.bufname:match("stack_test.py$"))

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      cleanup()
      debugger:dispose()
      vim.cmd("bufdo bwipeout!")
      return true
    end)
  end)

  describe("toggle command", function()

    it("registers DapJumpStop command", function()
      local debugger = sdk:create_debugger()
      local cleanup = jump_stop(debugger)
      assert.is_true(pcall(vim.api.nvim_parse_cmd, "DapJumpStop", {}))
      cleanup()
      debugger:dispose()
    end)

    it("toggles enabled state", function()
      local debugger = sdk:create_debugger()
      local cleanup = jump_stop(debugger)

      local messages = {}
      local original_notify = vim.notify
      vim.notify = function(msg) table.insert(messages, msg) end

      -- Toggle off
      vim.cmd("DapJumpStop")
      assert.equals("DapJumpStop: disabled", messages[#messages])

      -- Toggle on
      vim.cmd("DapJumpStop")
      assert.equals("DapJumpStop: enabled", messages[#messages])

      vim.notify = original_notify
      cleanup()
      debugger:dispose()
    end)

    it("accepts on/off/status arguments", function()
      local debugger = sdk:create_debugger()
      local cleanup = jump_stop(debugger)

      local messages = {}
      local original_notify = vim.notify
      vim.notify = function(msg) table.insert(messages, msg) end

      vim.cmd("DapJumpStop off")
      assert.equals("DapJumpStop: disabled", messages[#messages])

      vim.cmd("DapJumpStop status")
      assert.equals("DapJumpStop: disabled", messages[#messages])

      vim.cmd("DapJumpStop on")
      assert.equals("DapJumpStop: enabled", messages[#messages])

      vim.cmd("DapJumpStop status")
      assert.equals("DapJumpStop: enabled", messages[#messages])

      vim.notify = original_notify
      cleanup()
      debugger:dispose()
    end)

    verified_it("disabling prevents jumps", function()
      local debugger = sdk:create_debugger()
      auto_stack(debugger)
      local cleanup = jump_stop(debugger)

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      debugger:add_breakpoint({ path = script_path }, 7)

      -- Disable before starting
      vim.cmd("DapJumpStop off")

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(10000, function() return session.state:get() == "stopped" end)

      -- Give it time to potentially jump (it shouldn't)
      vim.wait(500)

      -- Buffer should NOT have changed to stack_test.py
      local pos = current_position()
      assert.is_falsy(pos.bufname:match("stack_test.py$"))

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      cleanup()
      debugger:dispose()
      vim.cmd("bufdo bwipeout!")
      return true
    end)
  end)

  describe("scope configuration", function()

    verified_it("scope=all jumps for any session", function()
      local debugger = sdk:create_debugger()
      auto_stack(debugger)
      local cleanup = jump_stop(debugger, { scope = "all" })

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      debugger:add_breakpoint({ path = script_path }, 7)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(10000, function() return session.state:get() == "stopped" end)

      -- Wait for jump_stop to do its work
      vim.wait(1000, function()
        local pos = current_position()
        return pos.bufname:match("stack_test.py$") and pos.line == 7
      end, 50)

      local pos = current_position()
      assert.is_truthy(pos.bufname:match("stack_test.py$"))
      assert.equals(7, pos.line)

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      cleanup()
      debugger:dispose()
      vim.cmd("bufdo bwipeout!")
      return true
    end)

    verified_it("scope=context jumps when session matches context", function()
      local debugger = sdk:create_debugger()
      auto_stack(debugger)
      local cleanup = jump_stop(debugger, { scope = "context" })

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      debugger:add_breakpoint({ path = script_path }, 7)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(10000, function() return session.state:get() == "stopped" end)

      -- auto_stack pins context to top frame, so context session matches
      -- Wait for jump_stop to do its work
      vim.wait(1000, function()
        local pos = current_position()
        return pos.bufname:match("stack_test.py$") and pos.line == 7
      end, 50)

      local pos = current_position()
      assert.is_truthy(pos.bufname:match("stack_test.py$"))
      assert.equals(7, pos.line)

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      cleanup()
      debugger:dispose()
      vim.cmd("bufdo bwipeout!")
      return true
    end)
  end)

  describe("cleanup", function()

    it("removes command on cleanup", function()
      local debugger = sdk:create_debugger()
      local cleanup = jump_stop(debugger)
      cleanup()
      assert.is_false(pcall(vim.api.nvim_parse_cmd, "DapJumpStop", {}))
      debugger:dispose()
    end)

    it("removes command on dispose", function()
      local debugger = sdk:create_debugger()
      jump_stop(debugger)
      debugger:dispose()
      assert.is_false(pcall(vim.api.nvim_parse_cmd, "DapJumpStop", {}))
    end)
  end)
end)
