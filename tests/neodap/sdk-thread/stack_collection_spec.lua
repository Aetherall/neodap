local neostate = require("neostate")
local sdk = require("neodap.sdk")
local async = require("plenary.async.tests")

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

describe("Stack Collection Integration (Real Debugger)", function()
    verified_it("should index frames by id and index using real Python debug session", function()
        local debugger = sdk:create_debugger()

        -- Configure debugpy adapter
        debugger:register_adapter("python", {
            type = "stdio",
            command = "python3",
            args = { "-m", "debugpy.adapter" }
        })

        local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")

        -- Add breakpoint using SDK
        local breakpoint = debugger:add_breakpoint(
            { path = script_path },
            7  -- line: return x in level_3
        )

        -- Start debug session with VSCode-style config
        -- SDK handles: adapter lookup, session creation, initialization, and launch
        local session = debugger:start({
            type = "python",
            request = "launch",
            program = script_path,
            console = "internalConsole",
        })

        -- Verify breakpoint was automatically bound to session
        local session_binding_count = 0
        for _ in session:bindings():iter() do
            session_binding_count = session_binding_count + 1
        end
        assert.are.equal(1, session_binding_count, "Breakpoint should be bound to session")

        local breakpoint_binding_count = 0
        for _ in breakpoint.bindings:iter() do
            breakpoint_binding_count = breakpoint_binding_count + 1
        end
        assert.are.equal(1, breakpoint_binding_count, "Breakpoint should reference the binding")

        -- Wait for session to reach stopped state (SDK manages this reactively)
        vim.wait(10000, function()
            return session.state:get() == "stopped"
        end)
        assert.are.equal("stopped", session.state:get(), "Session should be stopped at breakpoint")

        -- Get thread using SDK (threads are managed reactively)
        local thread_count = 0
        local thread = nil
        for t in session:threads():iter() do
            thread_count = thread_count + 1
            thread = t
        end
        assert.are.equal(1, thread_count, "Should have one thread")
        assert.is_not_nil(thread, "Should have found thread")
        assert.are.equal("stopped", thread.state:get(), "Thread should be stopped")

        -- Get stack using SDK
        local stack = thread:stack()
        assert.is_not_nil(stack, "Should have stack trace")

        -- Count frames
        local frame_count = 0
        for _ in stack:frames():iter() do
            frame_count = frame_count + 1
        end
        assert.is_true(frame_count >= 3, "Should have at least 3 frames (level_3, level_2, level_1)")

        -- Get actual frame IDs from real frames
        local real_frames = {}
        for frame in stack:frames():iter() do
            table.insert(real_frames, frame)
        end
        local frame0_id = real_frames[1].id
        local frame1_id = real_frames[2].id
        local frame2_id = real_frames[3].id

        -- Test index by id (using real frame IDs)
        local frame_by_id_0 = stack:frames():get_one("by_id", frame0_id)
        assert.is_not_nil(frame_by_id_0)
        assert.are.equal(frame0_id, frame_by_id_0.id)

        local frame_by_id_1 = stack:frames():get_one("by_id", frame1_id)
        assert.is_not_nil(frame_by_id_1)
        assert.are.equal(frame1_id, frame_by_id_1.id)

        -- Test index by position (0-based)
        local frame_at_0 = stack:frames():get_one("by_index", 0)
        assert.is_not_nil(frame_at_0)
        assert.are.equal(0, frame_at_0.index:get())
        assert.are.equal("level_3", frame_at_0.name)  -- Top of stack

        local frame_at_1 = stack:frames():get_one("by_index", 1)
        assert.is_not_nil(frame_at_1)
        assert.are.equal(1, frame_at_1.index:get())
        assert.are.equal("level_2", frame_at_1.name)

        local frame_at_2 = stack:frames():get_one("by_index", 2)
        assert.is_not_nil(frame_at_2)
        assert.are.equal(2, frame_at_2.index:get())
        assert.are.equal("level_1", frame_at_2.name)

        -- Test top() helper using SDK
        local top = stack:top()
        assert.is_not_nil(top)
        assert.are.equal(frame_at_0, top)
        assert.are.equal("level_3", top.name)

        -- Cleanup using SDK
        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        return true
    end)

    verified_it("should handle reactive index updates using real Python debug session", function()
        local debugger = sdk:create_debugger()

        -- Configure debugpy adapter
        debugger:register_adapter("python", {
            type = "stdio",
            command = "python3",
            args = { "-m", "debugpy.adapter" }
        })

        local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")

        -- Add breakpoint using SDK
        local breakpoint = debugger:add_breakpoint(
            { path = script_path },
            7
        )

        -- Start debug session with VSCode-style config
        local session = debugger:start({
            type = "python",
            request = "launch",
            program = script_path,
            console = "internalConsole",
        })

        -- Wait for stopped state using SDK reactive signals
        vim.wait(10000, function()
            return session.state:get() == "stopped"
        end)
        assert.are.equal("stopped", session.state:get())

        -- Get thread using SDK
        local thread = nil
        for t in session:threads():iter() do
            thread = t
            break
        end
        assert.is_not_nil(thread)

        -- Get stack using SDK
        local stack = thread:stack()
        assert.is_not_nil(stack)

        -- Count frames
        local frame_count = 0
        for _ in stack:frames():iter() do
            frame_count = frame_count + 1
        end
        assert.is_true(frame_count >= 2)

        -- Get first two frames
        local frame0 = stack:frames():get_one("by_index", 0)
        local frame1 = stack:frames():get_one("by_index", 1)
        assert.is_not_nil(frame0)
        assert.is_not_nil(frame1)

        local frame0_id = frame0.id
        local frame1_id = frame1.id

        -- Test reactive index updates (swap indices - simulating frame reordering)
        frame0.index:set(1)
        frame1.index:set(0)

        -- Verify indices swapped using Collection's reactive indexing
        local new_frame_at_0 = stack:frames():get_one("by_index", 0)
        local new_frame_at_1 = stack:frames():get_one("by_index", 1)
        assert.is_not_nil(new_frame_at_0)
        assert.is_not_nil(new_frame_at_1)
        assert.are.equal(frame1_id, new_frame_at_0.id)  -- frame1 moved to index 0
        assert.are.equal(frame0_id, new_frame_at_1.id)  -- frame0 moved to index 1

        -- Cleanup using SDK
        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        return true
    end)
end)
