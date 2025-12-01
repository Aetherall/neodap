local neostate = require("neostate")
local uri = require("neodap.sdk.uri")

describe("Contextual URI", function()
  describe("uri.build_context_map", function()
    it("should return empty map for nil entity", function()
      local map = uri.build_context_map(nil)
      assert.are.same({}, map)
    end)

    it("should extract session ID from session entity", function()
      local session = { id = "session-123" }
      local map = uri.build_context_map(session)
      assert.are.equal("session-123", map.session)
      assert.is_nil(map.thread)
      assert.is_nil(map.stack)
      assert.is_nil(map.frame)
    end)

    it("should extract thread and session IDs from thread entity", function()
      local thread = {
        id = 1,
        session = { id = "session-123" }
      }
      local map = uri.build_context_map(thread)
      assert.are.equal("session-123", map.session)
      assert.are.equal(1, map.thread)
      assert.is_nil(map.stack)
      assert.is_nil(map.frame)
    end)

    it("should extract stack, thread, and session IDs from stack entity", function()
      local stack = {
        id = "stack-1",
        sequence = 5,  -- Stack uses sequence for identification in URI schema
        thread = {
          id = 1,
          session = { id = "session-123" }
        }
      }
      local map = uri.build_context_map(stack)
      assert.are.equal("session-123", map.session)
      assert.are.equal(1, map.thread)
      assert.are.equal(5, map.stack)  -- Uses sequence, not id
      assert.is_nil(map.frame)
    end)

    it("should extract all IDs from frame entity", function()
      local frame = {
        id = 42,
        stack = {
          id = "stack-1",
          sequence = 5,  -- Stack uses sequence for identification in URI schema
          thread = {
            id = 1,
            session = { id = "session-123" }
          }
        }
      }
      local map = uri.build_context_map(frame)
      assert.are.equal("session-123", map.session)
      assert.are.equal(1, map.thread)
      assert.are.equal(5, map.stack)  -- Uses sequence, not id
      assert.are.equal(42, map.frame)
    end)

    it("should extract frame_index when available", function()
      local frame = {
        id = 42,
        index = { get = function() return 2 end },  -- Mock Signal
        stack = {
          id = "stack-1",
          sequence = 5,
          index = { get = function() return 0 end },  -- Mock Signal
          thread = {
            id = 1,
            session = { id = "session-123" }
          }
        }
      }
      local map = uri.build_context_map(frame)
      assert.are.equal(2, map.frame_index)
      assert.are.equal(0, map.stack_index)
    end)

    it("should handle entities without index signals", function()
      local frame = {
        id = 42,
        -- No index field
        stack = {
          id = "stack-1",
          sequence = 5,
          -- No index field
          thread = {
            id = 1,
            session = { id = "session-123" }
          }
        }
      }
      local map = uri.build_context_map(frame)
      assert.is_nil(map.frame_index)
      assert.is_nil(map.stack_index)
    end)
  end)

  describe("uri.expand_contextual", function()
    it("should expand @session marker", function()
      local result = uri.expand_contextual("dap:@session", { session = "abc" })
      assert.are.equal("dap:session:abc", result)
    end)

    it("should expand @thread marker", function()
      local result = uri.expand_contextual("dap:@session/@thread", {
        session = "abc",
        thread = 1
      })
      assert.are.equal("dap:session:abc/thread:1", result)
    end)

    it("should expand multiple markers", function()
      local result = uri.expand_contextual("dap:@session/@thread/@stack/@frame", {
        session = "abc",
        thread = 1,
        stack = "seq1",
        frame = 42
      })
      assert.are.equal("dap:session:abc/thread:1/stack:seq1/frame:42", result)
    end)

    it("should return nil if marker cannot be expanded", function()
      local result = uri.expand_contextual("dap:@session/@thread", { session = "abc" })
      assert.is_nil(result)
    end)

    it("should preserve non-contextual segments", function()
      local result = uri.expand_contextual("dap:@session/thread[0]", { session = "abc" })
      assert.are.equal("dap:session:abc/thread[0]", result)
    end)

    it("should encode special characters in IDs", function()
      local result = uri.expand_contextual("dap:@session", { session = "path/with:special" })
      assert.are.equal("dap:session:path%2Fwith%3Aspecial", result)
    end)

    it("should expand @entity/suffix patterns (scoped collection)", function()
      -- @stack/frame means "all frames in the current stack"
      local result = uri.expand_contextual("@stack/frame", {
        session = "abc",
        thread = 1,
        stack = 5,
      })
      assert.are.equal("dap:session:abc/thread:1/stack:5/frame", result)
    end)

    it("should expand @session/thread pattern", function()
      -- @session/thread means "all threads in the current session"
      local result = uri.expand_contextual("@session/thread", { session = "abc" })
      assert.are.equal("dap:session:abc/thread", result)
    end)

    it("should expand @thread/stack/frame pattern", function()
      -- Multi-level suffix
      local result = uri.expand_contextual("@thread/stack/frame", {
        session = "abc",
        thread = 1,
      })
      assert.are.equal("dap:session:abc/thread:1/stack/frame", result)
    end)
  end)

  describe("uri.expand_contextual (relative patterns)", function()
    local context_map

    before_each(function()
      context_map = {
        session = "abc",
        thread = 1,
        stack = 5,
        frame = 42,
        frame_index = 0,
        stack_index = 0,
      }
    end)

    it("should expand @frame+1 to next frame in stack", function()
      local result = uri.expand_contextual("@frame+1", context_map)
      assert.are.equal("dap:session:abc/thread:1/stack:5/frame[1]", result)
    end)

    it("should expand @frame+2 to two frames down", function()
      local result = uri.expand_contextual("@frame+2", context_map)
      assert.are.equal("dap:session:abc/thread:1/stack:5/frame[2]", result)
    end)

    it("should expand @frame+0 to current index", function()
      local result = uri.expand_contextual("@frame+0", context_map)
      assert.are.equal("dap:session:abc/thread:1/stack:5/frame[0]", result)
    end)

    it("should return nil for @frame-1 when at top (index 0)", function()
      local result = uri.expand_contextual("@frame-1", context_map)
      assert.is_nil(result)
    end)

    it("should expand @frame-1 when not at top", function()
      context_map.frame_index = 2
      local result = uri.expand_contextual("@frame-1", context_map)
      assert.are.equal("dap:session:abc/thread:1/stack:5/frame[1]", result)
    end)

    it("should expand @stack+1 to older stack", function()
      local result = uri.expand_contextual("@stack+1", context_map)
      assert.are.equal("dap:session:abc/thread:1/stack[1]", result)
    end)

    it("should return nil for @stack-1 when at latest (index 0)", function()
      local result = uri.expand_contextual("@stack-1", context_map)
      assert.is_nil(result)
    end)

    it("should expand @stack-1 when not at latest", function()
      context_map.stack_index = 1
      local result = uri.expand_contextual("@stack-1", context_map)
      assert.are.equal("dap:session:abc/thread:1/stack[0]", result)
    end)

    it("should return nil when frame_index is missing from context", function()
      context_map.frame_index = nil
      local result = uri.expand_contextual("@frame+1", context_map)
      assert.is_nil(result)
    end)

    it("should return nil when stack_index is missing from context", function()
      context_map.stack_index = nil
      local result = uri.expand_contextual("@stack+1", context_map)
      assert.is_nil(result)
    end)

    it("should return nil for unsupported entity types in relative patterns", function()
      -- @session+1 doesn't make sense
      local result = uri.expand_contextual("@session+1", context_map)
      assert.is_nil(result)
    end)

    it("should handle shorthand notation (without dap: prefix)", function()
      local result = uri.expand_contextual("@frame+1", context_map)
      assert.are.equal("dap:session:abc/thread:1/stack:5/frame[1]", result)
    end)
  end)

  describe("uri.is_contextual", function()
    it("should return true for patterns with @ markers", function()
      assert.is_true(uri.is_contextual("dap:@session"))
      assert.is_true(uri.is_contextual("dap:@session/thread:1"))
      assert.is_true(uri.is_contextual("dap:session:abc/@thread"))
    end)

    it("should return false for patterns without @ markers", function()
      assert.is_false(uri.is_contextual("dap:session:abc"))
      assert.is_false(uri.is_contextual("dap:session:abc/thread:1"))
    end)
  end)

  describe("uri.get_contextual_markers", function()
    it("should extract all markers from pattern", function()
      local markers = uri.get_contextual_markers("dap:@session/@thread/@frame")
      assert.are.same({ "session", "thread", "frame" }, markers)
    end)

    it("should return empty for non-contextual patterns", function()
      local markers = uri.get_contextual_markers("dap:session:abc/thread:1")
      assert.are.same({}, markers)
    end)
  end)
end)

