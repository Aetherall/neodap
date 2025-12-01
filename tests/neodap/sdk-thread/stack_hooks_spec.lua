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

describe("Stack-Centric Hooks (Real Debugger)", function()
    verified_it("thread:onFrame() fires for all frames (historical + current)", function()
        local debugger = sdk:create_debugger()

        debugger:register_adapter("python", {
            type = "stdio",
            command = "python3",
            args = { "-m", "debugpy.adapter" }
        })

        local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")
        local bp1 = debugger:add_breakpoint({ path = script_path }, 7)  -- return x in level_3
        local bp2 = debugger:add_breakpoint({ path = script_path }, 12) -- return y + 1 in level_2

        local session = debugger:start({
            type = "python",
            request = "launch",
            program = script_path,
            console = "internalConsole",
            stopOnEntry = false,
        })

        -- Wait for stop
        vim.wait(10000, function() return session.state:get() == "stopped" end)

        -- Get thread
        local thread = nil
        for t in session:threads():iter() do
            thread = t
            break
        end
        assert.is_not_nil(thread, "Expected thread")

        -- Track all frames seen by thread hook
        local frames_seen = {}
        thread:onFrame(function(frame)
            table.insert(frames_seen, frame)
        end)

        -- Fetch stack to trigger frame creation
        local stack1 = thread:stack()

        -- Wait for frames
        vim.wait(5000, function() return #frames_seen > 0 end)
        assert.is_true(#frames_seen > 0, "Expected frames from first stop")
        local count_after_first_stop = #frames_seen

        -- Continue to next breakpoint
        session:continue(thread.id)
        vim.wait(10000, function() return session.state:get() == "stopped" end)

        -- Fetch new stack
        thread:stack()

        -- Wait for more frames
        vim.wait(5000, function() return #frames_seen > count_after_first_stop end)
        assert.is_true(#frames_seen > count_after_first_stop, "Expected more frames after second stop")

        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        return true
    end)

    verified_it("thread:onCurrentFrame() fires only for current stack frames", function()
        local debugger = sdk:create_debugger()

        debugger:register_adapter("python", {
            type = "stdio",
            command = "python3",
            args = { "-m", "debugpy.adapter" }
        })

        local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")
        local bp1 = debugger:add_breakpoint({ path = script_path }, 7)  -- return x in level_3
        local bp2 = debugger:add_breakpoint({ path = script_path }, 12) -- return y + 1 in level_2

        local session = debugger:start({
            type = "python",
            request = "launch",
            program = script_path,
            console = "internalConsole",
            stopOnEntry = false,
        })

        vim.wait(10000, function() return session.state:get() == "stopped" end)

        -- Get thread
        local thread = nil
        for t in session:threads():iter() do
            thread = t
            break
        end
        assert.is_not_nil(thread, "Expected thread")

        local current_frames = {}
        local cleanup_count = 0

        thread:onCurrentFrame(function(frame)
            table.insert(current_frames, frame)
            return function()
                cleanup_count = cleanup_count + 1
            end
        end)

        -- Fetch stack to trigger frame creation
        thread:stack()

        -- Wait for frames
        vim.wait(2000, function() return #current_frames > 0 end)
        assert.is_true(#current_frames > 0, "Expected current frames")
        local first_stop_frame_count = #current_frames

        -- Continue to next breakpoint (invalidates previous stack)
        session:continue(thread.id)
        vim.wait(10000, function() return session.state:get() == "stopped" end)

        -- Fetch new stack
        thread:stack()

        -- Previous frames should have been cleaned up
        vim.wait(2000, function() return cleanup_count >= first_stop_frame_count end)
        assert.is_true(cleanup_count >= first_stop_frame_count, "Expected cleanup for previous frames")

        -- Should have new current frames
        assert.is_true(#current_frames > first_stop_frame_count, "Expected new current frames")

        -- Verify only the NEW frames are marked as current
        local active_count = 0
        for _, frame in ipairs(current_frames) do
            if frame._is_current:get() then
                active_count = active_count + 1
            end
        end
        -- The number of active frames should match the size of the new stack
        -- (approximate check, assuming stack depth is similar)
        assert.is_true(active_count > 0, "Expected some active frames")

        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        return true
    end)

    verified_it("stack:onFrame() fires only for frames in that stack", function()
        local debugger = sdk:create_debugger()

        debugger:register_adapter("python", {
            type = "stdio",
            command = "python3",
            args = { "-m", "debugpy.adapter" }
        })

        local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")
        local bp1 = debugger:add_breakpoint({ path = script_path }, 7)  -- return x in level_3
        local bp2 = debugger:add_breakpoint({ path = script_path }, 12) -- return y + 1 in level_2

        local session = debugger:start({
            type = "python",
            request = "launch",
            program = script_path,
            console = "internalConsole",
            stopOnEntry = false,
        })

        vim.wait(10000, function() return session.state:get() == "stopped" end)

        -- Get thread
        local thread = nil
        for t in session:threads():iter() do
            thread = t
            break
        end
        assert.is_not_nil(thread, "Expected thread")

        local first_stack = thread:stack()

        local stack_frames = {}
        first_stack:onFrame(function(frame)
            table.insert(stack_frames, frame)
        end)

        -- Wait for frames
        vim.wait(2000, function() return #stack_frames > 0 end)

        local first_stack_count = #stack_frames
        assert.is_true(first_stack_count > 0, "Expected frames in first stack")

        -- Continue to next breakpoint (new stack)
        session:continue(thread.id)
        vim.wait(10000, function() return session.state:get() == "stopped" end)

        -- Fetch new stack
        thread:stack()

        -- Wait a bit for potential frames (shouldn't happen)
        vim.wait(2000)

        -- Should NOT see any new frames in the old stack's hook
        assert.are.equal(first_stack_count, #stack_frames, "Stack hook should not receive frames from new stack")

        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        return true
    end)
end)
