-- Test lifecycle hooks with real Python debugging session
-- NO MOCKS - uses real debugpy adapter and actual Python program

local neostate = require("neostate")
local sdk = require("neodap.sdk")
local async = require("plenary.async.tests")

neostate.setup({
  debug_context = true,
  trace = true,
})

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

describe("SDK Lifecycle Hooks (Real Debugger)", function()
  local script_path = vim.fn.getcwd() .. "/tests/fixtures/stack_test.py"

  -- ==========================================================================
  -- DEBUGGER HOOKS
  -- ==========================================================================

  verified_it("should trigger debugger:onSession when session is created", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local session_called = false
    local captured_session = nil

    debugger:onSession(function(session)
      session_called = true
      captured_session = session
    end)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    -- Wait briefly for hook to fire
    vim.wait(100)

    assert.is_true(session_called, "onSession should be called")
    assert.are.equal(session.id, captured_session.id, "should receive the created session")

    -- Cleanup
    session:disconnect(true)
    debugger:dispose()

    return true
  end)

  it("should trigger debugger:onBreakpoint when breakpoint is added", function()
    local debugger = sdk:create_debugger()

    local breakpoint_called = false
    local captured_breakpoint = nil

    debugger:onBreakpoint(function(breakpoint)
      breakpoint_called = true
      captured_breakpoint = breakpoint
    end)

    local bp = debugger:add_breakpoint({ path = script_path }, 10)

    assert.is_true(breakpoint_called, "onBreakpoint should be called")
    assert.are.equal(bp, captured_breakpoint, "should receive the added breakpoint")
    assert.are.equal(10, captured_breakpoint.line, "should have correct line number")

    debugger:dispose()
  end)

  -- ==========================================================================
  -- SESSION HOOKS
  -- ==========================================================================

  verified_it("should trigger session:onThread when thread appears", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    local thread_called = false
    local captured_thread = nil

    session:onThread(function(thread)
      thread_called = true
      captured_thread = thread
    end)

    -- Wait for thread event
    vim.wait(5000, function()
      local count = 0
      for _ in session:threads():iter() do
        count = count + 1
      end
      return count > 0
    end)

    assert.is_true(thread_called, "onThread should be called")
    assert.is_not_nil(captured_thread, "should receive thread")
    assert.is_number(captured_thread.id, "thread should have ID")

    session:disconnect(true)
    debugger:dispose()

    return true
  end)

  verified_it("should trigger session:onBinding when breakpoint is bound", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Add breakpoint BEFORE starting session
    local bp = debugger:add_breakpoint({ path = script_path }, 10)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    local binding_called = false
    local captured_binding = nil

    session:onBinding(function(binding)
      binding_called = true
      captured_binding = binding
    end)

    -- Wait for binding to be created
    vim.wait(5000, function()
      local count = 0
      for _ in session:bindings():iter() do
        count = count + 1
      end
      return count > 0
    end)

    assert.is_true(binding_called, "onBinding should be called")
    assert.is_not_nil(captured_binding, "should receive binding")
    assert.are.equal(bp, captured_binding.breakpoint, "binding should reference the breakpoint")

    session:disconnect(true)
    debugger:dispose()

    return true
  end)

  verified_it("should trigger session:onOutput when debug output occurs", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    local output_called = false
    local captured_output = nil

    session:onOutput(function(output)
      output_called = true
      captured_output = output
    end)

    -- Wait for output event
    vim.wait(5000, function()
      local count = 0
      for _ in session:outputs():iter() do
        count = count + 1
      end
      return count > 0
    end)

    assert.is_true(output_called, "onOutput should be called")
    assert.is_not_nil(captured_output, "should receive output")
    assert.is_string(captured_output.output, "output should have text")

    session:disconnect(true)
    debugger:dispose()

    return true
  end)

  verified_it("should trigger session:onSource when source is created (lazy - via stack fetch)", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local bp = debugger:add_breakpoint({ path = script_path }, 10)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    -- Wait for stopped state
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    assert.are.equal("stopped", session.state:get(), "session should be stopped")

    -- Sources should NOT exist yet (not auto-fetched)
    local sources_list = session:sources()
    assert.are.equal(0, #sources_list, "sources should not exist before stack fetch")

    local source_called = false
    local captured_source = nil

    session:onSource(function(source)
      source_called = true
      captured_source = source
    end)

    -- Hook should NOT have fired yet (no sources exist)
    assert.is_false(source_called, "onSource should NOT fire until stack is fetched")

    -- Get thread and access its stack (which creates sources)
    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end
    assert.is_not_nil(thread, "thread should exist")
    local stack = thread:stack()
    assert.is_not_nil(stack, "stack should be fetched")

    -- Now sources should exist and hook should have fired
    sources_list = session:sources()
    local source_count = #sources_list
    assert.is_true(source_count > 0, "sources should exist after stack fetch (found " .. source_count .. ")")
    assert.is_true(source_called, "onSource should fire when stack is fetched")
    assert.is_not_nil(captured_source, "should receive source")
    assert.are.equal(script_path, captured_source.path, "source should have correct path")

    session:disconnect(true)
    debugger:dispose()

    return true
  end)

  -- ==========================================================================
  -- THREAD HOOKS
  -- ==========================================================================

  verified_it("should trigger thread:onStopped when thread hits breakpoint", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local bp = debugger:add_breakpoint({ path = script_path }, 10)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    -- Wait for thread to appear
    vim.wait(5000, function()
      local count = 0
      for _ in session:threads():iter() do
        count = count + 1
      end
      return count > 0
    end)

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end
    assert.is_not_nil(thread, "thread should exist")

    local stopped_called = false
    local captured_reason = nil

    thread:onStopped(function(reason)
      stopped_called = true
      captured_reason = reason
    end)

    -- Wait for stopped event
    vim.wait(10000, function()
      return thread.state:get() == "stopped"
    end)

    assert.is_true(stopped_called, "onStopped should be called")
    assert.is_string(captured_reason, "should receive stop reason")
    assert.are.equal("breakpoint", captured_reason, "should stop at breakpoint")

    session:disconnect(true)
    debugger:dispose()

    return true
  end)

  verified_it("should trigger thread:onResumed when thread continues after stop", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local bp = debugger:add_breakpoint({ path = script_path }, 10)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    -- Wait for thread to stop at breakpoint
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end
    assert.is_not_nil(thread, "thread should exist")
    assert.are.equal("stopped", thread.state:get(), "thread should be stopped")

    local resumed_called = false

    thread:onResumed(function()
      resumed_called = true
    end)

    -- Continue execution (now async)
    session:continue(thread.id)

    -- Wait for resumed event
    vim.wait(2000, function()
      return resumed_called
    end)

    assert.is_true(resumed_called, "onResumed should be called")

    session:disconnect(true)
    debugger:dispose()

    return true
  end)

  verified_it("should trigger thread:onStack when someone explicitly fetches stack", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local bp = debugger:add_breakpoint({ path = script_path }, 10)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    -- Wait for thread to appear
    vim.wait(5000, function()
      local count = 0
      for _ in session:threads():iter() do
        count = count + 1
      end
      return count > 0
    end)

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end
    assert.is_not_nil(thread, "thread should exist")

    -- Wait for stopped state
    vim.wait(10000, function()
      return thread.state:get() == "stopped"
    end)

    -- Stack should NOT be auto-fetched when thread stops
    assert.is_nil(thread._current_stack:get(), "stack should NOT be auto-fetched")

    local stack_called = false
    local captured_stack = nil

    -- Register the hook BEFORE fetching stack
    thread:onStack(function(stack)
      stack_called = true
      captured_stack = stack
    end)

    -- Hook should NOT have fired yet (no stack exists)
    assert.is_false(stack_called, "onStack should NOT fire until stack is fetched")

    -- NOW explicitly fetch the stack - this should trigger the hook
    local stack = thread:stack()

    -- Hook should fire when stack() is called
    assert.is_true(stack_called, "onStack should fire when stack() is called")
    assert.is_not_nil(captured_stack, "should receive stack")

    local frame_count = 0
    for _ in captured_stack:frames():iter() do
      frame_count = frame_count + 1
    end
    assert.is_true(frame_count > 0, "stack should have frames")
    assert.are.equal(stack, captured_stack, "captured stack should match returned stack")

    session:disconnect(true)
    debugger:dispose()

    return true
  end)

  -- ==========================================================================
  -- STACK HOOKS
  -- ==========================================================================

  verified_it("should trigger stack:onExpired when stack becomes stale", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Add two breakpoints to create multiple stops
    local bp1 = debugger:add_breakpoint({ path = script_path }, 10)
    local bp2 = debugger:add_breakpoint({ path = script_path }, 14)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
      stopOnEntry = false,
    })

    -- Wait for first stop
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end
    assert.is_not_nil(thread, "thread should exist")

    local first_stack = thread:stack()
    assert.is_not_nil(first_stack, "first stack should exist")
    assert.is_true(first_stack:is_current(), "first stack should be current")

    local expired_called = false

    first_stack:onExpired(function()
      expired_called = true
    end)

    -- Continue to next breakpoint (will expire current stack)
    session:continue(thread.id)

    -- Wait for second stop
    vim.wait(10000, function()
      local t = nil
      for thread in session:threads():iter() do
        t = thread
        break
      end
      if not t then return false end

      local stale_count = 0
      for _ in t:stale_stacks():iter() do
        stale_count = stale_count + 1
      end

      return t.state:get() == "stopped" and stale_count > 0
    end)

    assert.is_true(expired_called, "onExpired should be called")
    assert.is_false(first_stack:is_current(), "first stack should no longer be current")

    local stale_count = 0
    for _ in thread:stale_stacks():iter() do
      stale_count = stale_count + 1
    end
    assert.are.equal(1, stale_count, "should have one stale stack")

    session:disconnect(true)
    debugger:dispose()

    return true
  end)

  verified_it("should trigger frame:onExpired when stack becomes stale", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local bp1 = debugger:add_breakpoint({ path = script_path }, 10)
    local bp2 = debugger:add_breakpoint({ path = script_path }, 14)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
      stopOnEntry = false,
    })

    vim.wait(10000, function() return session.state:get() == "stopped" end)

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end
    local stack = thread:stack()
    local frame = stack:frames():get_one("by_index", 0)

    local expired_called = false
    frame:onExpired(function()
      expired_called = true
    end)

    session:continue(thread.id)
    vim.wait(10000, function() return session.state:get() == "stopped" end)

    assert.is_true(expired_called, "frame:onExpired should be called")
    assert.is_false(frame:is_current(), "frame should no longer be current")

    session:disconnect(true)
    debugger:dispose()

    return true
  end)

  -- ==========================================================================
  -- BINDING & BREAKPOINT HOOKS
  -- ==========================================================================

  verified_it("should trigger binding:onVerified and binding:onHit", function()
    print("=== TEST START ===")
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local bp = debugger:add_breakpoint({ path = script_path }, 11)  -- line: y = level_3() - executable line

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
      stopOnEntry = false,
    })

    -- Auto-fetch stack when thread stops (needed for frame creation which sets binding.active_frame)
    session:onThread(function(thread)
      thread:onStopped(function()
        neostate.void(function()
          thread:stack()
        end)()
      end)
    end)

    print("=== Waiting for binding ===")
    -- Wait for binding
    local has_binding = false
    vim.wait(5000, function()
      local count = 0
      for _ in session:bindings():iter() do
        count = count + 1
      end
      has_binding = count > 0
      return has_binding
    end)

    local binding = nil
    for b in session:bindings():iter() do
      binding = b
      break
    end
    assert.is_not_nil(binding, "Should have binding")
    print(string.format("=== Binding info: bp.line=%d, actualLine=%s, session.id=%s ===",
      binding.breakpoint.line, tostring(binding.actualLine:get()), binding.session.id))

    local verified_called = false
    binding:onVerified(function(verified)
      print(string.format("=== onVerified hook fired: verified=%s ===", tostring(verified)))
      if verified then verified_called = true end
    end)

    local hit_called = false
    local captured_frame = nil
    binding:onHit(function()
      hit_called = true
      -- Use active_frame signal instead of expecting frame parameter
      captured_frame = binding.active_frame:get()
    end)

    print("=== Waiting for verification ===")
    -- Wait for verification (should happen quickly after launch)
    vim.wait(2000, function() return binding.verified:get() end)

    -- Give the hook callback time to fire
    vim.wait(1000, function() return verified_called end)

    print(string.format("=== verified_called=%s, binding.verified=%s ===", tostring(verified_called), tostring(binding.verified:get())))
    assert.is_true(verified_called, "binding:onVerified should be called")

    print("=== Waiting for stopped state ===")
    -- Wait for hit (when execution stops at bp)
    local stopped = vim.wait(10000, function() return session.state:get() == "stopped" end)
    assert.is_true(stopped, "Session should reach stopped state")

    print("=== Waiting for active_frame ===")
    -- The 'stopped' event processing updates binding hit status
    local has_active_frame = vim.wait(2000, function() return binding.active_frame:get() ~= nil end)
    assert.is_true(has_active_frame, "Binding should have active_frame after stop")

    print("=== Checking final assertions ===")
    assert.is_true(hit_called, "binding:onHit should be called")
    assert.is_not_nil(captured_frame, "binding:onHit should receive frame")

    print("=== Test completed successfully, cleaning up ===")
    session:disconnect(true)
    debugger:dispose()
    print("=== Cleanup done ===")

    return true
  end)

  verified_it("should trigger breakpoint:onHit and breakpoint:onSession", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local bp = debugger:add_breakpoint({ path = script_path }, 10)

    local session_called = false
    local captured_session = nil
    bp:onSession(function(s)
      session_called = true
      captured_session = s
    end)

    local hit_called = false
    local captured_binding = nil
    bp:onHit(function(binding)
      hit_called = true
      captured_binding = binding
    end)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
      stopOnEntry = false,
    })

    -- Auto-fetch stack when thread stops (needed for frame creation which sets binding.active_frame)
    session:onThread(function(thread)
      thread:onStopped(function()
        neostate.void(function()
          thread:stack()
        end)()
      end)
    end)

    -- Wait for session hook
    vim.wait(5000, function() return session_called end)
    assert.is_true(session_called, "breakpoint:onSession should be called")
    assert.are.equal(session.id, captured_session.id, "should receive correct session")

    -- Wait for hit
    vim.wait(10000, function() return session.state:get() == "stopped" end)

    -- Allow time for binding update propagation and stack fetch
    vim.wait(2000, function() return hit_called end)

    assert.is_true(hit_called, "breakpoint:onHit should be called")
    assert.is_not_nil(captured_binding, "should receive binding")
    assert.are.equal(bp, captured_binding.breakpoint, "binding should belong to breakpoint")

    session:disconnect(true)
    debugger:dispose()

    return true
  end)
end)
