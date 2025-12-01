-- Tests for variable tracking with js-debug adapter
-- Uses real js-debug adapter with actual JavaScript program

local sdk = require("neodap.sdk")
local neostate = require("neostate")

-- Inline verified_it helper for async tests
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

describe("JavaScript Variable Tracking", function()
  local counter_script = vim.fn.fnamemodify("tests/fixtures/counter_loop.js", ":p")

  -- Helper to wait for js-debug child session
  local function wait_for_child_session(bootstrap_session)
    local child = nil
    vim.wait(10000, function()
      for s in bootstrap_session:children():iter() do
        child = s
        return true
      end
      return false
    end, 50)
    return child
  end

  verified_it("should track variable history across stacks", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("pwa-node", {
      type = "server",
      command = "js-debug",
      args = { "0" },
      connect_condition = function(chunk)
        local h, p = chunk:match("Debug server listening at (.*):(%d+)")
        return tonumber(p), h
      end,
    })

    -- Set breakpoint at line 8 (after counter is updated)
    debugger:add_breakpoint({ path = counter_script }, 8)

    -- Start returns the bootstrap session
    local bootstrap = debugger:start({
      type = "pwa-node",
      request = "launch",
      program = counter_script,
      console = "internalConsole",
    })

    print("\n=== JS VARIABLE HISTORY TEST ===")

    -- js-debug creates a child session for actual debugging
    local session = wait_for_child_session(bootstrap)
    if not session then
      error("No child session created")
    end

    -- Stop 3 times and fetch variables each time
    for iteration = 1, 3 do
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Small delay to ensure js-debug has fully populated stack/scope data
      vim.wait(100)

      local thread = nil
      for t in session:threads():iter() do
        thread = t
        break
      end

      local stack = thread:stack()
      local top_frame = stack:top()
      local scopes = top_frame:scopes()

      -- Search for counter variable in all scopes (js-debug may put it in Block or Local)
      local counter_var = nil

      for s in scopes:iter() do
        -- Skip Global scope - counter won't be there
        if s.name:match("Global") then
          goto continue
        end

        local vars = s:variables()
        for v in vars:iter() do
          if v.name == "counter" and not counter_var then
            counter_var = v
          end
        end

        ::continue::
      end

      print(string.format("  Stop #%d: stack=%s, counter=%s, is_current=%s",
        iteration,
        stack.id,
        counter_var and counter_var.value:get() or "nil",
        counter_var and tostring(counter_var._is_current:get()) or "nil"))

      if iteration < 3 then
        session:continue(thread.id)
        -- Check if variable was marked expired after continue
        print(string.format("    After continue: counter is_current=%s",
          counter_var and tostring(counter_var._is_current:get()) or "nil"))
      end
    end

    -- Small delay to let any async handlers finish
    vim.wait(200)

    -- Now check variable history
    local history = session:getVariableHistory("counter")
    print(string.format("  Variable history for 'counter': %d entries", #history))

    for i, entry in ipairs(history) do
      print(string.format("    [%d] stack=%s, value=%s, is_current=%s",
        i, entry.stack_id, entry.value, tostring(entry.is_current)))
    end

    assert.is_true(#history >= 3, "Should have at least 3 history entries for counter")

    -- Verify values progressed
    local values = {}
    for _, entry in ipairs(history) do
      table.insert(values, entry.value)
    end
    print("  Values: " .. table.concat(values, " -> "))

    -- Check we can get current variable
    local current = session:getCurrentVariable("counter")
    assert.is_not_nil(current, "Should find current variable 'counter'")
    assert.is_true(current._is_current:get(), "Current variable should be marked current")
    print(string.format("  Current value: %s", current.value:get()))

    -- Cleanup
    bootstrap:disconnect(true)
    vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)
end)
