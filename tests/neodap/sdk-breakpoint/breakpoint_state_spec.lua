-- Test breakpoint state transitions
-- Focus: hit detection when stopped at breakpoint, enabled state persistence

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

-- =============================================================================
-- HIT DETECTION TESTS
-- =============================================================================

describe("Breakpoint Hit Detection", function()
  local script_path = vim.fn.getcwd() .. "/tests/fixtures/stack_test.py"

  describe("with Python debugger", function()
    verified_it("binding.hit is true when stopped at breakpoint", function()
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

      -- Find the binding for our breakpoint
      local binding = nil
      for b in session:bindings():iter() do
        if b.breakpoint == bp then
          binding = b
          break
        end
      end

      assert.is_not_nil(binding, "Should have binding for breakpoint")

      -- Wait for hit detection (may be async)
      local hit_detected = vim.wait(2000, function()
        return binding.hit:get() == true
      end)

      assert.is_true(hit_detected, "binding.hit should become true when stopped at breakpoint")

      -- Cleanup
      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("breakpoint.state is 'hit' when stopped at breakpoint", function()
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

      -- Wait a bit for state to propagate
      vim.wait(500)

      assert.are.equal("hit", bp.state:get(), "breakpoint.state should be 'hit' when stopped")

      -- Cleanup
      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)

  describe("with js-debug", function()
    local js_script_path = vim.fn.getcwd() .. "/tests/fixtures/stepping_test.js"

    -- Helper to wait for child session (js-debug spawns child)
    local function wait_for_child_session(bootstrap_session)
      local child = nil
      vim.wait(10000, function()
        for s in bootstrap_session:children():iter() do
          child = s
          return true
        end
        return false
      end)
      return child
    end

    verified_it("binding.hit is true when stopped at breakpoint (js-debug)", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("pwa-node", {
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
          local h, p = chunk:match("Debug server listening at (.*):(%d+)")
          return tonumber(p), h
        end
      })

      local bp = debugger:add_breakpoint({ path = js_script_path }, 12)

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = js_script_path,
        console = "internalConsole",
      })

      -- Wait for child session
      local session = wait_for_child_session(bootstrap)
      assert.is_not_nil(session, "Should have child session")

      -- Wait for stopped state
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Find the binding for our breakpoint in the child session
      local binding = nil
      for b in session:bindings():iter() do
        if b.breakpoint == bp then
          binding = b
          break
        end
      end

      assert.is_not_nil(binding, "Should have binding for breakpoint in child session")

      -- Wait for hit detection (may be async)
      local hit_detected = vim.wait(2000, function()
        return binding.hit:get() == true
      end)

      assert.is_true(hit_detected, "binding.hit should become true when stopped at breakpoint")

      -- Cleanup
      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)
end)

-- =============================================================================
-- ENABLED STATE TESTS
-- =============================================================================

describe("Breakpoint Enabled State", function()
  local script_path = vim.fn.getcwd() .. "/tests/fixtures/stack_test.py"

  verified_it("enabled state persists when set via signal", function()
    local debugger = sdk:create_debugger()

    local bp = debugger:add_breakpoint({ path = script_path }, 10)

    -- Default should be true
    assert.is_true(bp.enabled:get(), "enabled should default to true")

    -- Set to false
    bp.enabled:set(false)
    assert.is_false(bp.enabled:get(), "enabled should be false after set(false)")

    -- Set back to true
    bp.enabled:set(true)
    assert.is_true(bp.enabled:get(), "enabled should be true after set(true)")

    debugger:dispose()
    return true
  end)

  verified_it("disable() method sets enabled to false", function()
    local debugger = sdk:create_debugger()

    local bp = debugger:add_breakpoint({ path = script_path }, 10)

    assert.is_true(bp.enabled:get(), "enabled should default to true")

    bp:disable()
    assert.is_false(bp.enabled:get(), "enabled should be false after disable()")

    debugger:dispose()
    return true
  end)

  verified_it("enable() method sets enabled to true", function()
    local debugger = sdk:create_debugger()

    local bp = debugger:add_breakpoint({ path = script_path }, 10)

    bp.enabled:set(false)
    assert.is_false(bp.enabled:get(), "enabled should be false")

    bp:enable()
    assert.is_true(bp.enabled:get(), "enabled should be true after enable()")

    debugger:dispose()
    return true
  end)

  verified_it("enabled state change triggers watchers", function()
    local debugger = sdk:create_debugger()

    local bp = debugger:add_breakpoint({ path = script_path }, 10)

    local watch_count = 0
    local last_value = nil

    bp.enabled:watch(function(value)
      watch_count = watch_count + 1
      last_value = value
    end)

    bp.enabled:set(false)
    vim.wait(100)

    assert.are.equal(1, watch_count, "watcher should fire once")
    assert.is_false(last_value, "watcher should receive false")

    bp.enabled:set(true)
    vim.wait(100)

    assert.are.equal(2, watch_count, "watcher should fire twice")
    assert.is_true(last_value, "watcher should receive true")

    debugger:dispose()
    return true
  end)
end)
