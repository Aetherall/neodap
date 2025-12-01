-- Tests for stepping operations: step_over, step_into, step_out
-- Uses real debugpy adapter with actual Python program

local sdk = require("neodap.sdk")
local neostate = require("neostate")

-- Inline verified_it helper for async tests
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

describe("Stepping Operations", function()
  local script_path = vim.fn.getcwd() .. "/tests/fixtures/stepping_test.py"

  -- Helper to get top frame info
  local function get_top_frame_info(thread, show_stack)
    local stack = thread:stack()
    local top_frame = stack:top()

    if show_stack then
      print("    Stack frames:")
      for frame in stack:frames():iter() do
        print(string.format("      [%d] %s at line %d", frame.index:get(), frame.name, frame.line))
      end
    end

    return {
      name = top_frame.name,
      line = top_frame.line,
      stack = stack,
      frame = top_frame,
    }
  end

  -- Helper to wait for stopped and get frame info
  -- Must wait for state to change (running -> stopped) not just be stopped
  local function wait_and_get_frame(session, thread)
    -- First wait for running state (step command was sent)
    vim.wait(5000, function()
      return session.state:get() == "running"
    end, 10)

    -- Then wait for stopped state (step completed)
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end, 10)
    assert.are.equal("stopped", session.state:get())
    return get_top_frame_info(thread)
  end

  verified_it("step_over should advance to next line in same function", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Set breakpoint at line 11 (a = value + 1)
    debugger:add_breakpoint({ path = script_path }, 11)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    print("\n=== STEP OVER TEST ===")

    -- Wait for initial stop at breakpoint
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end

    local frame1 = get_top_frame_info(thread)
    print(string.format("  Initial: %s at line %d", frame1.name, frame1.line))
    assert.are.equal("outer_function", frame1.name)
    assert.are.equal(11, frame1.line)

    -- Step over - should go to line 12 (b = inner_function(a))
    thread:step_over()
    local frame2 = wait_and_get_frame(session, thread)
    print(string.format("  After step_over #1: %s at line %d", frame2.name, frame2.line))
    assert.are.equal("outer_function", frame2.name, "Should stay in outer_function")
    assert.are.equal(12, frame2.line, "Should be at line 12")

    -- Step over again - should skip inner_function and go to line 13
    thread:step_over()
    local frame3 = wait_and_get_frame(session, thread)
    print(string.format("  After step_over #2: %s at line %d", frame3.name, frame3.line))
    assert.are.equal("outer_function", frame3.name, "Should stay in outer_function")
    assert.are.equal(13, frame3.line, "Should be at line 13 (skipped inner_function)")

    -- Cleanup
    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("step_into should enter function calls", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Set breakpoint at line 12 (b = inner_function(a)) - the function call
    debugger:add_breakpoint({ path = script_path }, 12)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    print("\n=== STEP INTO TEST ===")

    -- Wait for initial stop at breakpoint
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end

    local frame1 = get_top_frame_info(thread)
    print(string.format("  Initial: %s at line %d", frame1.name, frame1.line))
    assert.are.equal("outer_function", frame1.name)
    assert.are.equal(12, frame1.line)

    -- Step into - should enter inner_function
    thread:step_into()
    local frame2 = wait_and_get_frame(session, thread)
    print(string.format("  After step_into: %s at line %d", frame2.name, frame2.line))

    -- Show full stack
    print("    Full stack:")
    for frame in frame2.stack:frames():iter() do
      print(string.format("      [%d] %s at line %d", frame.index:get(), frame.name, frame.line))
    end

    assert.are.equal("inner_function", frame2.name, "Should enter inner_function")
    assert.are.equal(6, frame2.line, "Should be at line 6 (first line of inner_function)")

    -- Verify stack depth increased
    local frame_count = 0
    for _ in frame2.stack:frames():iter() do
      frame_count = frame_count + 1
    end
    print(string.format("  Stack depth: %d frames", frame_count))
    assert.is_true(frame_count >= 3, "Should have at least 3 frames (inner_function, outer_function, main)")

    -- Cleanup
    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("step_out should exit current function to caller", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Set breakpoint at line 6 (inside inner_function)
    debugger:add_breakpoint({ path = script_path }, 6)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    print("\n=== STEP OUT TEST ===")

    -- Wait for initial stop at breakpoint
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end

    local frame1 = get_top_frame_info(thread)
    print(string.format("  Initial: %s at line %d", frame1.name, frame1.line))
    assert.are.equal("inner_function", frame1.name)
    assert.are.equal(6, frame1.line)

    -- Step out - should return to outer_function after inner_function completes
    thread:step_out()
    local frame2 = wait_and_get_frame(session, thread)
    print(string.format("  After step_out: %s at line %d", frame2.name, frame2.line))

    -- Show full stack
    print("    Full stack:")
    for frame in frame2.stack:frames():iter() do
      print(string.format("      [%d] %s at line %d", frame.index:get(), frame.name, frame.line))
    end

    assert.are.equal("outer_function", frame2.name, "Should be back in outer_function")
    -- After step_out, we should be back at the call site (line 12) or the next line (13)
    assert.is_true(frame2.line >= 12 and frame2.line <= 13,
      "Should be at or after the function call (line 12-13)")

    -- Cleanup
    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("step operations should mark previous stack as expired", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Set breakpoint at line 11
    debugger:add_breakpoint({ path = script_path }, 11)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    print("\n=== STEP STACK EXPIRATION TEST ===")

    -- Wait for initial stop
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end

    -- Get first stack
    local stack1 = thread:stack()
    local frame1 = stack1:top()
    print(string.format("  Stack 1: %s, is_current=%s", stack1.id, tostring(stack1:is_current())))
    assert.is_true(stack1:is_current(), "Stack 1 should be current")
    assert.is_true(frame1:is_current(), "Frame 1 should be current")

    -- Step over
    thread:step_over()

    -- After step, previous stack should be expired
    print(string.format("  Stack 1 after step: is_current=%s", tostring(stack1:is_current())))
    assert.is_false(stack1:is_current(), "Stack 1 should be expired after step")
    assert.is_false(frame1:is_current(), "Frame 1 should be expired after step")

    -- Wait for new stop
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    -- Get new stack
    local stack2 = thread:stack()
    print(string.format("  Stack 2: %s, is_current=%s", stack2.id, tostring(stack2:is_current())))
    assert.is_true(stack2:is_current(), "Stack 2 should be current")
    assert.are_not.equal(stack1.id, stack2.id, "Should be different stacks")

    -- Cleanup
    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("step_into with granularity should respect granularity setting", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Set breakpoint at line 11
    debugger:add_breakpoint({ path = script_path }, 11)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    print("\n=== STEP GRANULARITY TEST ===")

    -- Wait for initial stop
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end

    local frame1 = get_top_frame_info(thread)
    print(string.format("  Initial: %s at line %d", frame1.name, frame1.line))

    -- Step with line granularity (default behavior)
    local err = thread:step_over("line")
    assert.is_nil(err, "step_over with granularity should succeed")

    local frame2 = wait_and_get_frame(session, thread)
    print(string.format("  After step_over('line'): %s at line %d", frame2.name, frame2.line))
    assert.are.equal(12, frame2.line, "Should advance by line")

    -- Cleanup
    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)
end)
