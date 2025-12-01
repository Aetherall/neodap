local neostate = require("neostate")
-- neostate.setup({ trace = true })
local sdk = require("neodap.sdk")
local uri = require("neodap.sdk.uri")

-- Inline verified_it helper
local function verified_it(name, fn, timeout_ms)
  timeout_ms = timeout_ms or 60000

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

describe("URI Resolution Complex Scenarios (Real Debuggers)", function()

    verified_it("should resolve across multiple concurrent sessions", function()
        print("\n=== MULTI-SESSION TEST ===")
        local debugger = sdk:create_debugger()

        debugger:register_adapter("python", {
            type = "stdio",
            command = "python3",
            args = { "-m", "debugpy.adapter" }
        })

        local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")

        -- Add breakpoint
        debugger:add_breakpoint({ path = script_path }, 7)

        -- Start TWO sessions concurrently
        print("  Starting session 1...")
        local session1 = debugger:start({
            type = "python",
            request = "launch",
            program = script_path,
            console = "internalConsole",
        })
        print("  Session 1 ID: " .. session1.id)

        print("  Starting session 2...")
        local session2 = debugger:start({
            type = "python",
            request = "launch",
            program = script_path,
            console = "internalConsole",
        })
        print("  Session 2 ID: " .. session2.id)

        -- Wait for both to stop
        vim.wait(15000, function()
            return session1.state:get() == "stopped" and session2.state:get() == "stopped"
        end)
        assert.are.equal("stopped", session1.state:get(), "Session 1 should be stopped")
        assert.are.equal("stopped", session2.state:get(), "Session 2 should be stopped")

        -- Populate frames in both sessions
        for t in session1:threads():iter() do
            t:stack()
            break
        end
        for t in session2:threads():iter() do
            t:stack()
            break
        end

        -- Test: dap:frame[0] should return ALL top frames from BOTH sessions
        print("  Resolving: dap:frame[0] (global)")
        local all_top_frames = uri.resolve(debugger, "dap:frame[0]")
        local top_frame_count = 0
        local session_ids_seen = {}
        for frame in all_top_frames:iter() do
            top_frame_count = top_frame_count + 1
            local sid = frame.stack.thread.session.id
            session_ids_seen[sid] = true
            print("    Top frame: " .. frame.name .. " (session: " .. sid .. ")")
        end

        print("  Total top frames globally: " .. top_frame_count)
        assert.is_true(top_frame_count >= 2, "Should have at least 2 top frames (one per session)")
        assert.is_true(session_ids_seen[session1.id], "Should have top frame from session 1")
        assert.is_true(session_ids_seen[session2.id], "Should have top frame from session 2")

        -- Test: dap:session:<id>/frame[0] should return only ONE session's top frame
        print("  Resolving: dap:session:" .. session1.id .. "/frame[0]")
        local session1_top = uri.resolve(debugger, "dap:session:" .. session1.id .. "/frame[0]")
        local s1_count = 0
        for frame in session1_top:iter() do
            s1_count = s1_count + 1
            assert.are.equal(session1.id, frame.stack.thread.session.id, "Frame should be from session 1")
        end
        print("  Session 1 top frames: " .. s1_count)
        assert.are.equal(1, s1_count, "Should have exactly 1 top frame for session 1")

        -- Cleanup
        session1:disconnect(true)
        session2:disconnect(true)
        vim.wait(3000, function()
            return session1.state:get() == "terminated" and session2.state:get() == "terminated"
        end)
        session1:dispose()
        session2:dispose()
        debugger:dispose()

        return true
    end, 60000)

    verified_it("should resolve frame by index within a stack", function()
        print("\n=== FRAME INDEX RESOLUTION TEST ===")
        local debugger = sdk:create_debugger()

        debugger:register_adapter("python", {
            type = "stdio",
            command = "python3",
            args = { "-m", "debugpy.adapter" }
        })

        -- Use stack_test.py which creates a deep call stack
        local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")

        -- Breakpoint at level_3 (deepest function)
        debugger:add_breakpoint({ path = script_path }, 7)

        local session = debugger:start({
            type = "python",
            request = "launch",
            program = script_path,
            console = "internalConsole",
        })
        print("  Session ID: " .. session.id)

        vim.wait(10000, function()
            return session.state:get() == "stopped"
        end)
        assert.are.equal("stopped", session.state:get())

        -- Get thread and stack
        local thread = nil
        for t in session:threads():iter() do
            thread = t
            break
        end
        assert.is_not_nil(thread)
        local stack = thread:stack()
        assert.is_not_nil(stack)

        -- Count all frames
        local all_frames = 0
        for _ in stack:frames():iter() do
            all_frames = all_frames + 1
        end
        print("  Total frames in stack: " .. all_frames)

        -- Test: frame[0] in this session
        print("  Resolving: dap:session:" .. session.id .. "/frame[0]")
        local top_frames = uri.resolve(debugger, "dap:session:" .. session.id .. "/frame[0]")
        local top_count = 0
        for frame in top_frames:iter() do
            top_count = top_count + 1
            print("    Frame[0]: " .. frame.name .. " (index=" .. frame.index:get() .. ")")
            assert.are.equal(0, frame.index:get(), "Top frame should have index 0")
        end
        print("  Top frames count: " .. top_count)
        assert.is_true(top_count >= 1, "Should have at least one top frame")

        -- Test: frame[1] should get second frame
        print("  Resolving: dap:session:" .. session.id .. "/frame[1]")
        local second_frames = uri.resolve(debugger, "dap:session:" .. session.id .. "/frame[1]")
        local second_count = 0
        for frame in second_frames:iter() do
            second_count = second_count + 1
            print("    Frame[1]: " .. frame.name .. " (index=" .. frame.index:get() .. ")")
            assert.are.equal(1, frame.index:get(), "Second frame should have index 1")
        end
        print("  Second frames count: " .. second_count)

        -- Cleanup
        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        return true
    end)

    verified_it("should resolve same variable name across multiple scopes", function()
        print("\n=== SAME VARIABLE ACROSS SCOPES TEST ===")
        local debugger = sdk:create_debugger()

        debugger:register_adapter("python", {
            type = "stdio",
            command = "python3",
            args = { "-m", "debugpy.adapter" }
        })

        local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")

        -- Breakpoint at level_3 where we have x in multiple frames
        debugger:add_breakpoint({ path = script_path }, 7)

        local session = debugger:start({
            type = "python",
            request = "launch",
            program = script_path,
            console = "internalConsole",
        })

        vim.wait(10000, function()
            return session.state:get() == "stopped"
        end)

        local thread = nil
        for t in session:threads():iter() do
            thread = t
            break
        end
        local stack = thread:stack()

        -- Get frames
        local frames = {}
        for frame in stack:frames():iter() do
            table.insert(frames, frame)
            print("  Frame " .. frame.index:get() .. ": " .. frame.name)
        end

        -- Load scopes for multiple frames
        print("  Loading scopes for frames...")
        local scopes_loaded = 0
        for i, frame in ipairs(frames) do
            if i <= 3 then  -- Load first 3 frames' scopes
                local scopes = frame:scopes()
                if scopes then
                    for scope in scopes:iter() do
                        print("    Frame " .. frame.name .. " has scope: " .. scope.name)
                        -- Load variables
                        local vars = scope:variables()
                        if vars then
                            for v in vars:iter() do
                                print("      Variable: " .. v.name .. " = " .. v.value:get())
                            end
                        end
                    end
                    scopes_loaded = scopes_loaded + 1
                end
            end
        end
        print("  Loaded scopes for " .. scopes_loaded .. " frames")

        -- Test: Query all variables named 'x' globally
        -- First check how many 'x' variables exist
        local x_count = 0
        for v in debugger.variables:iter() do
            if v.name == "x" then
                x_count = x_count + 1
                print("    Found 'x' in scope: " .. (v.scope_name or "unknown"))
            end
        end
        print("  Total 'x' variables in debugger.variables: " .. x_count)

        -- Test filtering by evaluate_name
        print("  Resolving variables by evaluate_name index...")
        local x_var = debugger.variables:get_one("by_evaluate_name", "x")
        if x_var then
            print("    Found variable with evaluateName='x': " .. x_var.value:get())
        end

        -- Cleanup
        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        return true
    end)

    verified_it("should handle scoped resolution with thread hierarchy", function()
        print("\n=== THREAD-SCOPED RESOLUTION TEST ===")
        local debugger = sdk:create_debugger()

        debugger:register_adapter("python", {
            type = "stdio",
            command = "python3",
            args = { "-m", "debugpy.adapter" }
        })

        local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")

        debugger:add_breakpoint({ path = script_path }, 7)

        local session = debugger:start({
            type = "python",
            request = "launch",
            program = script_path,
            console = "internalConsole",
        })

        vim.wait(10000, function()
            return session.state:get() == "stopped"
        end)

        -- Get thread
        local thread = nil
        local thread_id = nil
        for t in session:threads():iter() do
            thread = t
            thread_id = t.id
            break
        end
        assert.is_not_nil(thread)
        print("  Thread ID: " .. thread_id)

        local stack = thread:stack()
        assert.is_not_nil(stack)

        -- Test: Resolve thread by ID
        local thread_uri = "dap:session:" .. session.id .. "/thread:" .. thread_id
        print("  Resolving: " .. thread_uri)
        local threads = uri.resolve(debugger, thread_uri)
        local resolved_thread = nil
        for t in threads:iter() do
            resolved_thread = t
            print("    Found thread: " .. t.id)
        end
        assert.is_not_nil(resolved_thread)
        assert.are.equal(thread_id, resolved_thread.id)

        -- Test: frame[0] scoped to specific thread
        local scoped_uri = "dap:session:" .. session.id .. "/thread:" .. thread_id .. "/frame[0]"
        print("  Resolving: " .. scoped_uri)
        local scoped_frames = uri.resolve(debugger, scoped_uri)
        local scoped_count = 0
        for frame in scoped_frames:iter() do
            scoped_count = scoped_count + 1
            print("    Thread-scoped top frame: " .. frame.name)
            -- Verify frame belongs to correct thread
            assert.are.equal(thread_id, frame.stack.thread.id)
        end
        print("  Thread-scoped top frame count: " .. scoped_count)
        assert.is_true(scoped_count >= 1)

        -- Cleanup
        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        return true
    end)

    verified_it("should resolve bindings across sessions for same breakpoint", function()
        print("\n=== BREAKPOINT BINDINGS ACROSS SESSIONS TEST ===")
        local debugger = sdk:create_debugger()

        debugger:register_adapter("python", {
            type = "stdio",
            command = "python3",
            args = { "-m", "debugpy.adapter" }
        })

        local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")

        -- Create ONE global breakpoint
        local breakpoint = debugger:add_breakpoint({ path = script_path }, 7)
        print("  Breakpoint ID: " .. breakpoint.id)

        -- Start TWO sessions - both will bind to the same breakpoint
        local session1 = debugger:start({
            type = "python",
            request = "launch",
            program = script_path,
            console = "internalConsole",
        })
        print("  Session 1 ID: " .. session1.id)

        local session2 = debugger:start({
            type = "python",
            request = "launch",
            program = script_path,
            console = "internalConsole",
        })
        print("  Session 2 ID: " .. session2.id)

        vim.wait(15000, function()
            return session1.state:get() == "stopped" and session2.state:get() == "stopped"
        end)

        -- Test: Query all bindings for this breakpoint
        print("  Resolving bindings for breakpoint: " .. breakpoint.id)
        local binding_count = 0
        local session_ids = {}
        for binding in breakpoint.bindings:iter() do
            binding_count = binding_count + 1
            session_ids[binding.session.id] = true
            print("    Binding in session: " .. binding.session.id .. " (verified=" .. tostring(binding.verified:get()) .. ")")
        end
        print("  Total bindings: " .. binding_count)
        assert.are.equal(2, binding_count, "Should have 2 bindings (one per session)")
        assert.is_true(session_ids[session1.id], "Should have binding in session 1")
        assert.is_true(session_ids[session2.id], "Should have binding in session 2")

        -- Test: Resolve binding in specific session
        local binding_uri = "dap:session:" .. session1.id .. "/binding:" .. breakpoint.id
        print("  Resolving: " .. binding_uri)
        local bindings = uri.resolve(debugger, binding_uri)
        local resolved_count = 0
        for b in bindings:iter() do
            resolved_count = resolved_count + 1
            assert.are.equal(session1.id, b.session.id)
            print("    Found binding for session: " .. b.session.id)
        end
        assert.are.equal(1, resolved_count, "Should find exactly 1 binding for session 1")

        -- Cleanup
        session1:disconnect(true)
        session2:disconnect(true)
        vim.wait(3000, function()
            return session1.state:get() == "terminated" and session2.state:get() == "terminated"
        end)
        session1:dispose()
        session2:dispose()
        debugger:dispose()

        return true
    end, 60000)

    verified_it("should maintain reactive frame[0] across steps", function()
        print("\n=== REACTIVE FRAME[0] TEST ===")
        local debugger = sdk:create_debugger()

        debugger:register_adapter("python", {
            type = "stdio",
            command = "python3",
            args = { "-m", "debugpy.adapter" }
        })

        local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")

        -- Set breakpoints at two different locations
        debugger:add_breakpoint({ path = script_path }, 7)   -- level_3: return x
        debugger:add_breakpoint({ path = script_path }, 12)  -- level_2: return y + 1

        local session = debugger:start({
            type = "python",
            request = "launch",
            program = script_path,
            console = "internalConsole",
        })
        print("  Session ID: " .. session.id)

        -- Wait for first stop (at level_3)
        vim.wait(10000, function()
            return session.state:get() == "stopped"
        end)

        -- Get thread and fetch stack
        local thread = nil
        for t in session:threads():iter() do
            thread = t
            break
        end
        local stack1 = thread:stack()
        local top_frame1 = stack1:top()
        print("  First stop - top frame: " .. top_frame1.name .. " (line " .. top_frame1.line .. ")")

        -- Resolve stack[0]/frame[0] and store the collection (should be reactive)
        -- stack[0] scopes to latest stack, frame[0] filters to top frame
        local frame_uri = "dap:session:" .. session.id .. "/thread:" .. thread.id .. "/stack[0]/frame[0]"
        print("  Resolving: " .. frame_uri)
        local top_frames = uri.resolve(debugger, frame_uri)

        -- Verify initial state
        local initial_count = 0
        local initial_frame = nil
        for f in top_frames:iter() do
            initial_count = initial_count + 1
            initial_frame = f
            print("    frame[0]: " .. f.name .. " (index=" .. tostring(f.index:get()) .. ", stack=" .. f.stack.id .. ")")
        end
        print("  Initial frame[0] count: " .. initial_count)
        if initial_frame then
            print("  Initial frame[0] name: " .. initial_frame.name)
        end
        assert.are.equal(1, initial_count, "Should have exactly 1 top frame initially")
        assert.are.equal("level_3", initial_frame.name, "Initial top frame should be level_3")

        -- Debug: Track events on frame[0] view
        local added_frames = {}
        local removed_frames = {}
        top_frames:on_added(function(f)
            print("    [EVENT] frame ADDED: " .. f.name)
            table.insert(added_frames, f.name)
        end)
        top_frames:on_removed(function(f)
            print("    [EVENT] frame REMOVED: " .. f.name)
            table.insert(removed_frames, f.name)
        end)

        -- Continue to hit second breakpoint
        print("  Continuing...")
        session:continue()

        -- Wait for second stop
        vim.wait(10000, function()
            return session.state:get() == "stopped"
        end)

        -- Fetch new stack to populate frames
        local stack2 = thread:stack()
        local top_frame2 = stack2:top()
        print("  Second stop - top frame: " .. top_frame2.name .. " (line " .. top_frame2.line .. ")")

        -- The SAME collection should now reflect the new top frame
        -- (because stack[0] now points to the new stack via follow reactivity)
        local new_count = 0
        local new_frame = nil
        for f in top_frames:iter() do
            new_count = new_count + 1
            new_frame = f
            print("    frame[0] now: " .. f.name .. " (is_current=" .. tostring(f:is_current()) .. ")")
        end
        print("  After step - frame[0] count: " .. new_count)
        assert.are.equal(1, new_count, "Should still have exactly 1 top frame")
        assert.are.equal("level_2", new_frame.name, "Top frame should now be level_2")
        assert.is_true(new_frame:is_current(), "New top frame should be current")

        -- Verify old frame is no longer in the collection (it's not current)
        assert.are_not.equal(initial_frame.id, new_frame.id, "Frame should have changed")

        -- Cleanup
        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        return true
    end)

    verified_it("should resolve stack by relative index (0 = latest)", function()
        print("\n=== STACK RELATIVE INDEX TEST ===")
        local debugger = sdk:create_debugger()

        debugger:register_adapter("python", {
            type = "stdio",
            command = "python3",
            args = { "-m", "debugpy.adapter" }
        })

        local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")

        -- Set breakpoints at two different locations
        debugger:add_breakpoint({ path = script_path }, 7)   -- level_3: return x
        debugger:add_breakpoint({ path = script_path }, 12)  -- level_2: return y + 1 (after level_3 returns)

        local session = debugger:start({
            type = "python",
            request = "launch",
            program = script_path,
            console = "internalConsole",
        })
        print("  Session ID: " .. session.id)

        -- Wait for first stop (at level_3)
        vim.wait(10000, function()
            return session.state:get() == "stopped"
        end)
        assert.are.equal("stopped", session.state:get())

        -- Get thread and first stack
        local thread = nil
        for t in session:threads():iter() do
            thread = t
            break
        end
        assert.is_not_nil(thread)

        local stack1 = thread:stack()
        assert.is_not_nil(stack1)
        print("  First stack ID: " .. stack1.id)
        print("  First stack sequence: " .. stack1.sequence)
        print("  First stack index: " .. stack1:get_index())
        assert.are.equal(0, stack1:get_index(), "First stack should have index 0")

        -- Verify stack[0] resolves to the first stack
        local stack_uri = "dap:session:" .. session.id .. "/thread:" .. thread.id .. "/stack[0]"
        print("  Resolving: " .. stack_uri)
        local resolved = uri.resolve_one(debugger, stack_uri)
        assert.is_not_nil(resolved)
        assert.are.equal(stack1.id, resolved.id, "stack[0] should be first stack")

        -- Continue to hit second breakpoint
        print("  Continuing...")
        session:continue()

        -- Wait for second stop
        vim.wait(10000, function()
            return session.state:get() == "stopped"
        end)
        assert.are.equal("stopped", session.state:get())

        -- Get second stack
        local stack2 = thread:stack()
        assert.is_not_nil(stack2)
        print("  Second stack ID: " .. stack2.id)
        print("  Second stack sequence: " .. stack2.sequence)
        print("  Second stack index: " .. stack2:get_index())

        -- Check stack1's index again (computed based on sequence)
        print("  Checking stack1 (ID: " .. stack1.id .. ") index after stack2 creation: " .. stack1:get_index())

        -- Verify indexes: stack2 should be 0 (latest), stack1 should be 1 (older)
        assert.are.equal(0, stack2:get_index(), "Second stack should have index 0 (latest)")
        assert.are.equal(1, stack1:get_index(), "First stack should now have index 1 (older)")

        -- Verify stack[0] now resolves to the second stack
        print("  Resolving: " .. stack_uri .. " (should be second stack now)")
        resolved = uri.resolve_one(debugger, stack_uri)
        assert.is_not_nil(resolved)
        assert.are.equal(stack2.id, resolved.id, "stack[0] should now be second stack")

        -- Verify stack[1] resolves to the first stack
        local stack1_uri = "dap:session:" .. session.id .. "/thread:" .. thread.id .. "/stack[1]"
        print("  Resolving: " .. stack1_uri)
        local resolved_old = uri.resolve_one(debugger, stack1_uri)
        assert.is_not_nil(resolved_old)
        assert.are.equal(stack1.id, resolved_old.id, "stack[1] should be first stack")

        -- Cleanup
        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        return true
    end)

    verified_it("should track variable value changes across steps via reactive URI", function()
        print("\n=== REACTIVE VARIABLE TRACKING TEST ===")
        local debugger = sdk:create_debugger()

        debugger:register_adapter("python", {
            type = "stdio",
            command = "python3",
            args = { "-m", "debugpy.adapter" }
        })

        local script_path = vim.fn.fnamemodify("tests/fixtures/counter_loop.py", ":p")

        -- Set breakpoint at counter += 1 (line 7)
        debugger:add_breakpoint({ path = script_path }, 7)

        local session = debugger:start({
            type = "python",
            request = "launch",
            program = script_path,
            console = "internalConsole",
        })
        print("  Session ID: " .. session.id)

        -- Wait for first stop
        vim.wait(10000, function()
            return session.state:get() == "stopped"
        end)
        assert.are.equal("stopped", session.state:get())
        print("  Stopped at breakpoint")

        -- Get thread
        local thread = nil
        for t in session:threads():iter() do
            thread = t
            break
        end
        assert.is_not_nil(thread)

        -- Fetch stack and scopes to populate variables
        local stack = thread:stack()
        local top_frame = stack:top()
        print("  Top frame: " .. top_frame.name .. " (line " .. top_frame.line .. ")")

        -- Load scopes and variables to populate the global collection
        local scopes = top_frame:scopes()
        local scope_count = 0
        for scope in scopes:iter() do
            scope_count = scope_count + 1
            local vars = scope:variables()
            local var_count = 0
            for v in vars:iter() do
                var_count = var_count + 1
            end
            print("    Scope '" .. scope.name .. "': " .. var_count .. " variables")
        end
        print("  Loaded " .. scope_count .. " scopes")

        -- Track all counter values we observe via the reactive latest() signal
        local observed_values = {}

        -- Use debugger:resolve() to get a reactive collection of the "counter" variable
        -- scoped to stack[0] (current stack) - this will reactively update across steps!
        local var_uri = "dap:session:" .. session.id .. "/stack[0]/variable:counter"
        print("  Resolving reactive URI: " .. var_uri)
        local counter_vars = debugger:resolve(var_uri)
        assert.is_not_nil(counter_vars, "Should resolve variable URI")

        -- Use latest() to get a Signal for the most recent counter variable
        -- This automatically updates when new variables are added to the collection
        local latest_counter = counter_vars:latest()
        print("  Created latest() signal for counter variable")

        -- Watch the latest counter's value - this demonstrates reactive composition:
        -- latest() Signal -> Variable -> value Signal
        local unsub = latest_counter:use(function(var)
            if var then
                local val = var.value:get()
                print("    [latest] counter = " .. tostring(val))
                table.insert(observed_values, val)
            end
        end)

        -- Initial value should be 0 (before first increment)
        print("  Initial observed values: " .. vim.inspect(observed_values))
        assert.is_true(#observed_values >= 1, "Should have at least one observed value")
        assert.are.equal("0", observed_values[1], "Initial counter should be 0")

        -- Continue through the loop 3 times (hitting breakpoint each iteration)
        for iteration = 1, 3 do
            print("  Continue (iteration " .. iteration .. ")...")
            session:continue()

            -- Wait for stop at breakpoint
            vim.wait(5000, function()
                return session.state:get() == "stopped"
            end)
            assert.are.equal("stopped", session.state:get())

            -- Fetch new stack to populate the frame
            local new_stack = thread:stack()
            local new_frame = new_stack:top()

            -- Load scopes and variables for new stack
            local step_scopes = new_frame:scopes()
            for scope in step_scopes:iter() do
                scope:variables()  -- Populates global variables collection
            end

            print("    Observed values so far: " .. vim.inspect(observed_values))
        end

        -- Unsubscribe
        unsub()

        -- Verify we tracked multiple values (counter incrementing)
        print("  Final observed values: " .. vim.inspect(observed_values))
        assert.is_true(#observed_values >= 3, "Should have observed multiple counter values")

        -- The values should show progression (0, 1, 2, 3, ...)
        local seen = {}
        for _, v in ipairs(observed_values) do
            seen[v] = true
        end
        print("  Unique values seen: " .. vim.inspect(vim.tbl_keys(seen)))

        -- Should have seen at least values 0, 1, 2
        assert.is_true(seen["0"], "Should have seen counter = 0")
        assert.is_true(seen["1"], "Should have seen counter = 1")
        assert.is_true(seen["2"], "Should have seen counter = 2")

        -- Cleanup
        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        print("  SUCCESS: Reactive URI tracked counter value changes across steps!")
        return true
    end)

end)
