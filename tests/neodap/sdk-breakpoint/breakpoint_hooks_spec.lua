-- Test breakpoint and binding lifecycle hooks with cleanup semantics
-- Focus on when cleanup functions are called based on different lifecycle events

local neostate = require("neostate")
local sdk = require("neodap.sdk")

neostate.setup({
  debug_context = true,
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

describe("Breakpoint and Binding Lifecycle Hooks", function()
  local script_path = vim.fn.getcwd() .. "/tests/fixtures/stack_test.py"

  -- ==========================================================================
  -- BREAKPOINT:ONBINDING
  -- ==========================================================================

  verified_it("breakpoint:onBinding - cleanup runs when binding is removed", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local bp = debugger:add_breakpoint({ path = script_path }, 10)

    local binding_added = 0
    local binding_removed = 0

    bp:onBinding(function(binding)
      binding_added = binding_added + 1
      return function()
        -- Cleanup: runs when binding is removed from collection
        binding_removed = binding_removed + 1
      end
    end)

    -- Create first session - should trigger onBinding
    local session1 = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    vim.wait(1000)
    assert.are.equal(1, binding_added, "Should have 1 binding after first session")
    assert.are.equal(0, binding_removed, "No cleanup yet")

    -- Create second session - should trigger onBinding again
    local session2 = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    vim.wait(1000)
    assert.are.equal(2, binding_added, "Should have 2 bindings after second session")
    assert.are.equal(0, binding_removed, "No cleanup yet")

    -- Disconnect first session - should cleanup its binding
    session1:disconnect(true)

    -- Wait for session to be terminated and disposed
    vim.wait(5000, function()
      return binding_removed > 0
    end)

    assert.are.equal(2, binding_added, "Still 2 added total")
    assert.are.equal(1, binding_removed, "First binding cleaned up")

    -- Cleanup
    session2:disconnect(true)
    vim.wait(1000)
    assert.are.equal(2, binding_removed, "Both bindings cleaned up")

    debugger:dispose()
    return true
  end)

  -- ==========================================================================
  -- BREAKPOINT:ONVERIFIEDBINDING
  -- ==========================================================================

  verified_it("breakpoint:onVerifiedBinding - fires when verified, cleanup when session ends", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local bp = debugger:add_breakpoint({ path = script_path }, 10)

    local verified_added = 0
    local verified_removed = 0

    bp:onVerifiedBinding(function(binding)
      verified_added = verified_added + 1
      return function()
        verified_removed = verified_removed + 1
      end
    end)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    -- Wait for verification
    vim.wait(5000, function()
      for binding in session:bindings():iter() do
        if binding.verified:get() then
          return true
        end
      end
      return false
    end)

    assert.are.equal(1, verified_added, "Should have 1 verified binding")
    assert.are.equal(0, verified_removed, "No cleanup yet")

    -- Disconnect session - removes binding entirely
    session:disconnect(true)
    vim.wait(1000)

    assert.are.equal(1, verified_removed, "Cleanup when binding removed")

    debugger:dispose()
    return true
  end)

  -- ==========================================================================
  -- BINDING:ONVERIFIED
  -- ==========================================================================

  verified_it("binding:onVerified - fires immediately and cleanup on binding disposal", function()
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

    -- Wait for binding to be verified
    vim.wait(5000, function()
      for binding in session:bindings():iter() do
        if binding.verified:get() then
          return true
        end
      end
      return false
    end)

    local binding = nil
    for b in session:bindings():iter() do
      binding = b
      break
    end
    assert.is_not_nil(binding, "Should have binding")

    local call_count = 0
    local cleanup_count = 0

    binding:onVerified(function(verified)
      call_count = call_count + 1
      assert.is_true(verified, "Should be verified")
      return function()
        -- Cleanup: runs when binding disposed
        cleanup_count = cleanup_count + 1
      end
    end)

    -- Should fire immediately with current value (true)
    vim.wait(100)
    assert.are.equal(1, call_count, "Should fire immediately with current verified state")
    assert.are.equal(0, cleanup_count, "No cleanup yet")

    -- Disconnect session - disposes binding
    session:disconnect(true)
    vim.wait(1000)

    assert.are.equal(1, call_count, "Still 1 call")
    assert.are.equal(1, cleanup_count, "Cleanup when binding disposed")

    debugger:dispose()
    return true
  end)

  -- ==========================================================================
  -- BINDING:ONHIT
  -- ==========================================================================

  verified_it("binding:onHit - cleanup when frame becomes nil (unhit)", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Add two breakpoints for multiple stops
    local bp1 = debugger:add_breakpoint({ path = script_path }, 10)
    local bp2 = debugger:add_breakpoint({ path = script_path }, 14)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    -- No need to fetch stacks - onHit doesn't require it!

    -- Wait for first stop
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    local binding1 = nil
    for b in session:bindings():iter() do
      if b.breakpoint == bp1 then
        binding1 = b
        break
      end
    end
    assert.is_not_nil(binding1, "Should have binding for bp1")

    local hit_count = 0
    local cleanup_count = 0

    binding1:onHit(function()
      hit_count = hit_count + 1
      return function()
        -- Cleanup: runs when hit becomes false OR binding disposed
        cleanup_count = cleanup_count + 1
      end
    end)

    -- Wait for hit
    vim.wait(2000, function()
      return binding1.hit:get() == true
    end)

    assert.are.equal(1, hit_count, "Should fire when hit")
    assert.are.equal(0, cleanup_count, "No cleanup yet")

    -- Continue to next breakpoint - unhits bp1
    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end
    session:continue(thread.id)

    -- Wait for second stop (hit becomes false)
    vim.wait(10000, function()
      return binding1.hit:get() == false
    end)

    assert.are.equal(1, hit_count, "Still 1 hit (doesn't fire again)")
    assert.are.equal(1, cleanup_count, "Cleanup when unhit")

    -- Cleanup
    session:disconnect(true)
    debugger:dispose()
    return true
  end)

  -- ==========================================================================
  -- BREAKPOINT:ONHIT
  -- ==========================================================================

  verified_it("breakpoint:onHit - cleanup per binding, not all bindings", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Add two breakpoints
    local bp1 = debugger:add_breakpoint({ path = script_path }, 10)
    local bp2 = debugger:add_breakpoint({ path = script_path }, 14)

    local hit_count = 0
    local cleanup_count = 0

    bp1:onHit(function(binding)
      hit_count = hit_count + 1
      return function()
        -- Cleanup: runs when THAT binding's hit becomes false OR that binding removed
        -- NOT when other bindings are still hit
        cleanup_count = cleanup_count + 1
      end
    end)

    -- Create session - will hit bp1
    local session1 = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    -- No need to fetch stacks - onHit doesn't require it!

    -- Wait for first session to hit
    vim.wait(10000, function()
      return session1.state:get() == "stopped"
    end)

    -- Give hook some time to fire
    vim.wait(1000)

    assert.are.equal(1, hit_count, "First session hit")
    assert.are.equal(0, cleanup_count, "No cleanup yet")

    -- Continue first session to next breakpoint (unhits bp1)
    local thread1 = nil
    for t in session1:threads():iter() do
      thread1 = t
      break
    end
    session1:continue(thread1.id)

    -- Wait for unhit
    vim.wait(10000, function()
      local binding1 = nil
      for b in session1:bindings():iter() do
        if b.breakpoint == bp1 then
          binding1 = b
          break
        end
      end
      return binding1 and binding1.hit:get() == false
    end)

    assert.are.equal(1, hit_count, "Still 1 hit total")
    assert.are.equal(1, cleanup_count, "Cleanup for first binding")

    -- Cleanup
    session1:disconnect(true)
    debugger:dispose()
    return true
  end)

  verified_it("breakpoint:onHit - multiple bindings, cleanup individually", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local bp = debugger:add_breakpoint({ path = script_path }, 10)

    local hit_count = 0
    local cleanup_count = 0
    local hit_sessions = {}

    bp:onHit(function(binding)
      hit_count = hit_count + 1
      hit_sessions[binding.session.id] = true
      return function()
        cleanup_count = cleanup_count + 1
        hit_sessions[binding.session.id] = nil
      end
    end)

    -- Create two sessions
    local session1 = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    local session2 = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    -- No need to fetch stacks - onHit doesn't require it!

    -- Wait for both to hit
    vim.wait(10000, function()
      return session1.state:get() == "stopped" and session2.state:get() == "stopped"
    end)

    -- Give hooks time to fire
    vim.wait(1000)

    assert.are.equal(2, hit_count, "Both sessions hit")
    assert.are.equal(0, cleanup_count, "No cleanup yet")
    assert.are.equal(2, vim.tbl_count(hit_sessions), "Both sessions tracked")

    -- Disconnect first session only
    session1:disconnect(true)
    vim.wait(1000)

    assert.are.equal(2, hit_count, "Still 2 hits total")
    assert.are.equal(1, cleanup_count, "Only first session cleaned up")
    assert.are.equal(1, vim.tbl_count(hit_sessions), "Only second session still tracked")

    -- Cleanup
    session2:disconnect(true)
    vim.wait(1000)
    assert.are.equal(2, cleanup_count, "Both cleaned up")
    assert.are.equal(0, vim.tbl_count(hit_sessions), "No sessions tracked")

    debugger:dispose()
    return true
  end)
end)
