-- Test runInTerminal built-in functionality
-- NO MOCKS - tests the actual reverse request handler

local sdk = require("neodap.sdk")
local neostate = require("neostate")

-- Inline verified_it helper since module loading is problematic with plenary
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

describe("runInTerminal Built-in Handler", function()
  verified_it("should invoke runInTerminal and create terminal for Node.js launch", function()
    print("=== TEST START: run_in_terminal ===")

    local debugger = sdk:create_debugger()

    -- Register js-debug adapter
    debugger:register_adapter("pwa-node", {
      type = "server",
      command = "js-debug",
      args = { "0" },
      connect_condition = function(chunk)
        local h, p = chunk:match("Debug server listening at (.*):(%d+)")
        if h and p then
          return tonumber(p), h
        end
        return nil
      end
    })

    local test_file = vim.fn.fnamemodify("./tests/fixtures/run-in-terminal-test.js", ":p")

    -- Add breakpoint BEFORE starting session (so child session will have it)
    local bp = debugger:add_breakpoint({ path = test_file }, 5)

    -- Track runInTerminal calls and captured args
    local run_in_terminal_called = false
    local captured_args = nil
    local original_run_in_terminal = debugger.run_in_terminal
    debugger.run_in_terminal = function(self, args)
      run_in_terminal_called = true
      captured_args = args
      return original_run_in_terminal(self, args)
    end

    -- Start session with integratedTerminal console (triggers runInTerminal)
    local session = debugger:start({
      type = "pwa-node",
      request = "launch",
      name = "RunInTerminal Test",
      program = test_file,
      cwd = vim.fn.getcwd(),
      console = "integratedTerminal", -- This triggers runInTerminal
    })

    -- Wait for terminal buffer to appear
    local found_terminal = false
    vim.wait(5000, function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match("RunInTerminal Test") then
          found_terminal = true
          return true
        end
      end
      return false
    end, 100)

    -- Verify runInTerminal was invoked with correct structure
    assert.is_true(run_in_terminal_called, "runInTerminal handler should be called")
    assert.is_not_nil(captured_args, "Should capture runInTerminal args")
    assert.is_not_nil(captured_args.args, "Args should have 'args' field")
    assert.is_true(#captured_args.args > 0, "Args should have command array")
    assert.are.equal("node", captured_args.args[1], "First arg should be 'node'")
    assert.is_not_nil(captured_args.env, "Args should have 'env' field")
    assert.is_not_nil(captured_args.env.NODE_OPTIONS, "Should have NODE_OPTIONS for bootloader")
    assert.is_not_nil(captured_args.env.NODE_OPTIONS:match("bootloader"),
      "NODE_OPTIONS should reference bootloader")

    -- Verify terminal buffer was created
    assert.is_true(found_terminal, "Terminal buffer should have been created")

    -- Wait for child session to be spawned for the terminal process
    local child_session = nil
    vim.wait(5000, function()
      for session_iter in debugger.sessions:iter() do
        if session_iter.parent == session then
          child_session = session_iter
          return true
        end
      end
      return false
    end)

    assert.is_not_nil(child_session, "Child session should be spawned for terminal process")

    -- Auto-fetch stack when thread stops (needed for frame creation which sets binding.active_frame)
    child_session:onThread(function(thread)
      thread:onStopped(function()
        neostate.void(function()
          thread:stack()
        end)()
      end)
    end)

    -- Wait for child session to stop at breakpoint
    local stopped = vim.wait(10000, function()
      local state = child_session.state:get()
      return state == "stopped"
    end)

    -- Verify the breakpoint was hit
    assert.are.equal("stopped", child_session.state:get(), "Child session should stop at breakpoint")

    -- Verify we have a thread and stack
    local thread = nil
    for t in child_session:threads():iter() do
      thread = t
      break
    end
    assert.is_not_nil(thread, "Child session should have a thread")

    local stack = thread:stack()
    assert.is_not_nil(stack, "Should have stack trace")

    local top_frame = stack:top()
    assert.is_not_nil(top_frame, "Should have top frame")
    assert.are.equal(5, top_frame.line, "Should be stopped at line 5")

    -- Cleanup
    session:disconnect(true)
    debugger:dispose()

    return true
  end)
end)
