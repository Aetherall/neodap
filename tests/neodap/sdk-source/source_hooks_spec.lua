local neostate = require("neostate")
local sdk = require("neodap.sdk")
local async = require("plenary.async.tests")

neostate.setup({
  debug_context = false,
  trace = false,  -- Disable for clean test output
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

describe("Source-Centric Hooks (Real Debugger)", function()
  verified_it("source:onBreakpoint() fires when breakpoints added", function()
    print("=== 1. TEST START ===")
    local debugger = sdk:create_debugger()

    print("=== 2. AFTER CREATE DEBUGGER ===")
    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local script_path = vim.fn.fnamemodify("tests/fixtures/simple_python.py", ":p")

    print("=== 3. STARTING SESSION ===")
    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
      stopOnEntry = false,
    })

    print("=== 4. GETTING SOURCE ===")
    -- Get the source for our test file
    local source = session:get_or_create_source({ path = script_path })

    -- Track breakpoints added
    local breakpoints_added = {}
    source:onBreakpoint(function(bp)
      table.insert(breakpoints_added, bp)
    end)

    print("=== 5. ADDING FIRST BREAKPOINT ===")
    -- Add a breakpoint to this source
    local bp1 = debugger:add_breakpoint({ path = script_path }, 6)

    print("=== 6. WAITING FOR BREAKPOINT ===")
    -- Should fire immediately for new breakpoint
    vim.wait(1000, function() return #breakpoints_added >= 1 end)
    assert.are.equal(1, #breakpoints_added)
    assert.are.equal(bp1.id, breakpoints_added[1].id)

    print("=== 7. ADDING SECOND BREAKPOINT ===")
    -- Add another breakpoint
    local bp2 = debugger:add_breakpoint({ path = script_path }, 7)

    vim.wait(1000, function() return #breakpoints_added >= 2 end)
    assert.are.equal(2, #breakpoints_added)
    assert.are.equal(bp2.id, breakpoints_added[2].id)

    print("=== 8. COUNTING BREAKPOINTS ===")
    -- Verify source.breakpoints() returns both
    local bp_count = 0
    for _ in source:breakpoints():iter() do
      bp_count = bp_count + 1
    end
    assert.are.equal(2, bp_count)

    print("=== 9. CLEANING UP ===")
    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    session:dispose()
    debugger:dispose()
    print("=== 10. TEST COMPLETE ===")

    return true
  end)

  verified_it("source:onFrame() fires when execution enters source", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local script_path = vim.fn.fnamemodify("tests/fixtures/simple_python.py", ":p")

    -- Add breakpoint first so we stop
    local bp = debugger:add_breakpoint({ path = script_path }, 6)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
      stopOnEntry = false,
    })

    -- Get the source
    local source = session:get_or_create_source({ path = script_path })

    -- Track frames entering this source
    local frames_seen = {}
    source:onFrame(function(frame)
      table.insert(frames_seen, frame)
    end)

    -- Fetch frames when thread stops (triggers frame hooks)
    session:onThread(function(thread)
      thread:onStopped(function()
        neostate.void(function()
          thread:stack()
        end)()
      end)
    end)

    -- Wait for stopped event
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)
    assert.are.equal("stopped", session.state:get())

    -- Wait a bit for async frame loading to complete (void() is fire-and-forget)
    vim.wait(2000, function() return #frames_seen > 0 end)

    -- Should have at least one frame at this source
    assert.is_true(#frames_seen > 0, "Expected frames to be seen at source")

    -- Verify all frames are actually at this source
    for _, frame in ipairs(frames_seen) do
      assert.are.equal(source.correlation_key, frame.source.correlation_key)
    end

    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    session:dispose()
    debugger:dispose()

    return true
  end)

  verified_it("source:onTopFrame() fires for topmost frame only", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local script_path = vim.fn.fnamemodify("tests/fixtures/simple_python.py", ":p")

    -- Add breakpoint
    local bp = debugger:add_breakpoint({ path = script_path }, 6)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
      stopOnEntry = false,
    })

    local source = session:get_or_create_source({ path = script_path })

    -- Track top frames only
    local top_frames_seen = {}
    source:onTopFrame(function(frame)
      table.insert(top_frames_seen, frame)
    end)

    -- Fetch frames when thread stops (triggers frame hooks)
    session:onThread(function(thread)
      thread:onStopped(function()
        neostate.void(function()
          thread:stack()
        end)()
      end)
    end)

    -- Wait for stopped
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)
    assert.are.equal("stopped", session.state:get())

    -- Wait a bit for async frame loading to complete
    vim.wait(2000, function() return #top_frames_seen > 0 end)

    -- Should have at least one top frame
    assert.is_true(#top_frames_seen > 0, "Expected top frames to be seen")

    -- All should be at index 0
    for _, frame in ipairs(top_frames_seen) do
      assert.are.equal(0, frame.index:get())
    end

    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    session:dispose()
    debugger:dispose()

    return true
  end)

  verified_it("source:onActiveFrame() fires for current frames only", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local script_path = vim.fn.fnamemodify("tests/fixtures/simple_python.py", ":p")

    local bp = debugger:add_breakpoint({ path = script_path }, 6)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
      stopOnEntry = false,
    })

    local source = session:get_or_create_source({ path = script_path })

    -- Track active frames
    local active_frames = {}
    source:onActiveFrame(function(frame)
      table.insert(active_frames, frame)
    end)

    -- Fetch frames when thread stops (triggers frame hooks)
    session:onThread(function(thread)
      thread:onStopped(function()
        neostate.void(function()
          thread:stack()
        end)()
      end)
    end)

    -- Wait for stopped
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)
    assert.are.equal("stopped", session.state:get())

    -- Wait a bit for async frame loading to complete
    vim.wait(2000, function() return #active_frames > 0 end)

    -- Should have active frames
    assert.is_true(#active_frames > 0, "Expected active frames")

    -- All should be current (not stale)
    for _, frame in ipairs(active_frames) do
      assert.is_true(frame._is_current:get())
    end

    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    session:dispose()
    debugger:dispose()

    return true
  end)

  verified_it("source.frames() returns frames across ALL sessions", function()
    -- This test verifies that source.frames() is a cross-session query
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local script_path = vim.fn.fnamemodify("tests/fixtures/simple_python.py", ":p")

    local bp = debugger:add_breakpoint({ path = script_path }, 6)

    -- Fetch frames when any thread stops
    debugger:onSession(function(session)
      session:onThread(function(thread)
        thread:onStopped(function()
          neostate.void(function()
            thread:stack()
          end)()
        end)
      end)
    end)

    -- Start first session
    local session1 = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
      stopOnEntry = false,
    })

    -- Wait for first session to stop
    vim.wait(10000, function()
      return session1.state:get() == "stopped"
    end)
    assert.are.equal("stopped", session1.state:get())

    -- Get source from first session
    local source = session1:get_or_create_source({ path = script_path })

    -- Wait for async frame loading
    vim.wait(2000)

    -- Count frames from first session
    local frame_count_1 = 0
    for _ in source:frames():iter() do
      frame_count_1 = frame_count_1 + 1
    end
    assert.is_true(frame_count_1 > 0, "Expected frames from first session")

    -- Start second session (same file)
    local session2 = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
      stopOnEntry = false,
    })

    -- Wait for second session to stop
    vim.wait(10000, function()
      return session2.state:get() == "stopped"
    end)
    assert.are.equal("stopped", session2.state:get())

    -- Wait for async frame loading
    vim.wait(2000)

    -- Now count frames from both sessions via the source
    local frame_count_2 = 0
    for _ in source:frames():iter() do
      frame_count_2 = frame_count_2 + 1
    end

    -- Should have more frames now (from both sessions)
    assert.is_true(frame_count_2 > frame_count_1,
      string.format("Expected more frames after second session (got %d vs %d)",
        frame_count_2, frame_count_1))

    -- Verify frames come from different sessions
    local session_ids = {}
    for frame in source:frames():iter() do
      session_ids[frame.stack.thread.session.id] = true
    end

    local session_count = 0
    for _ in pairs(session_ids) do
      session_count = session_count + 1
    end
    assert.are.equal(2, session_count, "Expected frames from 2 different sessions")

    session1:disconnect(true)
    session2:disconnect(true)
    vim.wait(2000, function()
      return session1.state:get() == "terminated" and session2.state:get() == "terminated"
    end)
    session1:dispose()
    session2:dispose()
    debugger:dispose()

    return true
  end)

  verified_it("source.breakpoints() works for local sources with correlation_key", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local script_path = vim.fn.fnamemodify("tests/fixtures/simple_python.py", ":p")

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
      stopOnEntry = false,
    })

    -- Local source with path
    local local_source = session:get_or_create_source({ path = script_path })

    -- Add multiple breakpoints
    local bp1 = debugger:add_breakpoint({ path = script_path }, 6)
    local bp2 = debugger:add_breakpoint({ path = script_path }, 7)

    -- Query breakpoints via source
    local bp_count = 0
    for _ in local_source:breakpoints():iter() do
      bp_count = bp_count + 1
    end
    assert.are.equal(2, bp_count, "Expected 2 breakpoints for local source")

    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    session:dispose()
    debugger:dispose()

    return true
  end)
  verified_it("source:onActiveFrame() cleanup runs when frame is no longer active", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local script_path = vim.fn.fnamemodify("tests/fixtures/simple_python.py", ":p")
    local bp = debugger:add_breakpoint({ path = script_path }, 6)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
      stopOnEntry = false,
    })

    local source = session:get_or_create_source({ path = script_path })
    local cleanup_called = false
    local hook_fired = false

    source:onActiveFrame(function(frame)
      hook_fired = true
      return function()
        cleanup_called = true
      end
    end)

    -- Fetch frames when thread stops (triggers frame hooks)
    session:onThread(function(thread)
      thread:onStopped(function()
        neostate.void(function()
          thread:stack()
        end)()
      end)
    end)

    vim.wait(10000, function() return session.state:get() == "stopped" end)

    -- Wait for async frame loading
    vim.wait(2000, function() return hook_fired end)

    assert.is_true(hook_fired, "Hook should have fired")
    assert.is_false(cleanup_called, "Cleanup should not have fired yet")

    -- Continue to invalidate stack
    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end
    assert.is_not_nil(thread, "Expected at least one thread")
    session:continue(thread.id)

    vim.wait(2000, function() return cleanup_called end)
    assert.is_true(cleanup_called, "Cleanup should have fired")

    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    session:dispose()
    debugger:dispose()

    return true
  end)

  verified_it("source:onBreakpoint() cleanup runs when breakpoint is removed", function()
    local debugger = sdk:create_debugger()
    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })
    local script_path = vim.fn.fnamemodify("tests/fixtures/simple_python.py", ":p")

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
      stopOnEntry = false,
    })

    local source = session:get_or_create_source({ path = script_path })
    local cleanup_called = false
    local hook_fired = false

    source:onBreakpoint(function(bp)
      hook_fired = true
      return function()
        cleanup_called = true
      end
    end)

    local bp = debugger:add_breakpoint({ path = script_path }, 6)

    vim.wait(1000, function() return hook_fired end)
    assert.is_true(hook_fired, "Hook should have fired")
    assert.is_false(cleanup_called, "Cleanup should not have fired yet")

    debugger:remove_breakpoint(bp)

    vim.wait(1000, function() return cleanup_called end)
    assert.is_true(cleanup_called, "Cleanup should have fired")

    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    session:dispose()
    debugger:dispose()

    return true
  end)
end)
