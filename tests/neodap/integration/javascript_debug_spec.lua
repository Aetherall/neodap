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

describe("JavaScript Debugging (SDK Demo)", function()
  verified_it("should demonstrate SDK with real JavaScript debugging session", function()
    local debugger = sdk:create_debugger()

    -- Register JavaScript adapter (js-debug uses pwa-node for Node.js)
    debugger:register_adapter("pwa-node", {
      type = "server",
      command = "js-debug",
      args = { "0" },
      connect_condition = function(chunk)
        local h, p = chunk:match("Debug server listening at (.*):(%d+)")
        return tonumber(p), h
      end
    })

    -- Track outputs via SDK session
    local outputs = {}
    local terminated = false

    local script_path = vim.fn.fnamemodify("tests/fixtures/hello.js", ":p")

    -- Start debugging session (SDK handles initialization and launch)
    local session = debugger:start({
      type = "pwa-node",
      request = "launch",
      name = "Test",
      program = script_path,
      console = "internalConsole",
    })

    -- Register output handler using SDK's reactive system
    session:onOutput(function(output)
      table.insert(outputs, {
        category = output.category,
        output = output.output
      })
    end)

    -- Listen for termination
    session.client:on("terminated", function()
      terminated = true
    end)

    -- Wait for program output
    vim.wait(10000, function() return #outputs >= 2 or terminated end)

    assert.is_true(#outputs >= 2, "Should receive output events")

    -- Verify output types
    local found_launch = false
    local has_telemetry = false
    local has_console = false

    for _, output in ipairs(outputs) do
      if output.category == "telemetry" then
        has_telemetry = true
      end

      if output.category == "console" then
        has_console = true
      end

      if output.output and output.output:match("hello%.js") then
        found_launch = true
      end
    end

    -- Assert we got the expected output types
    assert.is_true(found_launch, "Should see program launch in output")
    assert.is_true(has_telemetry or has_console, "Should have telemetry or console output")

    -- Disconnect and cleanup
    session:disconnect(true)
    vim.wait(2000, function() return terminated end)

    debugger:dispose()

    -- This test demonstrates:
    -- ✓ SDK debugger:start() high-level API
    -- ✓ Automatic session initialization and launch
    -- ✓ Reactive output handling via onOutput hook
    -- ✓ Full debugging session from launch to termination
    -- ✓ Clean lifecycle management with dispose()

    return true
  end)
end)
