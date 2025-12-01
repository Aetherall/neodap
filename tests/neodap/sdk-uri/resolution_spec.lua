local neostate = require("neostate")
local sdk = require("neodap.sdk")
local uri = require("neodap.sdk.uri")

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

describe("URI Resolution (Real Debugger)", function()
    verified_it("should resolve session by ID", function()
        print("\n=== URI RESOLUTION: SESSION TEST ===")
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

        print("  Session ID: " .. session.id)
        print("  Session URI: " .. session.uri)

        -- Wait for stopped state
        vim.wait(10000, function()
            return session.state:get() == "stopped"
        end)

        -- Test: resolve session by ID
        local session_uri = "dap:session:" .. session.id
        print("  Resolving: " .. session_uri)

        local sessions = uri.resolve(debugger, session_uri)
        assert.is_not_nil(sessions, "resolve() should return a collection")

        local count = 0
        local resolved_session = nil
        for s in sessions:iter() do
            count = count + 1
            resolved_session = s
        end

        print("  Found " .. count .. " session(s)")
        assert.are.equal(1, count, "Should find exactly one session")
        assert.are.equal(session.id, resolved_session.id, "Should be the same session")

        -- Test: resolve_one convenience
        local one = uri.resolve_one(debugger, session_uri)
        assert.is_not_nil(one)
        assert.are.equal(session.id, one.id)

        -- Cleanup
        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        return true
    end)

    verified_it("should resolve frames with index accessor [0]", function()
        print("\n=== URI RESOLUTION: FRAME[0] TEST ===")
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
        assert.are.equal("stopped", session.state:get())

        -- Get stack to populate frames
        local thread = nil
        for t in session:threads():iter() do
            thread = t
            break
        end
        assert.is_not_nil(thread)

        local stack = thread:stack()
        assert.is_not_nil(stack)

        -- Count frames first
        local frame_count = 0
        for _ in stack:frames():iter() do
            frame_count = frame_count + 1
        end
        print("  Total frames in stack: " .. frame_count)

        -- Test: resolve frame[0] in session (top frames)
        local frame_uri = "dap:session:" .. session.id .. "/frame[0]"
        print("  Resolving: " .. frame_uri)

        local frames = uri.resolve(debugger, frame_uri)
        assert.is_not_nil(frames, "resolve() should return a collection")

        local top_frame_count = 0
        local top_frame = nil
        for f in frames:iter() do
            top_frame_count = top_frame_count + 1
            top_frame = f
            print("    Found frame: " .. f.name .. " (index=" .. f.index:get() .. ")")
        end

        print("  Found " .. top_frame_count .. " top frame(s)")
        assert.is_true(top_frame_count >= 1, "Should find at least one top frame")
        assert.are.equal(0, top_frame.index:get(), "Top frame should have index 0")
        assert.are.equal("level_3", top_frame.name, "Top frame should be level_3")

        -- Cleanup
        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        return true
    end)

    verified_it("should resolve frame by exact ID", function()
        print("\n=== URI RESOLUTION: FRAME:ID TEST ===")
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

        -- Get a real frame ID
        local thread = nil
        for t in session:threads():iter() do
            thread = t
            break
        end
        local stack = thread:stack()
        local real_frame = stack:top()
        assert.is_not_nil(real_frame)

        local frame_id = real_frame.id
        print("  Real frame ID: " .. frame_id)
        print("  Real frame name: " .. real_frame.name)

        -- Test: resolve frame by exact ID
        local frame_uri = "dap:session:" .. session.id .. "/frame:" .. frame_id
        print("  Resolving: " .. frame_uri)

        local frame = uri.resolve_one(debugger, frame_uri)
        assert.is_not_nil(frame, "Should find frame by ID")
        assert.are.equal(frame_id, frame.id, "Should be the same frame")
        assert.are.equal(real_frame.name, frame.name, "Should have same name")

        print("  Resolved frame: " .. frame.name)

        -- Cleanup
        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        return true
    end)

    verified_it("should resolve global frame[0] across all sessions", function()
        print("\n=== URI RESOLUTION: GLOBAL FRAME[0] TEST ===")
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

        -- Populate frames
        local thread = nil
        for t in session:threads():iter() do
            thread = t
            break
        end
        local stack = thread:stack()
        assert.is_not_nil(stack)

        -- Test: resolve frame[0] globally (no session scope)
        local frame_uri = "dap:frame[0]"
        print("  Resolving: " .. frame_uri)

        local frames = uri.resolve(debugger, frame_uri)
        assert.is_not_nil(frames, "resolve() should return a collection")

        local top_frame_count = 0
        for f in frames:iter() do
            top_frame_count = top_frame_count + 1
            print("    Found global top frame: " .. f.name .. " in session " .. f.stack.thread.session.id)
        end

        print("  Found " .. top_frame_count .. " global top frame(s)")
        assert.is_true(top_frame_count >= 1, "Should find at least one top frame globally")

        -- Cleanup
        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        return true
    end)

    verified_it("should resolve breakpoint by ID", function()
        print("\n=== URI RESOLUTION: BREAKPOINT TEST ===")
        local debugger = sdk:create_debugger()

        debugger:register_adapter("python", {
            type = "stdio",
            command = "python3",
            args = { "-m", "debugpy.adapter" }
        })

        local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")

        local breakpoint = debugger:add_breakpoint({ path = script_path }, 7)
        print("  Breakpoint ID: " .. breakpoint.id)
        print("  Breakpoint URI: " .. breakpoint.uri)

        -- Test: resolve breakpoint by ID (before session even starts)
        local bp_uri = "dap:breakpoint:" .. breakpoint.id
        print("  Resolving: " .. bp_uri)

        local bps = uri.resolve(debugger, bp_uri)
        assert.is_not_nil(bps)

        local count = 0
        local resolved_bp = nil
        for b in bps:iter() do
            count = count + 1
            resolved_bp = b
        end

        print("  Found " .. count .. " breakpoint(s)")
        assert.are.equal(1, count, "Should find exactly one breakpoint")
        assert.are.equal(breakpoint.id, resolved_bp.id)
        assert.are.equal(7, resolved_bp.line)

        -- Cleanup
        debugger:dispose()

        return true
    end)

    verified_it("should resolve source by correlation key", function()
        print("\n=== URI RESOLUTION: SOURCE TEST ===")
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

        -- Get a source from a frame
        local thread = nil
        for t in session:threads():iter() do
            thread = t
            break
        end
        local stack = thread:stack()
        local frame = stack:top()
        assert.is_not_nil(frame.source)

        local source = frame.source
        print("  Source correlation_key: " .. source.correlation_key)
        print("  Source URI: " .. source:location_uri())

        -- Test: resolve source by file URI
        local source_uri = source:location_uri()
        print("  Resolving: " .. source_uri)

        local sources = uri.resolve(debugger, source_uri)
        assert.is_not_nil(sources)

        local count = 0
        local resolved_source = nil
        for s in sources:iter() do
            count = count + 1
            resolved_source = s
        end

        print("  Found " .. count .. " source(s)")
        assert.are.equal(1, count, "Should find exactly one source")
        assert.are.equal(source.correlation_key, resolved_source.correlation_key)

        -- Cleanup
        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        session:dispose()
        debugger:dispose()

        return true
    end)
end)
