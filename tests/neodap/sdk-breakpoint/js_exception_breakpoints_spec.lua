local sdk = require("neodap.sdk")
local neostate = require("neostate")

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

-- Helper to wait for js-debug child session (js-debug uses bootstrap/child pattern)
local function wait_for_child_session(bootstrap_session)
  local child = nil
  vim.wait(10000, function()
    for s in bootstrap_session:children():iter() do
      child = s
      return true
    end
    return false
  end, 50)
  return child
end

describe("JavaScript Exception Breakpoints", function()
  describe("Uncaught exceptions", function()
    verified_it("should stop on uncaught exceptions when filter enabled", function()
      local debugger = sdk:create_debugger()

      -- Register JavaScript adapter with exception filters
      debugger:register_adapter("pwa-node", {
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
          local h, p = chunk:match("Debug server listening at (.*):(%d+)")
          return tonumber(p), h
        end,
        exceptionFilters = {
          { filter = "all", label = "All Exceptions", default = false },
          { filter = "uncaught", label = "Uncaught Exceptions", default = true },
        }
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/exception_test.js", ":p")

      print("\n=== JS UNCAUGHT EXCEPTION TEST ===")

      -- Start returns bootstrap session, child session does actual debugging
      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for child session (js-debug pattern)
      local session = wait_for_child_session(bootstrap)
      if not session then
        error("No child session created - js-debug bootstrap may have failed")
      end
      print("  Got child session")

      -- Track exception stops
      local exception_stopped = false
      local stop_reason = nil

      -- Wait for stopped state on child session
      vim.wait(15000, function()
        if session.state:get() == "stopped" then
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

      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("should retrieve exception info for uncaught exception", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("pwa-node", {
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
          local h, p = chunk:match("Debug server listening at (.*):(%d+)")
          return tonumber(p), h
        end,
        exceptionFilters = {
          { filter = "uncaught", label = "Uncaught Exceptions", default = true },
        }
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/exception_test.js", ":p")

      print("\n=== JS EXCEPTION INFO TEST ===")

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for child session
      local session = wait_for_child_session(bootstrap)
      if not session then
        error("No child session created")
      end

      -- Wait for stopped on exception
      local thread_with_exception = nil

      vim.wait(15000, function()
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

      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)

  describe("Caught exceptions", function()
    verified_it("should stop on caught exceptions when 'all' filter enabled", function()
      local debugger = sdk:create_debugger()

      -- Register with 'all' exceptions filter enabled
      debugger:register_adapter("pwa-node", {
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
          local h, p = chunk:match("Debug server listening at (.*):(%d+)")
          return tonumber(p), h
        end,
        exceptionFilters = {
          { filter = "all", label = "All Exceptions", default = true },
          { filter = "uncaught", label = "Uncaught Exceptions", default = false },
        }
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/caught_exception_test.js", ":p")

      print("\n=== JS CAUGHT EXCEPTION TEST ===")

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for child session
      local session = wait_for_child_session(bootstrap)
      if not session then
        error("No child session created")
      end

      -- Track exception stops
      local exception_stopped = false
      local stop_reason = nil

      -- Wait for stopped on exception (should be the caught one)
      vim.wait(15000, function()
        if session.state:get() == "stopped" then
          for thread in session:threads():iter() do
            if thread:stoppedOnException() then
              exception_stopped = true
              stop_reason = thread.stopReason:get()
              print(string.format("  Thread %d stopped on exception", thread.id))
              return true
            end
          end
        end
        return session.state:get() == "terminated"
      end)

      print(string.format("  Exception stopped: %s", tostring(exception_stopped)))
      print(string.format("  Stop reason: %s", tostring(stop_reason)))

      assert.is_true(exception_stopped, "Should stop on caught exception when 'all' filter enabled")
      assert.equals("exception", stop_reason)

      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("should NOT stop on caught exceptions with only 'uncaught' filter", function()
      local debugger = sdk:create_debugger()

      -- Register with only uncaught filter (all disabled)
      debugger:register_adapter("pwa-node", {
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
          local h, p = chunk:match("Debug server listening at (.*):(%d+)")
          return tonumber(p), h
        end,
        exceptionFilters = {
          { filter = "all", label = "All Exceptions", default = false },
          { filter = "uncaught", label = "Uncaught Exceptions", default = true },
        }
      })

      -- Use script with ONLY caught exceptions
      local script_path = vim.fn.fnamemodify("tests/fixtures/caught_exception_test.js", ":p")

      print("\n=== JS SKIP CAUGHT EXCEPTION TEST ===")

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for child session
      local session = wait_for_child_session(bootstrap)
      if not session then
        error("No child session created")
      end

      -- Track states
      local exception_stopped = false

      -- Wait - should NOT stop on caught exceptions, program should complete
      -- Check both child session AND bootstrap for termination (js-debug exits child first)
      vim.wait(15000, function()
        if session.state:get() == "stopped" then
          for thread in session:threads():iter() do
            if thread:stoppedOnException() then
              exception_stopped = true
              print("  Unexpectedly stopped on exception!")
              return true
            end
          end
        end
        -- Child session terminates or bootstrap terminates = program done
        if session.state:get() == "terminated" or bootstrap.state:get() == "terminated" then
          return true
        end
        return false
      end)

      local terminated = session.state:get() == "terminated" or bootstrap.state:get() == "terminated"

      print(string.format("  Exception stopped: %s", tostring(exception_stopped)))
      print(string.format("  Program terminated: %s (child=%s, bootstrap=%s)",
        tostring(terminated), session.state:get(), bootstrap.state:get()))

      assert.is_false(exception_stopped, "Should NOT stop on caught exception with only 'uncaught' filter")
      assert.is_true(terminated, "Program should complete without exception stops")

      bootstrap:disconnect(true)
      debugger:dispose()

      return true
    end)
  end)

  describe("Filter toggling mid-session", function()
    verified_it("should stop on exceptions after enabling filter mid-session", function()
      local debugger = sdk:create_debugger()

      -- Start with all filters disabled
      debugger:register_adapter("pwa-node", {
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
          local h, p = chunk:match("Debug server listening at (.*):(%d+)")
          return tonumber(p), h
        end,
        exceptionFilters = {
          { filter = "all", label = "All Exceptions", default = false },
          { filter = "uncaught", label = "Uncaught Exceptions", default = false },
        }
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/caught_exception_test.js", ":p")

      print("\n=== JS FILTER TOGGLE TEST ===")

      -- Set breakpoint before exception
      debugger:add_breakpoint({ path = script_path }, 14)

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for child session
      local session = wait_for_child_session(bootstrap)
      if not session then
        error("No child session created")
      end

      -- Wait for breakpoint
      vim.wait(15000, function()
        return session.state:get() == "stopped"
      end)

      print("  Stopped at breakpoint")

      -- Verify no filters enabled
      local enabled_before = debugger:enabled_exception_filters("pwa-node")
      print(string.format("  Enabled filters before: %d", #enabled_before))
      assert.equals(0, #enabled_before)

      -- Enable 'all' exceptions filter mid-session
      print("  Enabling 'all' exceptions filter")
      debugger:set_exception_filter("pwa-node", "all", true)

      local enabled_after = debugger:enabled_exception_filters("pwa-node")
      print(string.format("  Enabled filters after: %d", #enabled_after))
      assert.equals(1, #enabled_after)

      -- Wait for sync to complete
      vim.wait(500)

      -- Continue - should now stop on caught exception
      session:continue()

      local exception_stopped = false
      vim.wait(10000, function()
        if session.state:get() == "stopped" then
          for thread in session:threads():iter() do
            if thread:stoppedOnException() then
              exception_stopped = true
              return true
            end
          end
        end
        -- Also check bootstrap termination as fallback exit condition
        if bootstrap.state:get() == "terminated" then
          return true
        end
        return false
      end)

      print(string.format("  Stopped on exception after toggle: %s", tostring(exception_stopped)))
      assert.is_true(exception_stopped, "Should stop on exception after enabling filter")

      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("should NOT stop on exceptions after disabling filter mid-session", function()
      local debugger = sdk:create_debugger()

      -- Start with 'all' filter enabled
      debugger:register_adapter("pwa-node", {
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
          local h, p = chunk:match("Debug server listening at (.*):(%d+)")
          return tonumber(p), h
        end,
        exceptionFilters = {
          { filter = "all", label = "All Exceptions", default = true },
          { filter = "uncaught", label = "Uncaught Exceptions", default = false },
        }
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/caught_exception_test.js", ":p")

      print("\n=== JS FILTER DISABLE TEST ===")

      -- Set breakpoint before exception
      debugger:add_breakpoint({ path = script_path }, 14)

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for child session
      local session = wait_for_child_session(bootstrap)
      if not session then
        error("No child session created")
      end

      -- Wait for breakpoint
      vim.wait(15000, function()
        return session.state:get() == "stopped"
      end)

      print("  Stopped at breakpoint")

      -- Verify 'all' filter is enabled
      local enabled_before = debugger:enabled_exception_filters("pwa-node")
      print(string.format("  Enabled filters before: %s", table.concat(enabled_before, ", ")))
      assert.equals(1, #enabled_before)
      assert.equals("all", enabled_before[1])

      -- Disable 'all' exceptions filter mid-session
      print("  Disabling 'all' exceptions filter")
      debugger:set_exception_filter("pwa-node", "all", false)

      local enabled_after = debugger:enabled_exception_filters("pwa-node")
      print(string.format("  Enabled filters after: %d", #enabled_after))
      assert.equals(0, #enabled_after)

      -- Wait for sync to complete
      vim.wait(500)

      -- Continue - should NOT stop on caught exception now
      session:continue()

      local exception_stopped = false
      vim.wait(10000, function()
        if session.state:get() == "stopped" then
          for thread in session:threads():iter() do
            if thread:stoppedOnException() then
              exception_stopped = true
              print("  Unexpectedly stopped on exception!")
              return true
            end
          end
        end
        -- Program should complete without exception stops
        if session.state:get() == "terminated" or bootstrap.state:get() == "terminated" then
          return true
        end
        return false
      end)

      local terminated = session.state:get() == "terminated" or bootstrap.state:get() == "terminated"

      print(string.format("  Exception stopped: %s", tostring(exception_stopped)))
      print(string.format("  Program terminated: %s", tostring(terminated)))

      assert.is_false(exception_stopped, "Should NOT stop on exception after disabling filter")
      assert.is_true(terminated, "Program should complete without exception stops")

      bootstrap:disconnect(true)
      debugger:dispose()

      return true
    end)
  end)
end)
