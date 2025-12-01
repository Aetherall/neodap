-- Tests for SourceBinding frame hooks
-- Tests: source_binding:onFrame, source_binding:onTopFrame, source_binding:onActiveFrame

local neostate = require("neostate")
local sdk = require("neodap.sdk")

neostate.setup({
  debug_context = false,
  trace = false,
})

-- Helper for tests that need coroutines
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

describe("SourceBinding Frame Hooks", function()
  local script_path = vim.fn.getcwd() .. "/tests/fixtures/stack_test.py"

  -- ==========================================================================
  -- SOURCEBINDING:ONFRAME
  -- ==========================================================================

  describe("SourceBinding:onFrame", function()
    verified_it("fires for frames in THIS session at this source", function()
      print("\n=== SOURCEBINDING:ONFRAME TEST ===")
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      -- Add breakpoint to stop execution
      local bp = debugger:add_breakpoint({ path = script_path }, 10)

      local frames_received = {}

      -- Start session
      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Fetch frames when thread stops
      session:onThread(function(thread)
        thread:onStopped(function()
          neostate.void(function()
            thread:stack()
          end)()
        end)
      end)

      -- Wait for session to stop
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)
      assert.are.equal("stopped", session.state:get())

      -- Get source binding for this session
      local source_binding = nil
      vim.wait(3000, function()
        for sb in session:source_bindings():iter() do
          if sb.source.correlation_key == script_path then
            source_binding = sb
            return true
          end
        end
        return false
      end)

      assert.is_not_nil(source_binding, "Should have source binding")
      print(string.format("  Found SourceBinding for: %s", source_binding.source.correlation_key))

      -- Hook into source binding's frames
      source_binding:onFrame(function(frame)
        table.insert(frames_received, frame)
        print(string.format("  Frame received: %s line %d", frame.name or "unknown", frame.line or 0))
        return function()
          print("  Frame cleanup called")
        end
      end)

      -- Wait for frames to be received
      vim.wait(2000, function()
        return #frames_received > 0
      end)

      print(string.format("  Frames received: %d", #frames_received))
      assert.is_true(#frames_received > 0, "Should have received at least 1 frame")

      -- Verify all frames are from this session
      for _, frame in ipairs(frames_received) do
        assert.are.equal(session.id, frame.stack.thread.session.id, "Frame should be from this session")
      end

      -- Cleanup
      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("does NOT receive frames from other sessions", function()
      print("\n=== SOURCEBINDING:ONFRAME SESSION ISOLATION TEST ===")
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      local bp = debugger:add_breakpoint({ path = script_path }, 10)

      local session1_frames = {}
      local session2_frames = {}

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
      })

      -- Wait for first session to stop
      vim.wait(10000, function()
        return session1.state:get() == "stopped"
      end)

      -- Get source binding for session1
      local source_binding1 = nil
      vim.wait(3000, function()
        for sb in session1:source_bindings():iter() do
          if sb.source.correlation_key == script_path then
            source_binding1 = sb
            return true
          end
        end
        return false
      end)

      assert.is_not_nil(source_binding1, "Session1 should have source binding")

      source_binding1:onFrame(function(frame)
        table.insert(session1_frames, frame)
        print(string.format("  Session1 frame: %s", frame.name or "unknown"))
        return function() end
      end)

      -- Wait for session1 frames
      vim.wait(2000, function()
        return #session1_frames > 0
      end)

      print(string.format("  Session1 frames after first session: %d", #session1_frames))
      local session1_frame_count = #session1_frames

      -- Start second session
      local session2 = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for second session to stop
      vim.wait(10000, function()
        return session2.state:get() == "stopped"
      end)

      -- Get source binding for session2
      local source_binding2 = nil
      vim.wait(3000, function()
        for sb in session2:source_bindings():iter() do
          if sb.source.correlation_key == script_path then
            source_binding2 = sb
            return true
          end
        end
        return false
      end)

      assert.is_not_nil(source_binding2, "Session2 should have source binding")

      source_binding2:onFrame(function(frame)
        table.insert(session2_frames, frame)
        print(string.format("  Session2 frame: %s", frame.name or "unknown"))
        return function() end
      end)

      -- Wait for session2 frames
      vim.wait(2000, function()
        return #session2_frames > 0
      end)

      print(string.format("  Session1 frames after second session: %d", #session1_frames))
      print(string.format("  Session2 frames: %d", #session2_frames))

      -- Session1's source_binding should NOT have received session2's frames
      assert.are.equal(session1_frame_count, #session1_frames,
        "Session1 source_binding should not receive session2 frames")

      -- Session2 should have its own frames
      assert.is_true(#session2_frames > 0, "Session2 should have frames")

      -- Verify frame session ownership
      for _, frame in ipairs(session1_frames) do
        assert.are.equal(session1.id, frame.stack.thread.session.id)
      end
      for _, frame in ipairs(session2_frames) do
        assert.are.equal(session2.id, frame.stack.thread.session.id)
      end

      -- Cleanup
      session1:disconnect(true)
      session2:disconnect(true)
      vim.wait(2000, function()
        return session1.state:get() == "terminated" and session2.state:get() == "terminated"
      end)
      debugger:dispose()

      return true
    end)
  end)

  -- ==========================================================================
  -- SOURCEBINDING:ONTOPFRAME
  -- ==========================================================================

  describe("SourceBinding:onTopFrame", function()
    verified_it("fires only for top frames (index 0) in THIS session", function()
      print("\n=== SOURCEBINDING:ONTOPFRAME TEST ===")
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      local bp = debugger:add_breakpoint({ path = script_path }, 10)

      local top_frames_received = {}

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Fetch frames when thread stops
      session:onThread(function(thread)
        thread:onStopped(function()
          neostate.void(function()
            thread:stack()
          end)()
        end)
      end)

      -- Wait for session to stop
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Get source binding
      local source_binding = nil
      vim.wait(3000, function()
        for sb in session:source_bindings():iter() do
          if sb.source.correlation_key == script_path then
            source_binding = sb
            return true
          end
        end
        return false
      end)

      assert.is_not_nil(source_binding, "Should have source binding")

      source_binding:onTopFrame(function(frame)
        table.insert(top_frames_received, frame)
        print(string.format("  Top frame received: %s (index %d)", frame.name or "unknown", frame.index:get()))
        return function() end
      end)

      -- Wait for top frames
      vim.wait(2000, function()
        return #top_frames_received > 0
      end)

      print(string.format("  Top frames received: %d", #top_frames_received))
      assert.is_true(#top_frames_received > 0, "Should have received top frames")

      -- Verify all are index 0
      for _, frame in ipairs(top_frames_received) do
        assert.are.equal(0, frame.index:get(), "Top frame should have index 0")
        assert.are.equal(session.id, frame.stack.thread.session.id, "Frame should be from this session")
      end

      -- Cleanup
      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)

  -- ==========================================================================
  -- SOURCEBINDING:ONACTIVEFRAME
  -- ==========================================================================

  describe("SourceBinding:onActiveFrame", function()
    verified_it("fires only for active (current) frames in THIS session", function()
      print("\n=== SOURCEBINDING:ONACTIVEFRAME TEST ===")
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      local bp = debugger:add_breakpoint({ path = script_path }, 10)

      local active_frames_received = {}

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Fetch frames when thread stops
      session:onThread(function(thread)
        thread:onStopped(function()
          neostate.void(function()
            thread:stack()
          end)()
        end)
      end)

      -- Wait for session to stop
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Get source binding
      local source_binding = nil
      vim.wait(3000, function()
        for sb in session:source_bindings():iter() do
          if sb.source.correlation_key == script_path then
            source_binding = sb
            return true
          end
        end
        return false
      end)

      assert.is_not_nil(source_binding, "Should have source binding")

      source_binding:onActiveFrame(function(frame)
        table.insert(active_frames_received, frame)
        print(string.format("  Active frame received: %s (is_current=%s)",
          frame.name or "unknown", tostring(frame._is_current:get())))
        return function()
          print("  Active frame cleanup called")
        end
      end)

      -- Wait for active frames
      vim.wait(2000, function()
        return #active_frames_received > 0
      end)

      print(string.format("  Active frames received: %d", #active_frames_received))
      assert.is_true(#active_frames_received > 0, "Should have received active frames")

      -- Verify all are current (not stale)
      for _, frame in ipairs(active_frames_received) do
        assert.is_true(frame._is_current:get(), "Active frame should be current")
        assert.are.equal(session.id, frame.stack.thread.session.id, "Frame should be from this session")
      end

      -- Cleanup
      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("cleanup runs when frame becomes inactive", function()
      print("\n=== SOURCEBINDING:ONACTIVEFRAME CLEANUP TEST ===")
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      local bp = debugger:add_breakpoint({ path = script_path }, 10)

      local hook_fired = false
      local cleanup_called = false

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Fetch frames when thread stops
      session:onThread(function(thread)
        thread:onStopped(function()
          neostate.void(function()
            thread:stack()
          end)()
        end)
      end)

      -- Wait for session to stop
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Get source binding
      local source_binding = nil
      vim.wait(3000, function()
        for sb in session:source_bindings():iter() do
          if sb.source.correlation_key == script_path then
            source_binding = sb
            return true
          end
        end
        return false
      end)

      assert.is_not_nil(source_binding, "Should have source binding")

      source_binding:onActiveFrame(function(frame)
        hook_fired = true
        return function()
          cleanup_called = true
          print("  Cleanup called!")
        end
      end)

      -- Wait for hook to fire
      vim.wait(2000, function()
        return hook_fired
      end)

      assert.is_true(hook_fired, "Hook should have fired")
      assert.is_false(cleanup_called, "Cleanup should not have fired yet")

      -- Continue execution to invalidate stack
      local thread = nil
      for t in session:threads():iter() do
        thread = t
        break
      end
      assert.is_not_nil(thread, "Should have a thread")
      session:continue(thread.id)

      -- Wait for cleanup
      vim.wait(2000, function()
        return cleanup_called
      end)

      print(string.format("  Cleanup called: %s", tostring(cleanup_called)))
      assert.is_true(cleanup_called, "Cleanup should have been called when frame became inactive")

      -- Cleanup
      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)
end)
