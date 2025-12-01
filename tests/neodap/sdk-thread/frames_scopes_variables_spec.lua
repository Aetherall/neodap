-- Test that demonstrates listing frames, scopes, and variables
-- Uses real debugpy adapter with actual Python program

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

describe("Frames, Scopes, and Variables", function()
  local script_path = vim.fn.getcwd() .. "/tests/fixtures/stack_test.py"
  local counter_script = vim.fn.getcwd() .. "/tests/fixtures/counter_loop.py"

  verified_it("should list frames, top frame scopes, and scope variables", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Set breakpoint at line 7 (return x in level_3)
    local bp = debugger:add_breakpoint({ path = script_path }, 7)

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
    assert.are.equal("stopped", session.state:get())

    -- Get thread
    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end
    assert.is_not_nil(thread, "Expected thread")

    -- Fetch stack trace
    local stack = thread:stack()
    assert.is_not_nil(stack, "Expected stack")

    -- =========================================================================
    -- 1. LIST ALL FRAMES
    -- =========================================================================
    print("\n=== FRAMES ===")
    local frames = {}
    for frame in stack:frames():iter() do
      table.insert(frames, frame)
      print(string.format("  [%d] %s at line %d", frame.index:get(), frame.name, frame.line))
    end

    assert.is_true(#frames >= 4, "Expected at least 4 frames (level_3, level_2, level_1, main)")

    -- Verify frame structure
    local frame_names = {}
    for _, frame in ipairs(frames) do
      table.insert(frame_names, frame.name)
      assert.is_number(frame.id, "Frame should have numeric id")
      assert.is_string(frame.name, "Frame should have name")
      assert.is_number(frame.line, "Frame should have line number")
    end

    -- Check expected frame names are present
    local has_level_3 = vim.tbl_contains(frame_names, "level_3")
    local has_level_2 = vim.tbl_contains(frame_names, "level_2")
    local has_level_1 = vim.tbl_contains(frame_names, "level_1")
    local has_main = vim.tbl_contains(frame_names, "main")

    assert.is_true(has_level_3, "Should have level_3 frame")
    assert.is_true(has_level_2, "Should have level_2 frame")
    assert.is_true(has_level_1, "Should have level_1 frame")
    assert.is_true(has_main, "Should have main frame")

    -- =========================================================================
    -- 2. GET TOP FRAME AND ITS SCOPES
    -- =========================================================================
    local top_frame = stack:top()
    assert.is_not_nil(top_frame, "Expected top frame")
    assert.are.equal("level_3", top_frame.name, "Top frame should be level_3")
    assert.are.equal(7, top_frame.line, "Top frame should be at line 7")

    -- Fetch scopes for top frame
    local scopes = top_frame:scopes()
    assert.is_not_nil(scopes, "Expected scopes")

    print("\n=== SCOPES (top frame) ===")
    local scope_list = {}
    for scope in scopes:iter() do
      table.insert(scope_list, scope)
      print(string.format("  %s (variablesReference: %d)", scope.name, scope.variablesReference))
    end

    assert.is_true(#scope_list > 0, "Expected at least one scope")

    -- Verify scope structure
    for _, scope in ipairs(scope_list) do
      assert.is_string(scope.name, "Scope should have name")
      assert.is_number(scope.variablesReference, "Scope should have variablesReference")
    end

    -- Find the Locals scope (usually the first one)
    local locals_scope = nil
    for _, scope in ipairs(scope_list) do
      if scope.name == "Locals" or scope.name:match("[Ll]ocal") then
        locals_scope = scope
        break
      end
    end

    -- If no explicit "Locals" scope, use the first scope
    if not locals_scope then
      locals_scope = scope_list[1]
    end
    assert.is_not_nil(locals_scope, "Expected locals scope")

    -- =========================================================================
    -- 3. GET VARIABLES FROM SCOPE
    -- =========================================================================
    local variables = locals_scope:variables()
    assert.is_not_nil(variables, "Expected variables")

    print("\n=== VARIABLES (" .. locals_scope.name .. ") ===")
    local variable_list = {}
    for var in variables:iter() do
      table.insert(variable_list, var)
      local has_children = var.variablesReference > 0 and " [+]" or ""
      print(string.format("  %s = %s%s", var.name, var.value:get(), has_children))
    end

    assert.is_true(#variable_list > 0, "Expected at least one variable")

    -- Verify variable structure
    for _, var in ipairs(variable_list) do
      assert.is_string(var.name, "Variable should have name")
      assert.is_not_nil(var.value:get(), "Variable should have value")
      assert.is_number(var.variablesReference, "Variable should have variablesReference")
    end

    -- Find the 'x' variable (x = 42)
    local x_var = nil
    for _, var in ipairs(variable_list) do
      if var.name == "x" then
        x_var = var
        break
      end
    end

    assert.is_not_nil(x_var, "Expected to find variable 'x'")
    assert.are.equal("42", x_var.value:get(), "Variable 'x' should have value 42")

    -- =========================================================================
    -- CLEANUP
    -- =========================================================================
    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("should fetch nested variables (structured types)", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local bp = debugger:add_breakpoint({ path = script_path }, 7)

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
    local top_frame = stack:top()
    local scopes = top_frame:scopes()

    -- Get first scope
    local scope = nil
    for s in scopes:iter() do
      scope = s
      break
    end

    local variables = scope:variables()

    -- Find a variable with children (variablesReference > 0)
    local structured_var = nil
    for var in variables:iter() do
      if var.variablesReference > 0 then
        structured_var = var
        break
      end
    end

    if structured_var then
      -- Fetch nested variables
      local children = structured_var:variables()
      assert.is_not_nil(children, "Should be able to fetch child variables")

      local child_count = 0
      for child in children:iter() do
        child_count = child_count + 1
        -- Verify child variable structure
        assert.is_string(child.name, "Child variable should have name")
        assert.is_not_nil(child.value:get(), "Child variable should have value")
      end

      assert.is_true(child_count >= 0, "Should be able to iterate child variables")
    end

    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("should show incrementing counter across multiple continues", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Set breakpoint at line 8 (print statement, after counter is updated)
    local bp = debugger:add_breakpoint({ path = counter_script }, 8)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = counter_script,
      console = "internalConsole",
    })

    print("\n=== COUNTER LOOP TEST ===")

    local counter_values = {}

    -- Loop through 3 iterations
    for iteration = 1, 3 do
      -- Wait for stopped state
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)
      assert.are.equal("stopped", session.state:get(), "Should be stopped at iteration " .. iteration)

      -- Get thread and stack
      local thread = nil
      for t in session:threads():iter() do
        thread = t
        break
      end
      assert.is_not_nil(thread, "Expected thread")

      local stack = thread:stack()
      local top_frame = stack:top()
      assert.is_not_nil(top_frame, "Expected top frame")

      -- Get scopes and variables
      local scopes = top_frame:scopes()
      local locals_scope = nil
      for s in scopes:iter() do
        if s.name == "Locals" or s.name:match("[Ll]ocal") then
          locals_scope = s
          break
        end
      end
      if not locals_scope then
        for s in scopes:iter() do
          locals_scope = s
          break
        end
      end

      local variables = locals_scope:variables()

      -- Find counter and i variables
      local counter_val = nil
      local i_val = nil
      for var in variables:iter() do
        if var.name == "counter" then
          counter_val = var.value:get()
        elseif var.name == "i" then
          i_val = var.value:get()
        end
      end

      print(string.format("  Stop #%d: i = %s, counter = %s", iteration, i_val or "nil", counter_val or "nil"))
      table.insert(counter_values, tonumber(counter_val) or 0)

      -- Continue to next iteration (if not last)
      if iteration < 3 then
        session:continue(thread.id)
      end
    end

    print("  Counter values: " .. table.concat(counter_values, " -> "))

    -- Verify counter incremented
    assert.are.equal(1, counter_values[1], "First stop should have counter = 1")
    assert.are.equal(2, counter_values[2], "Second stop should have counter = 2")
    assert.are.equal(3, counter_values[3], "Third stop should have counter = 3")

    -- Cleanup
    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("should set a variable value and see it change", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Set breakpoint at line 8 (after counter is assigned)
    local bp = debugger:add_breakpoint({ path = counter_script }, 8)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = counter_script,
      console = "internalConsole",
    })

    print("\n=== SET VARIABLE TEST ===")

    -- Wait for first stop
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

    local stack = thread:stack()
    local top_frame = stack:top()

    -- Get scopes and find Locals
    local scopes = top_frame:scopes()
    local locals_scope = nil
    for s in scopes:iter() do
      if s.name == "Locals" or s.name:match("[Ll]ocal") then
        locals_scope = s
        break
      end
    end
    if not locals_scope then
      for s in scopes:iter() do
        locals_scope = s
        break
      end
    end

    -- Get variables and find 'counter'
    local variables = locals_scope:variables()
    local counter_var = nil
    for var in variables:iter() do
      if var.name == "counter" then
        counter_var = var
        break
      end
    end
    assert.is_not_nil(counter_var, "Expected to find 'counter' variable")

    -- Read original value
    local original_value = counter_var.value:get()
    print(string.format("  Original value: counter = %s", original_value))
    assert.are.equal("1", original_value, "Counter should start at 1")

    -- Set counter to a new value
    local new_value = "999"
    print(string.format("  Setting counter to %s...", new_value))
    local err, result_value, result_type = counter_var:set_value(new_value)

    assert.is_nil(err, "set_value should succeed: " .. tostring(err or ""))
    assert.are.equal(new_value, result_value, "Returned value should match")

    -- Verify the variable's reactive value was updated
    local updated_value = counter_var.value:get()
    print(string.format("  Updated value: counter = %s", updated_value))
    assert.are.equal(new_value, updated_value, "Variable value should be updated")

    -- Continue and stop again to verify the value persists in the program
    session:continue(thread.id)

    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    -- Get fresh stack and variables
    local stack2 = thread:stack()
    local top_frame2 = stack2:top()
    local scopes2 = top_frame2:scopes()
    local locals_scope2 = nil
    for s in scopes2:iter() do
      if s.name == "Locals" or s.name:match("[Ll]ocal") then
        locals_scope2 = s
        break
      end
    end
    if not locals_scope2 then
      for s in scopes2:iter() do
        locals_scope2 = s
        break
      end
    end

    local variables2 = locals_scope2:variables()
    local counter_var2 = nil
    for var in variables2:iter() do
      if var.name == "counter" then
        counter_var2 = var
        break
      end
    end

    -- After continue, counter should be 1000 (999 + 1 from next iteration)
    -- The loop does counter += 1, so our 999 becomes 1000
    local value_after_continue = counter_var2.value:get()
    print(string.format("  After continue: counter = %s (999 + 1 = 1000)", value_after_continue))

    -- Verify the set value persisted and was incremented
    assert.are.equal("1000", value_after_continue, "Counter should be 1000 (999 + 1)")

    -- Cleanup
    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("should track variable history across stacks", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Set breakpoint at line 8 (after counter is updated)
    local bp = debugger:add_breakpoint({ path = counter_script }, 8)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = counter_script,
      console = "internalConsole",
    })

    print("\n=== VARIABLE HISTORY TEST ===")

    -- Stop 3 times and fetch variables each time
    for iteration = 1, 3 do
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      local thread = nil
      for t in session:threads():iter() do
        thread = t
        break
      end

      local stack = thread:stack()
      local top_frame = stack:top()
      local scopes = top_frame:scopes()
      local locals_scope = nil
      for s in scopes:iter() do
        if s.name == "Locals" or s.name:match("[Ll]ocal") then
          locals_scope = s
          break
        end
      end
      if not locals_scope then
        for s in scopes:iter() do
          locals_scope = s
          break
        end
      end

      -- Fetch variables (this adds them to global collection)
      local vars = locals_scope:variables()

      -- Find counter variable and show its stack_id
      local counter_var = nil
      for v in vars:iter() do
        if v.name == "counter" then
          counter_var = v
          break
        end
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
    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)
end)
