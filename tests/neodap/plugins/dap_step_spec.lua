local sdk = require("neodap.sdk")
local neostate = require("neostate")
local dap_step = require("neodap.plugins.dap_step")
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

describe("DapStep Plugin", function()
  local script_path = vim.fn.getcwd() .. "/tests/fixtures/stepping_test.py"

  local function wait_for_step(session, thread)
    vim.wait(500, function() return false end, 10)  -- Let void start
    vim.wait(5000, function() return session.state:get() == "stopped" end, 10)
    vim.wait(2000, function() return thread._current_stack:get() ~= nil end, 50)
    return thread._current_stack:get():top().line
  end

  describe("with Python debugger", function()

    verified_it("step over moves to next line", function()
      local debugger = sdk:create_debugger()
      auto_stack(debugger)
      dap_step(debugger)

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      debugger:add_breakpoint({ path = script_path }, 6)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(10000, function() return session.state:get() == "stopped" end)

      local thread = session:threads():iter()()
      vim.wait(1000, function() return thread._current_stack:get() ~= nil end, 50)
      debugger:context():pin(thread._current_stack:get():top().uri)

      assert.equals(6, thread._current_stack:get():top().line)

      vim.cmd("DapStep over")
      assert.equals(7, wait_for_step(session, thread))

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()
      return true
    end)

    verified_it("step into enters function", function()
      local debugger = sdk:create_debugger()
      auto_stack(debugger)
      dap_step(debugger)

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      debugger:add_breakpoint({ path = script_path }, 12)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(10000, function() return session.state:get() == "stopped" end)

      local thread = session:threads():iter()()
      vim.wait(1000, function() return thread._current_stack:get() ~= nil end, 50)
      debugger:context():pin(thread._current_stack:get():top().uri)

      assert.equals(12, thread._current_stack:get():top().line)

      vim.cmd("DapStep into")
      assert.equals(6, wait_for_step(session, thread))

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()
      return true
    end)

    verified_it("step out returns to caller", function()
      local debugger = sdk:create_debugger()
      auto_stack(debugger)
      dap_step(debugger)

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      debugger:add_breakpoint({ path = script_path }, 6)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(10000, function() return session.state:get() == "stopped" end)

      local thread = session:threads():iter()()
      vim.wait(1000, function() return thread._current_stack:get() ~= nil end, 50)
      debugger:context():pin(thread._current_stack:get():top().uri)

      assert.equals(6, thread._current_stack:get():top().line)

      vim.cmd("DapStep out")
      local line = wait_for_step(session, thread)
      assert.is_true(line >= 12)

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()
      return true
    end)

    verified_it("defaults to step over", function()
      local debugger = sdk:create_debugger()
      auto_stack(debugger)
      dap_step(debugger)

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      debugger:add_breakpoint({ path = script_path }, 6)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(10000, function() return session.state:get() == "stopped" end)

      local thread = session:threads():iter()()
      vim.wait(1000, function() return thread._current_stack:get() ~= nil end, 50)
      debugger:context():pin(thread._current_stack:get():top().uri)

      vim.cmd("DapStep")
      assert.equals(7, wait_for_step(session, thread))

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()
      return true
    end)

    verified_it("accepts args in any order", function()
      local debugger = sdk:create_debugger()
      auto_stack(debugger)
      dap_step(debugger)

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      debugger:add_breakpoint({ path = script_path }, 6)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(10000, function() return session.state:get() == "stopped" end)

      local thread = session:threads():iter()()
      vim.wait(1000, function() return thread._current_stack:get() ~= nil end, 50)
      debugger:context():pin(thread._current_stack:get():top().uri)

      vim.cmd("DapStep line over")
      assert.equals(7, wait_for_step(session, thread))

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()
      return true
    end)

    verified_it("step over with statement granularity", function()
      local debugger = sdk:create_debugger()
      auto_stack(debugger)
      dap_step(debugger)

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      debugger:add_breakpoint({ path = script_path }, 6)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(10000, function() return session.state:get() == "stopped" end)

      local thread = session:threads():iter()()
      vim.wait(1000, function() return thread._current_stack:get() ~= nil end, 50)
      debugger:context():pin(thread._current_stack:get():top().uri)

      assert.equals(6, thread._current_stack:get():top().line)

      vim.cmd("DapStep over statement")
      assert.equals(7, wait_for_step(session, thread))

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()
      return true
    end)

    verified_it("step into with instruction granularity", function()
      local debugger = sdk:create_debugger()
      auto_stack(debugger)
      dap_step(debugger)

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      debugger:add_breakpoint({ path = script_path }, 12)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(10000, function() return session.state:get() == "stopped" end)

      local thread = session:threads():iter()()
      vim.wait(1000, function() return thread._current_stack:get() ~= nil end, 50)
      debugger:context():pin(thread._current_stack:get():top().uri)

      assert.equals(12, thread._current_stack:get():top().line)

      vim.cmd("DapStep instruction into")
      assert.equals(6, wait_for_step(session, thread))

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()
      return true
    end)
  end)

  describe("config", function()
    it("registers command", function()
      local debugger = sdk:create_debugger()
      local cleanup = dap_step(debugger)
      assert.is_true(pcall(vim.api.nvim_parse_cmd, "DapStep", {}))
      cleanup()
      debugger:dispose()
    end)

    it("accepts multi_thread = pick", function()
      local debugger = sdk:create_debugger()
      local cleanup = dap_step(debugger, { multi_thread = "pick" })
      assert.is_true(pcall(vim.api.nvim_parse_cmd, "DapStep", {}))
      cleanup()
      debugger:dispose()
    end)
  end)

  describe("cleanup", function()
    it("removes command on cleanup", function()
      local debugger = sdk:create_debugger()
      local cleanup = dap_step(debugger)
      cleanup()
      assert.is_false(pcall(vim.api.nvim_parse_cmd, "DapStep", {}))
      debugger:dispose()
    end)

    it("removes command on dispose", function()
      local debugger = sdk:create_debugger()
      dap_step(debugger)
      debugger:dispose()
      assert.is_false(pcall(vim.api.nvim_parse_cmd, "DapStep", {}))
    end)
  end)
end)
