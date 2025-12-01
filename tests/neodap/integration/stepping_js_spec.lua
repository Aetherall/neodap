-- Tests for stepping operations with js-debug adapter
-- Uses real js-debug adapter with actual JavaScript program

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

describe("JavaScript Stepping Operations", function()
  local script_path = vim.fn.fnamemodify("tests/fixtures/stepping_test.js", ":p")

  -- Helper to get top frame info
  local function get_top_frame_info(thread)
    local stack = thread:stack()
    local top_frame = stack:top()
    return {
      name = top_frame.name,
      line = top_frame.line,
      stack = stack,
      frame = top_frame,
    }
  end

  -- Helper to wait for stopped and get frame info
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

  verified_it("step_over should advance to next line in same function", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("pwa-node", {
      type = "server",
      command = "js-debug",
      args = { "0" },  -- Let js-debug pick a random port
      connect_condition = function(chunk)
        local h, p = chunk:match("Debug server listening at (.*):(%d+)")
        return tonumber(p), h  -- Return both port and host
      end,
    })

    -- Set breakpoint at line 12 (const a = value + 1)
    debugger:add_breakpoint({ path = script_path }, 12)

    -- Start returns the bootstrap session
    local bootstrap = debugger:start({
      type = "pwa-node",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    print("\n=== JS STEP OVER TEST ===")

    -- js-debug creates a child session for actual debugging
    print("  Waiting for child session...")
    local session = wait_for_child_session(bootstrap)
    if not session then
      error("No child session created - js-debug bootstrap may have failed")
    end
    print("  Got child session")

    -- Wait for initial stop at breakpoint
    print("  Waiting for stopped state...")
    vim.wait(15000, function()
      return session.state:get() == "stopped"
    end, 100)
    print(string.format("  Session state: %s", session.state:get()))

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end

    if not thread then
      error("No thread found - session state: " .. session.state:get())
    end

    local frame1 = get_top_frame_info(thread)
    print(string.format("  Initial: %s at line %d", frame1.name, frame1.line))
    -- js-debug uses "global.functionName" format
    assert.is_truthy(frame1.name:match("outerFunction$"), "Should be in outerFunction")
    assert.are.equal(12, frame1.line)

    -- Step over - should go to line 13 (const b = innerFunction(a))
    thread:step_over()
    local frame2 = wait_and_get_frame(session, thread)
    print(string.format("  After step_over #1: %s at line %d", frame2.name, frame2.line))
    assert.is_truthy(frame2.name:match("outerFunction$"), "Should stay in outerFunction")
    assert.are.equal(13, frame2.line, "Should be at line 13")

    -- Step over again - should skip innerFunction and go to line 14
    thread:step_over()
    local frame3 = wait_and_get_frame(session, thread)
    print(string.format("  After step_over #2: %s at line %d", frame3.name, frame3.line))
    assert.is_truthy(frame3.name:match("outerFunction$"), "Should stay in outerFunction")
    assert.are.equal(14, frame3.line, "Should be at line 14 (skipped innerFunction)")

    -- Cleanup
    bootstrap:disconnect(true)
    vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("step_into should enter function calls", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("pwa-node", {
      type = "server",
      command = "js-debug",
      args = { "0" },  -- Let js-debug pick a random port
      connect_condition = function(chunk)
        local h, p = chunk:match("Debug server listening at (.*):(%d+)")
        return tonumber(p), h  -- Return both port and host
      end,
    })

    -- Set breakpoint at line 13 (const b = innerFunction(a)) - the function call
    debugger:add_breakpoint({ path = script_path }, 13)

    -- Start returns the bootstrap session
    local bootstrap = debugger:start({
      type = "pwa-node",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    print("\n=== JS STEP INTO TEST ===")

    -- js-debug creates a child session for actual debugging
    local session = wait_for_child_session(bootstrap)
    if not session then
      error("No child session created")
    end

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
    -- js-debug uses "global.functionName" format
    assert.is_truthy(frame1.name:match("outerFunction$"), "Should be in outerFunction")
    assert.are.equal(13, frame1.line)

    -- Step into - should enter innerFunction
    thread:step_into()
    local frame2 = wait_and_get_frame(session, thread)
    print(string.format("  After step_into: %s at line %d", frame2.name, frame2.line))

    -- Show full stack
    print("    Full stack:")
    for frame in frame2.stack:frames():iter() do
      print(string.format("      [%d] %s at line %d", frame.index:get(), frame.name, frame.line))
    end

    assert.is_truthy(frame2.name:match("innerFunction$"), "Should enter innerFunction")
    assert.are.equal(7, frame2.line, "Should be at line 7 (first line of innerFunction)")

    -- Verify stack depth increased
    local frame_count = 0
    for _ in frame2.stack:frames():iter() do
      frame_count = frame_count + 1
    end
    print(string.format("  Stack depth: %d frames", frame_count))
    assert.is_true(frame_count >= 3, "Should have at least 3 frames (innerFunction, outerFunction, main)")

    -- Cleanup
    bootstrap:disconnect(true)
    vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("step_out should exit current function to caller", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("pwa-node", {
      type = "server",
      command = "js-debug",
      args = { "0" },  -- Let js-debug pick a random port
      connect_condition = function(chunk)
        local h, p = chunk:match("Debug server listening at (.*):(%d+)")
        return tonumber(p), h  -- Return both port and host
      end,
    })

    -- Set breakpoint at line 7 (inside innerFunction)
    debugger:add_breakpoint({ path = script_path }, 7)

    -- Start returns the bootstrap session
    local bootstrap = debugger:start({
      type = "pwa-node",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    print("\n=== JS STEP OUT TEST ===")

    -- js-debug creates a child session for actual debugging
    local session = wait_for_child_session(bootstrap)
    if not session then
      error("No child session created")
    end

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
    -- js-debug uses "global.functionName" format
    assert.is_truthy(frame1.name:match("innerFunction$"), "Should be in innerFunction")
    assert.are.equal(7, frame1.line)

    -- Step out - should return to outerFunction after innerFunction completes
    thread:step_out()
    local frame2 = wait_and_get_frame(session, thread)
    print(string.format("  After step_out: %s at line %d", frame2.name, frame2.line))

    -- Show full stack
    print("    Full stack:")
    for frame in frame2.stack:frames():iter() do
      print(string.format("      [%d] %s at line %d", frame.index:get(), frame.name, frame.line))
    end

    assert.is_truthy(frame2.name:match("outerFunction$"), "Should be back in outerFunction")
    -- After step_out, we should be back at the call site (line 13) or the next line (14)
    assert.is_true(frame2.line >= 13 and frame2.line <= 14,
      "Should be at or after the function call (line 13-14)")

    -- Cleanup
    bootstrap:disconnect(true)
    vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("step operations should mark previous stack as expired", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("pwa-node", {
      type = "server",
      command = "js-debug",
      args = { "0" },  -- Let js-debug pick a random port
      connect_condition = function(chunk)
        local h, p = chunk:match("Debug server listening at (.*):(%d+)")
        return tonumber(p), h  -- Return both port and host
      end,
    })

    -- Set breakpoint at line 12
    debugger:add_breakpoint({ path = script_path }, 12)

    -- Start returns the bootstrap session
    local bootstrap = debugger:start({
      type = "pwa-node",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    print("\n=== JS STEP STACK EXPIRATION TEST ===")

    -- js-debug creates a child session for actual debugging
    local session = wait_for_child_session(bootstrap)
    if not session then
      error("No child session created")
    end

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
    bootstrap:disconnect(true)
    vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)
end)
