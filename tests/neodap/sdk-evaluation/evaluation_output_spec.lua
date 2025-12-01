-- Tests for expression evaluation and structured output
-- Tests both Python (debugpy) and JavaScript (js-debug) adapters

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

describe("Expression Evaluation", function()
  local py_script = vim.fn.getcwd() .. "/tests/fixtures/evaluation_test.py"
  local js_script = vim.fn.fnamemodify("tests/fixtures/evaluation_test.js", ":p")

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

  describe("Python (debugpy)", function()
    verified_it("should evaluate simple expressions", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      -- Set breakpoint at line 24 (after debugger statement)
      debugger:add_breakpoint({ path = py_script }, 24)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = py_script,
        console = "internalConsole",
      })

      print("\n=== PYTHON EVALUATION TEST ===")

      -- Wait for stop at breakpoint
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      local thread = nil
      for t in session:threads():iter() do
        thread = t
        break
      end

      local stack = thread:stack()
      local frame = stack:top()
      print(string.format("  Frame: %s at line %d", frame.name, frame.line))

      -- Test simple arithmetic expression
      local err, result = frame:evaluate("1 + 2 + 3")
      assert.is_nil(err, "Arithmetic evaluation should succeed")
      assert.is_not_nil(result, "Should get result")
      print(string.format("  1 + 2 + 3 = %s", result.result))
      assert.are.equal("6", result.result)

      -- Test variable reference
      err, result = frame:evaluate("simple_number")
      assert.is_nil(err, "Variable evaluation should succeed")
      print(string.format("  simple_number = %s", result.result))
      assert.are.equal("42", result.result)

      -- Test string variable
      err, result = frame:evaluate("simple_string")
      assert.is_nil(err, "String evaluation should succeed")
      print(string.format("  simple_string = %s", result.result))
      assert.is_truthy(result.result:match("hello world"))

      -- Test expression with variable
      err, result = frame:evaluate("simple_number * 2")
      assert.is_nil(err, "Expression with variable should succeed")
      print(string.format("  simple_number * 2 = %s", result.result))
      assert.are.equal("84", result.result)

      -- Cleanup
      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("should evaluate structured objects and expand children", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      debugger:add_breakpoint({ path = py_script }, 24)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = py_script,
        console = "internalConsole",
      })

      print("\n=== PYTHON STRUCTURED EVALUATION TEST ===")

      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      local thread = nil
      for t in session:threads():iter() do
        thread = t
        break
      end

      local stack = thread:stack()
      local frame = stack:top()

      -- Test evaluating a dict (structured object)
      local err, result = frame:evaluate("user")
      assert.is_nil(err, "Dict evaluation should succeed")
      assert.is_not_nil(result, "Should get result")
      print(string.format("  user = %s (type: %s)", result.result, result.type or "nil"))

      -- Check if result has children (variablesReference > 0)
      if result.variablesReference > 0 then
        print(string.format("  user has children (variablesReference=%d)", result.variablesReference))

        -- Expand children
        local children = result:variables()
        assert.is_not_nil(children, "Should get children")

        print("  user children:")
        for child in children:iter() do
          print(string.format("    - %s = %s", child.name, child.value:get()))
        end

        -- Verify we got expected keys
        local found_name = false
        local found_age = false
        for child in children:iter() do
          if child.name == "'name'" or child.name == "name" then
            found_name = true
          end
          if child.name == "'age'" or child.name == "age" then
            found_age = true
          end
        end
        assert.is_true(found_name, "Should have 'name' key")
        assert.is_true(found_age, "Should have 'age' key")
      else
        print("  Note: user has no expandable children (simple representation)")
      end

      -- Test evaluating a list
      err, result = frame:evaluate("numbers")
      assert.is_nil(err, "List evaluation should succeed")
      print(string.format("  numbers = %s", result.result))

      if result.variablesReference > 0 then
        local items = result:variables()
        print(string.format("  numbers has %d items", items and items:count() or 0))
      end

      -- Cleanup
      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)

  describe("JavaScript (js-debug)", function()
    verified_it("should evaluate simple expressions", function()
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

      -- Set breakpoint at debugger statement line
      debugger:add_breakpoint({ path = js_script }, 24)

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = js_script,
        console = "internalConsole",
      })

      print("\n=== JAVASCRIPT EVALUATION TEST ===")

      local session = wait_for_child_session(bootstrap)
      if not session then
        error("No child session created")
      end

      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)
      vim.wait(100)  -- Let js-debug populate data

      local thread = nil
      for t in session:threads():iter() do
        thread = t
        break
      end

      local stack = thread:stack()
      local frame = stack:top()

      -- Test simple arithmetic expression
      local err, result = frame:evaluate("1 + 2 + 3")
      assert.is_nil(err, "Arithmetic evaluation should succeed")
      assert.is_not_nil(result, "Should get result")
      print(string.format("  1 + 2 + 3 = %s", result.result))
      assert.are.equal("6", result.result)

      -- Test variable reference
      err, result = frame:evaluate("simpleNumber")
      assert.is_nil(err, "Variable evaluation should succeed")
      print(string.format("  simpleNumber = %s", result.result))
      assert.are.equal("42", result.result)

      -- Test string variable
      err, result = frame:evaluate("simpleString")
      assert.is_nil(err, "String evaluation should succeed")
      print(string.format("  simpleString = %s", result.result))
      assert.is_truthy(result.result:match("hello world"))

      -- Test expression with variable
      err, result = frame:evaluate("simpleNumber * 2")
      assert.is_nil(err, "Expression with variable should succeed")
      print(string.format("  simpleNumber * 2 = %s", result.result))
      assert.are.equal("84", result.result)

      -- Cleanup
      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("should evaluate structured objects and expand children", function()
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

      debugger:add_breakpoint({ path = js_script }, 24)

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = js_script,
        console = "internalConsole",
      })

      print("\n=== JAVASCRIPT STRUCTURED EVALUATION TEST ===")

      local session = wait_for_child_session(bootstrap)
      if not session then
        error("No child session created")
      end

      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)
      vim.wait(100)

      local thread = nil
      for t in session:threads():iter() do
        thread = t
        break
      end

      local stack = thread:stack()
      local frame = stack:top()

      -- Test evaluating an object
      local err, result = frame:evaluate("user")
      assert.is_nil(err, "Object evaluation should succeed")
      assert.is_not_nil(result, "Should get result")
      print(string.format("  user = %s (type: %s)", result.result, result.type or "nil"))

      -- Check if result has children
      if result.variablesReference > 0 then
        print(string.format("  user has children (variablesReference=%d)", result.variablesReference))

        local children = result:variables()
        assert.is_not_nil(children, "Should get children")

        print("  user children:")
        for child in children:iter() do
          print(string.format("    - %s = %s", child.name, child.value:get()))
        end

        -- Verify expected properties
        local found_name = false
        local found_age = false
        for child in children:iter() do
          if child.name == "name" then
            found_name = true
          end
          if child.name == "age" then
            found_age = true
          end
        end
        assert.is_true(found_name, "Should have 'name' property")
        assert.is_true(found_age, "Should have 'age' property")
      end

      -- Test evaluating an array
      err, result = frame:evaluate("numbers")
      assert.is_nil(err, "Array evaluation should succeed")
      print(string.format("  numbers = %s", result.result))

      if result.variablesReference > 0 then
        local items = result:variables()
        print(string.format("  numbers has %d items", items and items:count() or 0))
      end

      -- Cleanup
      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)
