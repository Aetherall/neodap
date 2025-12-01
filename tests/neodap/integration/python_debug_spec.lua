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

describe("Python Debugging (SDK Demo)", function()
  verified_it("should demonstrate SDK with real Python debugging session", function()
    local debugger = sdk:create_debugger()

    -- Register Python adapter
    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Track outputs via SDK session
    local outputs = {}
    local terminated = false

    local script_path = vim.fn.fnamemodify("tests/fixtures/hello.py", ":p")

    -- Start debugging session (SDK handles initialization and launch)
    local session = debugger:start({
      type = "python",
      request = "launch",
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
    vim.wait(10000, function() return #outputs >= 4 or terminated end)

    assert.is_true(#outputs >= 4, "Should receive at least 4 output events")

    -- Verify output types
    local found_stdout = false
    local found_stderr = false

    for _, output in ipairs(outputs) do
      if output.category == "stdout" then
        found_stdout = true
      end

      if output.category == "stderr" then
        found_stderr = true
      end
    end

    -- Assert we got the expected output types
    assert.is_true(found_stdout, "Should see stdout output")
    assert.is_true(found_stderr, "Should see stderr output")

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
