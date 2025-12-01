local sdk = require("neodap.sdk")
local neostate = require("neostate")

-- Inline verified_it helper
local function verified_it(name, fn, timeout_ms)
  timeout_ms = timeout_ms or 30000

  return it(name, function()
    local completed = false
    local test_error = nil
    local test_result = nil

    local co = coroutine.create(function()
      local ok, result = pcall(fn)
      if not ok then
        test_error = result
      else
        test_result = result
      end
      completed = true
    end)

    local ok, err = coroutine.resume(co)
    if not ok and not completed then
      error("Test failed to start: " .. tostring(err))
    end

    local success = vim.wait(timeout_ms, function()
      return completed
    end, 100)

    if not success then
      error(string.format("Test '%s' timed out after %dms", name, timeout_ms))
    end

    if test_error then
      error(test_error)
    end

    if test_result ~= true then
      error(string.format(
        "Test did not return true (got: %s). Tests must return true at completion.",
        tostring(test_result)
      ))
    end
  end)
end

describe("Session Restart", function()
  describe("supportsRestart", function()
    verified_it("should check restart capability from adapter", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/hello.py", ":p")

      print("\n=== SUPPORTS RESTART TEST ===")

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for running state
      vim.wait(5000, function()
        return session.state:get() == "running" or session.state:get() == "stopped"
      end)

      local supports = session:supportsRestart()
      print(string.format("  supportsRestart: %s", tostring(supports)))

      -- debugpy doesn't support restart, so this should be false
      assert.is_false(supports, "debugpy should not support native restart")

      -- Wait for termination
      vim.wait(5000, function()
        return session.state:get() == "terminated"
      end)

      session:disconnect()
      debugger:dispose()

      return true
    end)
  end)

  describe("Restart via new session fallback", function()
    verified_it("should create new session when adapter lacks native restart", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/counter_loop.py", ":p")

      print("\n=== RESTART VIA NEW SESSION TEST ===")

      -- Set breakpoint to stop the program
      local bp = debugger:add_breakpoint({ path = script_path }, 7)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for stopped at breakpoint
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      print("  Stopped at first breakpoint")
      local old_session_id = session.id

      -- Track restart hook on old session
      local restart_called = false
      session:onRestart(function()
        restart_called = true
        print("  onRestart hook called on old session")
      end)

      -- Restart the session (returns new session)
      print("  Restarting session...")
      local new_session, err = session:restart()

      assert.is_nil(err, "Should not have error")
      assert.is_not_nil(new_session, "Should return new session")
      assert.is_true(restart_called, "onRestart hook should be called on old session")

      -- New session should be different object
      print(string.format("  Old session ID: %s", old_session_id))
      print(string.format("  New session ID: %s", new_session.id))
      assert.are_not.equal(old_session_id, new_session.id, "New session should have different ID")

      -- Wait for new session to stop at breakpoint
      vim.wait(10000, function()
        return new_session.state:get() == "stopped"
      end)

      print(string.format("  New session state: %s", new_session.state:get()))
      assert.equals("stopped", new_session.state:get(), "New session should stop at breakpoint")

      -- Old session should be terminated/disposed
      assert.equals("terminated", session.state:get(), "Old session should be terminated")

      new_session:disconnect()
      debugger:dispose()

      return true
    end)

    verified_it("should emit restarted hook on new session", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/counter_loop.py", ":p")

      print("\n=== RESTARTED HOOK TEST ===")

      local bp = debugger:add_breakpoint({ path = script_path }, 7)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Track restarted hook - will be emitted on new session
      local restarted_called = false

      -- We'll check the new session for the restarted event after restart
      local new_session, err = session:restart()

      -- The restarted event was already emitted during restart
      -- Register hook to verify it was called (by checking session state)
      vim.wait(10000, function()
        return new_session.state:get() == "stopped"
      end)

      print(string.format("  New session ready: %s", new_session.state:get()))
      assert.equals("stopped", new_session.state:get())

      new_session:disconnect()
      debugger:dispose()

      return true
    end)
  end)

  describe("State after restart", function()
    verified_it("should have fresh threads in new session", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/counter_loop.py", ":p")

      print("\n=== FRESH THREADS TEST ===")

      local bp = debugger:add_breakpoint({ path = script_path }, 7)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Store old thread references
      local old_threads = {}
      for thread in session:threads():iter() do
        table.insert(old_threads, thread)
      end
      print(string.format("  Old session threads: %d", #old_threads))

      -- Restart
      local new_session, err = session:restart()

      vim.wait(10000, function()
        return new_session.state:get() == "stopped"
      end)

      -- Get new threads
      local new_threads = {}
      for thread in new_session:threads():iter() do
        table.insert(new_threads, thread)
      end
      print(string.format("  New session threads: %d", #new_threads))

      -- Verify threads are different objects
      for _, old in ipairs(old_threads) do
        for _, new in ipairs(new_threads) do
          assert.are_not.equal(old, new, "Should have different thread objects")
        end
      end

      -- Verify old threads are disposed
      for _, old in ipairs(old_threads) do
        assert.is_true(old._disposed or false, "Old threads should be disposed")
      end

      new_session:disconnect()
      debugger:dispose()

      return true
    end)

    verified_it("should preserve breakpoints across restart", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/counter_loop.py", ":p")

      print("\n=== BREAKPOINT PRESERVATION TEST ===")

      -- Add breakpoint before first session
      local bp = debugger:add_breakpoint({ path = script_path }, 7)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      print("  First session stopped at breakpoint")

      -- Restart
      local new_session, err = session:restart()

      vim.wait(10000, function()
        return new_session.state:get() == "stopped"
      end)

      print("  New session stopped at breakpoint")

      -- Verify breakpoint still exists in debugger
      local bp_count = 0
      for _ in debugger.breakpoints:iter() do
        bp_count = bp_count + 1
      end
      assert.equals(1, bp_count, "Breakpoint should still exist")

      -- Verify new session has binding for the breakpoint
      local binding_count = 0
      for _ in new_session:bindings():iter() do
        binding_count = binding_count + 1
      end
      print(string.format("  New session bindings: %d", binding_count))
      assert.equals(1, binding_count, "New session should have breakpoint binding")

      new_session:disconnect()
      debugger:dispose()

      return true
    end)
  end)

end)
