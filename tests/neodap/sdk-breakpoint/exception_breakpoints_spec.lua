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

describe("Exception Breakpoints", function()
  describe("ExceptionFilter registration", function()
    it("should create ExceptionFilter objects when adapter is registered", function()
      local debugger = sdk:create_debugger()

      -- Register adapter with exception filters
      debugger:register_adapter("test-python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
        exceptionFilters = {
          { filter = "raised", label = "Raised Exceptions", default = false },
          { filter = "uncaught", label = "Uncaught Exceptions", default = true },
        }
      })

      -- Verify filters were created
      local count = 0
      for _ in debugger.exception_filters:iter() do
        count = count + 1
      end
      assert.equals(2, count, "Should have 2 exception filters")

      -- Verify filter lookup by ID
      local uncaught = debugger.exception_filters:get_one("by_id", "test-python:uncaught")
      assert.is_not_nil(uncaught, "Should find uncaught filter")
      assert.equals("uncaught", uncaught.filter_id)
      assert.equals("Uncaught Exceptions", uncaught.label)
      assert.is_true(uncaught.enabled:get(), "uncaught should be enabled by default")

      local raised = debugger.exception_filters:get_one("by_id", "test-python:raised")
      assert.is_not_nil(raised, "Should find raised filter")
      assert.equals("raised", raised.filter_id)
      assert.equals("Raised Exceptions", raised.label)
      assert.is_false(raised.enabled:get(), "raised should be disabled by default")

      -- Verify lookup by adapter
      local filters = {}
      for filter in debugger.exception_filters:where("by_adapter", "test-python"):iter() do
        table.insert(filters, filter)
      end
      assert.equals(2, #filters, "Should have 2 filters for test-python adapter")

      debugger:dispose()
      return true
    end)

    it("should toggle exception filter enabled state", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("test-python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
        exceptionFilters = {
          { filter = "raised", label = "Raised Exceptions", default = false },
          { filter = "uncaught", label = "Uncaught Exceptions", default = true },
        }
      })

      -- Toggle via Signal
      local filter = debugger.exception_filters:get_one("by_id", "test-python:raised")
      assert.is_false(filter.enabled:get())

      filter.enabled:set(true)
      assert.is_true(filter.enabled:get())

      -- Toggle via convenience method
      debugger:set_exception_filter("test-python", "raised", false)
      assert.is_false(filter.enabled:get())

      -- Get enabled filters
      local enabled = debugger:enabled_exception_filters("test-python")
      assert.equals(1, #enabled)
      assert.equals("uncaught", enabled[1])

      debugger:dispose()
      return true
    end)
  end)

  describe("ExceptionFilterBinding", function()
    verified_it("should create bindings when session starts", function()
      local debugger = sdk:create_debugger()

      -- Register adapter with exception filters
      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
        exceptionFilters = {
          { filter = "raised", label = "Raised Exceptions", default = false },
          { filter = "uncaught", label = "Uncaught Exceptions", default = true },
        }
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/hello.py", ":p")

      -- Start session
      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Verify bindings were created for this session
      local binding_count = 0
      for binding in session:exception_filter_bindings():iter() do
        binding_count = binding_count + 1
        print(string.format("  Binding: filter=%s, verified=%s",
          binding.filter.filter_id,
          tostring(binding.verified:get())
        ))
      end
      assert.equals(2, binding_count, "Should have 2 exception filter bindings")

      -- Verify binding is in global collection
      local global_count = 0
      for _ in debugger.exception_filter_bindings:iter() do
        global_count = global_count + 1
      end
      assert.equals(2, global_count, "Global collection should have 2 bindings")

      -- Wait for session to complete
      vim.wait(5000, function()
        return session.state:get() == "terminated"
      end)

      session:disconnect()
      debugger:dispose()

      return true
    end)
  end)

  describe("Exception stops", function()
    verified_it("should stop on uncaught exceptions when filter enabled", function()
      local debugger = sdk:create_debugger()

      -- Register Python adapter with exception filters
      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
        exceptionFilters = {
          { filter = "raised", label = "Raised Exceptions", default = false },
          { filter = "uncaught", label = "Uncaught Exceptions", default = true },
        }
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/exception_test.py", ":p")

      print("\n=== EXCEPTION STOP TEST ===")

      -- Start session
      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Track exception stops
      local exception_stopped = false
      local stop_reason = nil

      -- Wait for stopped state
      vim.wait(10000, function()
        if session.state:get() == "stopped" then
          -- Check if any thread stopped on exception
          for thread in session:threads():iter() do
            if thread:stoppedOnException() then
              exception_stopped = true
              stop_reason = thread.stopReason:get()
              print(string.format("  Thread %d stopped on exception", thread.id))
            end
          end
        end
        return exception_stopped or session.state:get() == "terminated"
      end)

      print(string.format("  Exception stopped: %s", tostring(exception_stopped)))
      print(string.format("  Stop reason: %s", tostring(stop_reason)))

      assert.is_true(exception_stopped, "Should stop on uncaught exception")
      assert.equals("exception", stop_reason)

      session:disconnect()
      debugger:dispose()

      return true
    end)

    verified_it("should retrieve exception info when stopped on exception", function()
      local debugger = sdk:create_debugger()

      -- Register Python adapter with exception filters
      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
        exceptionFilters = {
          { filter = "raised", label = "Raised Exceptions", default = false },
          { filter = "uncaught", label = "Uncaught Exceptions", default = true },
        }
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/exception_test.py", ":p")

      print("\n=== EXCEPTION INFO TEST ===")

      -- Start session
      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for stopped on exception
      local thread_with_exception = nil

      vim.wait(10000, function()
        if session.state:get() == "stopped" then
          for thread in session:threads():iter() do
            if thread:stoppedOnException() then
              thread_with_exception = thread
              return true
            end
          end
        end
        return session.state:get() == "terminated"
      end)

      assert.is_not_nil(thread_with_exception, "Should have thread stopped on exception")

      -- Fetch exception info
      local info, err = thread_with_exception:exceptionInfo()

      if err then
        print(string.format("  Error getting exception info: %s", err))
      else
        print(string.format("  Exception ID: %s", info.exceptionId or "nil"))
        print(string.format("  Description: %s", info.description or "nil"))
        print(string.format("  Break mode: %s", info.breakMode or "nil"))
        if info.details then
          print(string.format("  Type name: %s", info.details.typeName or "nil"))
          print(string.format("  Message: %s", info.details.message or "nil"))
        end
      end

      assert.is_nil(err, "Should not have error")
      assert.is_not_nil(info, "Should have exception info")
      assert.is_not_nil(info.exceptionId, "Should have exception ID")

      session:disconnect()
      debugger:dispose()

      return true
    end)
  end)

  describe("Filter toggling mid-session", function()
    verified_it("should sync exception filters when toggled during session", function()
      local debugger = sdk:create_debugger()

      -- Register Python adapter with all filters disabled initially
      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
        exceptionFilters = {
          { filter = "raised", label = "Raised Exceptions", default = false },
          { filter = "uncaught", label = "Uncaught Exceptions", default = false },  -- Start disabled
        }
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/exception_test.py", ":p")

      print("\n=== FILTER TOGGLE TEST ===")

      -- Set a breakpoint to stop before the exception
      local bp = debugger:add_breakpoint({ path = script_path }, 10)

      -- Start session with uncaught disabled
      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for breakpoint hit
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      print("  Stopped at breakpoint")

      -- Verify no exception filters are enabled
      local enabled_before = debugger:enabled_exception_filters("python")
      print(string.format("  Enabled filters before toggle: %d", #enabled_before))
      assert.equals(0, #enabled_before)

      -- Enable uncaught exceptions mid-session
      print("  Toggling uncaught exceptions filter ON")
      debugger:set_exception_filter("python", "uncaught", true)

      -- Verify filter is now enabled
      local enabled_after = debugger:enabled_exception_filters("python")
      print(string.format("  Enabled filters after toggle: %d", #enabled_after))
      assert.equals(1, #enabled_after)
      assert.equals("uncaught", enabled_after[1])

      -- Continue - should now stop on exception
      session:continue()

      -- Wait for exception stop
      local stopped_on_exception = false
      vim.wait(5000, function()
        if session.state:get() == "stopped" then
          for thread in session:threads():iter() do
            if thread:stoppedOnException() then
              stopped_on_exception = true
              return true
            end
          end
        end
        return session.state:get() == "terminated"
      end)

      print(string.format("  Stopped on exception after toggle: %s", tostring(stopped_on_exception)))
      assert.is_true(stopped_on_exception, "Should stop on exception after enabling filter")

      session:disconnect()
      debugger:dispose()

      return true
    end)

    verified_it("should NOT stop on exceptions after disabling filter", function()
      local debugger = sdk:create_debugger()

      -- Register Python adapter with "raised" filter enabled
      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
        exceptionFilters = {
          { filter = "raised", label = "Raised Exceptions", default = true },
          { filter = "uncaught", label = "Uncaught Exceptions", default = false },
        }
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/multi_exception_test.py", ":p")

      print("\n=== FILTER DISABLE TEST ===")

      -- Set a breakpoint BEFORE the exception so we can toggle filter before hitting exception
      local bp = debugger:add_breakpoint({ path = script_path }, 16)  -- x = 1 line

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Verify raised filter is enabled
      local enabled_before = debugger:enabled_exception_filters("python")
      print(string.format("  Enabled filters at start: %s", table.concat(enabled_before, ", ")))
      assert.equals(1, #enabled_before)

      -- Wait for breakpoint hit (not exception)
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      print("  Stopped at breakpoint")

      -- Now DISABLE the raised filter while stopped at breakpoint (not exception)
      print("  Disabling raised exceptions filter")
      debugger:set_exception_filter("python", "raised", false)

      -- Verify filter is disabled
      local enabled_after = debugger:enabled_exception_filters("python")
      print(string.format("  Enabled filters after disable: %d", #enabled_after))
      assert.equals(0, #enabled_after)

      -- Manually sync and check response
      local err = session:_sync_exception_filters_to_dap()
      print(string.format("  Sync error: %s", tostring(err)))
      assert.is_nil(err)

      -- Continue - should NOT stop on any exceptions now
      session:continue()

      -- Wait for termination (program should complete without stopping on exceptions)
      local stopped_on_exception = false
      local terminated = false

      vim.wait(10000, function()
        if session.state:get() == "stopped" then
          for thread in session:threads():iter() do
            if thread:stoppedOnException() then
              stopped_on_exception = true
              print(string.format("  Unexpectedly stopped on exception!"))
              return true
            end
          end
        end
        if session.state:get() == "terminated" then
          terminated = true
          return true
        end
        return false
      end)

      print(string.format("  Stopped on exception: %s", tostring(stopped_on_exception)))
      print(string.format("  Program terminated: %s", tostring(terminated)))

      assert.is_false(stopped_on_exception, "Should NOT stop on exception after disabling filter")
      assert.is_true(terminated, "Program should complete without exception stops")

      session:disconnect()
      debugger:dispose()

      return true
    end)
  end)

  describe("Session terminate", function()
    verified_it("should check terminate support and call terminate", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/hello.py", ":p")

      print("\n=== TERMINATE TEST ===")

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

      local supports = session:supportsTerminate()
      print(string.format("  supportsTerminate: %s", tostring(supports)))

      if supports then
        local err = session:terminate()
        print(string.format("  terminate() error: %s", tostring(err)))

        -- Wait for termination
        vim.wait(5000, function()
          return session.state:get() == "terminated"
        end)

        print(string.format("  Final state: %s", session.state:get()))
      else
        print("  Adapter does not support terminate, using disconnect")
        session:disconnect()

        vim.wait(5000, function()
          return session.state:get() == "terminated"
        end)
      end

      debugger:dispose()

      return true
    end)
  end)
end)