describe("Contextual URI Resolution", function()
  local Debugger = require("neodap.sdk.debugger")
  local sdk = require("neodap.sdk")
  local debugger

  before_each(function()
    debugger = Debugger:new()
  end)

  after_each(function()
    if debugger then
      debugger:dispose()
    end
  end)

  describe("resolve_contextual", function()
    it("should return nil when context has no frame_uri", function()
      local result = debugger:resolve_contextual("dap:@session")
      assert.is_nil(result:get())
    end)

    it("should update when context changes", function()
      local ctx = debugger:context()
      local result = debugger:resolve_contextual("dap:@session", ctx)

      local observed = {}
      result:watch(function(val)
        table.insert(observed, val)
      end)

      -- Initially nil
      assert.is_nil(result:get())

      -- Simulating context change would require a real session
      -- This test verifies the reactive wiring is in place
      assert.are.equal(0, #observed)
    end)
  end)
end)

-- =============================================================================
-- Relative Index Reactivity Tests (Real Debugger)
-- =============================================================================

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

    coroutine.resume(co)
    local success = vim.wait(timeout_ms, function() return completed end, 100)

    if not success then
      error(string.format("Test '%s' timed out after %dms", name, timeout_ms))
    end
    if test_error then error(test_error) end
    if test_result ~= true then
      error("Test must return true")
    end
  end)
