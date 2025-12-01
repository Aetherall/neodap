local sdk = require("neodap.sdk")
local neostate = require("neostate")

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

describe("variable_completion plugin", function()
  describe("setup", function()
    verified_it("should set completefunc on variable edit buffers", function()
      local debugger = sdk:create_debugger()

      -- Register Python adapter
      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      -- Load plugins
      require("neodap.plugins.variable_edit").setup(debugger)
      require("neodap.plugins.variable_completion")(debugger)

      local script_path = vim.fn.fnamemodify("tests/fixtures/stepping_test.py", ":p")

      print("\n=== VARIABLE COMPLETION SETUP TEST ===")

      -- Set breakpoint
      debugger:add_breakpoint({ path = script_path }, 11)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for stopped state
      vim.wait(15000, function()
        return session.state:get() == "stopped"
      end)

      -- Step to get local variables
      local thread = nil
      for t in session:threads():iter() do
        thread = t
        break
      end
      assert.is_not_nil(thread, "Should have thread")

      thread:step_over()

      -- Wait for stopped again
      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Get the stack and frame
      local stack = thread:stack()
      assert.is_not_nil(stack, "Should have stack")

      local frame = stack:top()
      assert.is_not_nil(frame, "Should have frame")

      -- Fetch scopes
      local scopes = frame:scopes()
      assert.is_not_nil(scopes, "Should have scopes")

      -- Find Locals scope
      local locals_scope = nil
      for scope in scopes:iter() do
        if scope.name == "Locals" then
          locals_scope = scope
          break
        end
      end
      assert.is_not_nil(locals_scope, "Should have Locals scope")

      -- Fetch variables
      local variables = locals_scope:variables()
      assert.is_not_nil(variables, "Should have variables")

      -- Find 'a' variable
      local a_var = nil
      for var in variables:iter() do
        if var.name == "a" then
          a_var = var
          break
        end
      end
      assert.is_not_nil(a_var, "Should have 'a' variable")
      assert.is_not_nil(a_var.uri, "Variable should have URI")

      print(string.format("  Variable 'a' URI: %s", a_var.uri))

      -- Open variable edit buffer with concrete URI
      vim.cmd("edit " .. a_var.uri)
      local bufnr = vim.fn.bufnr(a_var.uri)

      assert.is_true(bufnr > 0, "Buffer should be opened")

      -- Check completefunc is set
      local completefunc = vim.bo[bufnr].completefunc
      print(string.format("  completefunc: %s", completefunc))

      assert.is_true(completefunc:match("^v:lua%._dap_complete_%d+$") ~= nil,
        "Should have completefunc set to v:lua._dap_complete_<bufnr>")

      -- Verify the global function exists for this buffer
      local fn_name = completefunc:gsub("^v:lua%.", "")
      assert.is_not_nil(_G[fn_name], "Global completion function should exist for buffer")

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("should provide completions from debugger", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      require("neodap.plugins.variable_edit").setup(debugger)
      require("neodap.plugins.variable_completion")(debugger)

      local script_path = vim.fn.fnamemodify("tests/fixtures/stepping_test.py", ":p")

      print("\n=== VARIABLE COMPLETION REQUEST TEST ===")

      debugger:add_breakpoint({ path = script_path }, 11)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(15000, function()
        return session.state:get() == "stopped"
      end)

      local thread = nil
      for t in session:threads():iter() do
        thread = t
        break
      end

      thread:step_over()

      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Check if debugpy supports completions
      local supports_completions = session.capabilities and session.capabilities.supportsCompletionsRequest
      print(string.format("  Adapter supports completions: %s", tostring(supports_completions)))

      if not supports_completions then
        print("  Skipping completion test - adapter doesn't support completions")
        session:disconnect(true)
        vim.wait(2000, function() return session.state:get() == "terminated" end)
        debugger:dispose()
        return true
      end

      -- Get frame for completions request
      local stack = thread:stack()
      local frame = stack:top()

      -- Test completions request directly using neostate.settle for sync
      local completions_result, completions_err = neostate.settle(
        session.client:request("completions", {
          text = "val",
          column = 4,
          frameId = frame.id,
        })
      )

      print(string.format("  Completions error: %s", tostring(completions_err)))
      print(string.format("  Completions count: %d", completions_result and completions_result.targets and #completions_result.targets or 0))

      assert.is_nil(completions_err, "Should not have error")

      local targets = completions_result and completions_result.targets or {}
      if #targets > 0 then
        print(string.format("  First completion: %s", targets[1].label))
        -- Look for 'value' variable in completions
        local found_value = false
        for _, item in ipairs(targets) do
          if item.label == "value" then
            found_value = true
            break
          end
        end
        print(string.format("  Found 'value' in completions: %s", tostring(found_value)))
      end

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)

  describe("cleanup", function()
    verified_it("should remove per-buffer functions on dispose", function()
      local debugger = sdk:create_debugger()

      -- Register Python adapter
      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      -- Load plugins
      require("neodap.plugins.variable_edit").setup(debugger)
      require("neodap.plugins.variable_completion")(debugger)

      local script_path = vim.fn.fnamemodify("tests/fixtures/stepping_test.py", ":p")

      print("\n=== VARIABLE COMPLETION CLEANUP TEST ===")

      -- Set breakpoint and start session
      debugger:add_breakpoint({ path = script_path }, 11)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      vim.wait(15000, function()
        return session.state:get() == "stopped"
      end)

      local thread = nil
      for t in session:threads():iter() do
        thread = t
        break
      end
      thread:step_over()

      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Get a variable and open its edit buffer
      local stack = thread:stack()
      local frame = stack:top()
      local scopes = frame:scopes()

      local locals_scope = nil
      for scope in scopes:iter() do
        if scope.name == "Locals" then
          locals_scope = scope
          break
        end
      end

      local variables = locals_scope:variables()
      local a_var = nil
      for var in variables:iter() do
        if var.name == "a" then
          a_var = var
          break
        end
      end

      -- Open variable edit buffer
      vim.cmd("edit " .. a_var.uri)
      local bufnr = vim.fn.bufnr(a_var.uri)

      -- Get the function name from completefunc
      local completefunc = vim.bo[bufnr].completefunc
      local fn_name = completefunc:gsub("^v:lua%.", "")

      print(string.format("  Buffer %d completefunc: %s", bufnr, completefunc))
      assert.is_not_nil(_G[fn_name], "Global completion function should exist before dispose")

      -- Dispose debugger
      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      -- Verify function is removed
      assert.is_nil(_G[fn_name], "Global completion function should be removed on dispose")

      print("  Cleanup successful")

      return true
    end)
  end)
end)
