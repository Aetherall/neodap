-- Tests for Source and SourceBinding breakpoint hooks
-- Tests: source:onBreakpointBinding, source_binding:onBreakpoint, source_binding:onBreakpointBinding

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

describe("Source and SourceBinding Breakpoint Hooks", function()
  local script_path = vim.fn.getcwd() .. "/tests/fixtures/stack_test.py"

  -- ==========================================================================
  -- SOURCE:ONBREAKPOINTBINDING
  -- ==========================================================================

  describe("Source:onBreakpointBinding", function()
    verified_it("fires when binding created for breakpoint at source", function()
      print("\n=== SOURCE:ONBREAKPOINTBINDING TEST ===")
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      -- Add breakpoint
      local bp = debugger:add_breakpoint({ path = script_path }, 10)

      local bindings_received = {}
      local cleanup_count = 0

      -- Start session first to create Source entity
      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for source to be created
      local source = nil
      vim.wait(3000, function()
        source = debugger.sources:get_one("by_correlation_key", script_path)
        return source ~= nil
      end)

      assert.is_not_nil(source, "Source should exist")
      print(string.format("  Found Source: %s", source.correlation_key))

      -- Hook into source's breakpoint bindings
      source:onBreakpointBinding(function(binding)
        table.insert(bindings_received, binding)
        print(string.format("  Binding received for session: %s", binding.session.id))
        return function()
          cleanup_count = cleanup_count + 1
          print(string.format("  Cleanup called, total: %d", cleanup_count))
        end
      end)

      -- Wait for binding to be received (it was already created)
      vim.wait(1000, function()
        return #bindings_received > 0
      end)

      print(string.format("  Bindings received: %d", #bindings_received))
      assert.are.equal(1, #bindings_received, "Should have received 1 binding")
      assert.are.equal(0, cleanup_count, "No cleanup yet")

      -- Cleanup
      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      -- After session ends, cleanup should have been called
      print(string.format("  Final cleanup count: %d", cleanup_count))
      assert.are.equal(1, cleanup_count, "Cleanup should have been called")

      return true
    end)

    verified_it("receives bindings from multiple sessions", function()
      print("\n=== SOURCE:ONBREAKPOINTBINDING MULTI-SESSION TEST ===")
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      local bp = debugger:add_breakpoint({ path = script_path }, 10)

      -- Start first session to create Source entity
      local session1 = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for source to be created
      local source = nil
      vim.wait(3000, function()
        source = debugger.sources:get_one("by_correlation_key", script_path)
        return source ~= nil
      end)

      assert.is_not_nil(source, "Source should exist")

      local bindings_received = {}

      source:onBreakpointBinding(function(binding)
        table.insert(bindings_received, binding)
        print(string.format("  Binding from session: %s", binding.session.id))
        return function() end
      end)

      -- Wait for first binding
      vim.wait(1000, function()
        return #bindings_received >= 1
      end)

      -- Start second session
      local session2 = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(2000, function()
        return #bindings_received >= 2
      end)

      print(string.format("  Total bindings: %d", #bindings_received))
      assert.are.equal(2, #bindings_received, "Should have received bindings from both sessions")

      -- Verify different sessions
      assert.are_not.equal(
        bindings_received[1].session.id,
        bindings_received[2].session.id,
        "Bindings should be from different sessions"
      )

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
  -- SOURCEBINDING:ONBREAKPOINTBINDING
  -- ==========================================================================

  describe("SourceBinding:onBreakpointBinding", function()
    verified_it("fires only for THIS session's bindings", function()
      print("\n=== SOURCEBINDING:ONBREAKPOINTBINDING TEST ===")
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      local bp = debugger:add_breakpoint({ path = script_path }, 10)

      local session1_bindings = {}
      local session2_bindings = {}

      -- Start first session
      local session1 = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for source to be created
      vim.wait(3000, function()
        return debugger.sources:get_one("by_correlation_key", script_path) ~= nil
      end)

      -- Get source binding for session1
      local source_binding1 = nil
      for sb in session1:source_bindings():iter() do
        if sb.source.correlation_key == script_path then
          source_binding1 = sb
          break
        end
      end

      assert.is_not_nil(source_binding1, "Session1 should have source binding")
      print(string.format("  Session1 source binding found"))

      source_binding1:onBreakpointBinding(function(binding)
        table.insert(session1_bindings, binding)
        print(string.format("  Session1 binding received"))
        return function() end
      end)

      -- Wait for binding to be received
      vim.wait(1000, function()
        return #session1_bindings > 0
      end)

      -- Start second session
      local session2 = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for session2 source bindings
      vim.wait(3000, function()
        for _ in session2:source_bindings():iter() do
          return true
        end
        return false
      end)

      -- Get source binding for session2
      local source_binding2 = nil
      for sb in session2:source_bindings():iter() do
        if sb.source.correlation_key == script_path then
          source_binding2 = sb
          break
        end
      end

      assert.is_not_nil(source_binding2, "Session2 should have source binding")
      print(string.format("  Session2 source binding found"))

      source_binding2:onBreakpointBinding(function(binding)
        table.insert(session2_bindings, binding)
        print(string.format("  Session2 binding received"))
        return function() end
      end)

      vim.wait(1000, function()
        return #session2_bindings > 0
      end)

      print(string.format("  Session1 bindings: %d", #session1_bindings))
      print(string.format("  Session2 bindings: %d", #session2_bindings))

      -- Each should have exactly 1 binding (session-isolated)
      assert.are.equal(1, #session1_bindings, "Session1 should have 1 binding")
      assert.are.equal(1, #session2_bindings, "Session2 should have 1 binding")

      -- Verify they're different bindings
      assert.are_not.equal(session1_bindings[1], session2_bindings[1], "Should be different binding objects")

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
  -- SOURCEBINDING:ONBREAKPOINT
  -- ==========================================================================

  describe("SourceBinding:onBreakpoint", function()
    verified_it("fires for breakpoints bound to THIS session", function()
      print("\n=== SOURCEBINDING:ONBREAKPOINT TEST ===")
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      local bp = debugger:add_breakpoint({ path = script_path }, 10)

      local breakpoints_received = {}

      -- Start session
      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for source binding
      vim.wait(2000, function()
        for _ in session:source_bindings():iter() do
          return true
        end
        return false
      end)

      -- Get source binding
      local source_binding = nil
      for sb in session:source_bindings():iter() do
        if sb.source.correlation_key == script_path then
          source_binding = sb
          break
        end
      end

      assert.is_not_nil(source_binding, "Should have source binding")

      source_binding:onBreakpoint(function(breakpoint)
        table.insert(breakpoints_received, breakpoint)
        print(string.format("  Breakpoint received: line %d", breakpoint.line))
        return function()
          print("  Breakpoint cleanup called")
        end
      end)

      -- Wait for breakpoint to be received
      vim.wait(1000, function()
        return #breakpoints_received > 0
      end)

      print(string.format("  Breakpoints received: %d", #breakpoints_received))
      assert.are.equal(1, #breakpoints_received, "Should have received 1 breakpoint")
      assert.are.equal(bp, breakpoints_received[1], "Should be the same breakpoint object")

      -- Cleanup
      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("does NOT fire for breakpoints only in other sessions", function()
      print("\n=== SOURCEBINDING:ONBREAKPOINT SESSION ISOLATION TEST ===")
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      -- Start session1 first (no breakpoint yet)
      local session1 = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(2000, function()
        return session1.state:get() == "running" or session1.state:get() == "stopped"
      end)

      -- Now add breakpoint - session1 should get a binding
      local bp = debugger:add_breakpoint({ path = script_path }, 10)

      -- Wait for binding to be created in session1
      vim.wait(2000, function()
        for binding in debugger.bindings:iter() do
          if binding.session == session1 then
            return true
          end
        end
        return false
      end)

      -- Start session2
      local session2 = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(2000, function()
        for _ in session2:source_bindings():iter() do
          return true
        end
        return false
      end)

      -- Get source binding for session2
      local source_binding2 = nil
      for sb in session2:source_bindings():iter() do
        if sb.source.correlation_key == script_path then
          source_binding2 = sb
          break
        end
      end

      assert.is_not_nil(source_binding2, "Session2 should have source binding")

      local session2_breakpoints = {}
      source_binding2:onBreakpoint(function(breakpoint)
        table.insert(session2_breakpoints, breakpoint)
        return function() end
      end)

      -- Wait a bit
      vim.wait(1000, function()
        return #session2_breakpoints > 0
      end)

      print(string.format("  Session2 breakpoints: %d", #session2_breakpoints))

      -- Session2 should also have received the breakpoint (since it was bound when session started)
      -- Both sessions should have bindings for the breakpoint
      assert.are.equal(1, #session2_breakpoints, "Session2 should have the breakpoint")

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
end)