end)

describe("Debug Output", function()
  local js_script = vim.fn.fnamemodify("tests/fixtures/evaluation_test.js", ":p")

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

  verified_it("should capture console output events", function()
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

    local bootstrap = debugger:start({
      type = "pwa-node",
      request = "launch",
      program = js_script,
      console = "internalConsole",
    })

    print("\n=== DEBUG OUTPUT TEST ===")

    local session = wait_for_child_session(bootstrap)
    if not session then
      error("No child session created")
    end

    -- Collect outputs using the reactive API
    local outputs = {}
    session:onOutput(function(output)
      table.insert(outputs, output)
    end)

    -- Let program run to completion (no breakpoint)
    vim.wait(5000, function()
      return session.state:get() == "terminated" or #outputs >= 2
    end, 100)

    print(string.format("  Captured %d output events", #outputs))

    for i, output in ipairs(outputs) do
      print(string.format("    [%d] category=%s, output=%s",
        i, output.category, (output.output or ""):sub(1, 50)))
    end

    -- Should have captured some output
    assert.is_true(#outputs >= 1, "Should capture at least one output event")

    -- Check output categories
    local has_console = false
    local has_stdout = false
    for _, output in ipairs(outputs) do
      if output.category == "console" then
        has_console = true
      end
      if output.category == "stdout" then
        has_stdout = true
      end
    end
    assert.is_true(has_console or has_stdout, "Should have console or stdout output")

    -- Cleanup
    bootstrap:disconnect(true)
    vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("should handle output with structured data", function()
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

    local bootstrap = debugger:start({
      type = "pwa-node",
      request = "launch",
      program = js_script,
      console = "internalConsole",
    })

    print("\n=== STRUCTURED OUTPUT TEST ===")

    local session = wait_for_child_session(bootstrap)
    if not session then
      error("No child session created")
    end

    local structured_outputs = {}
    session:onOutput(function(output)
      if output.variablesReference and output.variablesReference > 0 then
        table.insert(structured_outputs, output)
      end
    end)

    -- Let program run
    vim.wait(5000, function()
      return session.state:get() == "terminated" or #structured_outputs >= 1
    end, 100)

    print(string.format("  Found %d structured outputs", #structured_outputs))

    -- If we have structured output, try to expand it
    if #structured_outputs > 0 then
      local output = structured_outputs[1]
      print(string.format("  Structured output: category=%s, variablesReference=%d",
        output.category, output.variablesReference))

      -- Try to expand variables
      if output.variables then
        local vars = output:variables()
        if vars then
          print("  Expanded variables:")
          for v in vars:iter() do
            print(string.format("    - %s = %s", v.name, v.value:get()))
          end
        end
      end
    else
      print("  Note: No structured output captured (js-debug may not support this)")
    end

    -- Cleanup
    bootstrap:disconnect(true)
    vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)
end)

describe("Completions", function()
  local py_script = vim.fn.getcwd() .. "/tests/fixtures/evaluation_test.py"
  local js_script = vim.fn.fnamemodify("tests/fixtures/evaluation_test.js", ":p")

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

  describe("Python (debugpy)", function()
    verified_it("should provide completions for variables", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      debugger:add_breakpoint({ path = py_script }, 24)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = py_script,
        console = "internalConsole",
      })

      print("\n=== PYTHON COMPLETIONS TEST ===")

      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Check capabilities
      print(string.format("  supportsCompletions: %s", tostring(session:supportsCompletions())))
      print(string.format("  triggerCharacters: %s", vim.inspect(session:completionTriggerCharacters())))

      local thread = nil
      for t in session:threads():iter() do
        thread = t
        break
      end

      local stack = thread:stack()
      local frame = stack:top()

      -- Test completion for "user." - should show dict keys
      local err, completions = frame:completions("user.", 6)

      if err then
        print(string.format("  Completions error: %s", err))
        -- Some adapters don't support completions - that's OK
        if err:match("not supported") or err:match("unsupported") then
          print("  Note: Adapter does not support completions")
        end
      else
        print(string.format("  Got %d completions for 'user.'", #completions))
        for i, item in ipairs(completions) do
          if i <= 10 then  -- Limit output
            print(string.format("    [%d] %s (type: %s)", i, item.label, item.type or "nil"))
          end
        end
        if #completions > 10 then
          print(string.format("    ... and %d more", #completions - 10))
        end
      end

      -- Test completion for partial variable name "simple"
      err, completions = frame:completions("simple", 7)

      if not err then
        print(string.format("  Got %d completions for 'simple'", #completions))
        for i, item in ipairs(completions) do
          if i <= 5 then
            print(string.format("    [%d] %s", i, item.label))
          end
        end
      end

      -- Cleanup
      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)

  describe("JavaScript (js-debug)", function()
    verified_it("should provide completions for variables", function()
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

      debugger:add_breakpoint({ path = js_script }, 24)

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = js_script,
        console = "internalConsole",
      })

      print("\n=== JAVASCRIPT COMPLETIONS TEST ===")

      local session = wait_for_child_session(bootstrap)
      if not session then
        error("No child session created")
      end

      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)
      vim.wait(100)

      -- Check capabilities
      print(string.format("  supportsCompletions: %s", tostring(session:supportsCompletions())))

      local thread = nil
      for t in session:threads():iter() do
        thread = t
        break
      end

      local stack = thread:stack()
      local frame = stack:top()

      -- Test completion for "user." - should show object properties
      local err, completions = frame:completions("user.", 6)

      if err then
        print(string.format("  Completions error: %s", err))
        if err:match("not supported") or err:match("unsupported") then
          print("  Note: Adapter does not support completions")
        end
      else
        print(string.format("  Got %d completions for 'user.'", #completions))
        for i, item in ipairs(completions) do
          if i <= 10 then
            print(string.format("    [%d] %s (type: %s)", i, item.label, item.type or "nil"))
          end
        end
        if #completions > 10 then
          print(string.format("    ... and %d more", #completions - 10))
        end
      end

      -- Test completion for partial "simple"
      err, completions = frame:completions("simple", 7)

      if not err then
        print(string.format("  Got %d completions for 'simple'", #completions))
        for i, item in ipairs(completions) do
          if i <= 5 then
            print(string.format("    [%d] %s", i, item.label))
          end
        end
      end

      -- Cleanup
      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)
end)