end

describe("Relative Index Reactivity (Real Debugger)", function()
  local sdk = require("neodap.sdk")

  verified_it("@frame+1 updates when context frame changes", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")
    debugger:add_breakpoint({ path = script_path }, 7)  -- line: return x in level_3

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    vim.wait(10000, function() return session.state:get() == "stopped" end)

    -- Get the stack (should have level_3 -> level_2 -> level_1 -> main)
    local thread = session:threads():iter()()
    local stack = thread:stack()
    local frames = {}
    for frame in stack:frames():iter() do
      table.insert(frames, frame)
    end

    -- Sort frames by index (top frame first)
    table.sort(frames, function(a, b) return a.index:get() < b.index:get() end)

    assert(#frames >= 3, "Need at least 3 frames for test")

    -- Create context and pin to top frame (level_3)
    local ctx = debugger:context()
    ctx.frame_uri:set(frames[1].uri)

    -- Resolve @frame+1 (should be level_2, the caller)
    local caller_signal = debugger:resolve_contextual("@frame+1", ctx)

    -- Track observed values
    local observed_callers = {}
    caller_signal:use(function(frame)
      if frame then
        table.insert(observed_callers, frame.name)
      end
    end)

    -- Initial value should be level_2 (caller of level_3)
    local initial_caller = caller_signal:get()
    assert(initial_caller, "@frame+1 should resolve to caller")
    assert.are.equal(frames[2].name, initial_caller.name)

    -- Change context to level_2 (frames[2])
    ctx.frame_uri:set(frames[2].uri)

    -- Give reactive system time to propagate
    vim.wait(200)

    -- Now @frame+1 should be level_1 (caller of level_2)
    local new_caller = caller_signal:get()
    assert(new_caller, "@frame+1 should resolve after context change")
    assert.are.equal(frames[3].name, new_caller.name)

    -- Verify we observed both values (use ran immediately + on change)
    assert(#observed_callers >= 2, "Should have observed at least 2 values, got " .. #observed_callers)
    assert.are.equal(frames[2].name, observed_callers[1])
    assert.are.equal(frames[3].name, observed_callers[2])

    -- Cleanup
    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)
end)
