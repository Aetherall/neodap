local sdk = require("neodap.sdk")
local neostate = require("neostate")

-- Counter for unique URIs per test
local test_counter = 0

-- Helper to get a unique URI for each test to avoid buffer reuse
local function unique_eval_uri(base)
  test_counter = test_counter + 1
  base = base or "@frame"
  return string.format("dap-eval:%s?test=%d", base, test_counter)
end

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

describe("eval_buffer plugin", function()
  describe("URI parsing", function()
    verified_it("should open dap-eval:@frame buffer", function()
      local debugger = sdk:create_debugger()

      -- Register Python adapter
      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      -- Load plugins
      require("neodap.plugins.auto_context")(debugger)
      require("neodap.plugins.eval_buffer")(debugger)

      local script_path = vim.fn.fnamemodify("tests/fixtures/stepping_test.py", ":p")

      print("\n=== EVAL BUFFER URI TEST ===")

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

      -- Use unique URI to avoid buffer conflicts
      local uri = unique_eval_uri("@frame")
      vim.cmd("edit " .. uri)
      local bufnr = vim.fn.bufnr(uri)

      assert.is_true(bufnr > 0, "Buffer should be opened")

      -- Check buffer options
      assert.equals("nofile", vim.bo[bufnr].buftype, "Should be nofile buftype")
      assert.is_false(vim.bo[bufnr].swapfile, "Should have swapfile disabled")
      assert.is_true(vim.bo[bufnr].modifiable, "Should be modifiable")

      -- Check frame pattern stored
      assert.equals("@frame", vim.b[bufnr].dap_eval_frame_pattern, "Should store frame pattern")

      print("  Buffer opened successfully with correct options")

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("should parse closeonsubmit query param", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      require("neodap.plugins.auto_context")(debugger)
      require("neodap.plugins.eval_buffer")(debugger)

      local script_path = vim.fn.fnamemodify("tests/fixtures/stepping_test.py", ":p")

      print("\n=== EVAL BUFFER QUERY PARAM TEST ===")

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

      -- Use unique URI with closeonsubmit
      local uri = unique_eval_uri("@frame") .. "&closeonsubmit"
      vim.cmd("edit " .. uri)
      local bufnr = vim.fn.bufnr(uri)

      assert.is_true(bufnr > 0, "Buffer should be opened")
      assert.is_true(vim.b[bufnr].dap_eval_close_on_submit, "Should have closeonsubmit set")

      print("  Query param parsed correctly")

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)

  describe("completions", function()
    verified_it("should set completefunc on eval buffer", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      require("neodap.plugins.auto_context")(debugger)
      require("neodap.plugins.eval_buffer")(debugger)

      local script_path = vim.fn.fnamemodify("tests/fixtures/stepping_test.py", ":p")

      print("\n=== EVAL BUFFER COMPLETEFUNC TEST ===")

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

      -- Use unique URI
      local uri = unique_eval_uri("@frame")
      vim.cmd("edit " .. uri)
      local bufnr = vim.fn.bufnr(uri)

      -- Check completefunc is set
      local completefunc = vim.bo[bufnr].completefunc
      print(string.format("  completefunc: %s", completefunc))

      assert.is_true(completefunc:match("^v:lua%._dap_eval_complete_%d+$") ~= nil,
        "Should have completefunc set to v:lua._dap_eval_complete_<bufnr>")

      -- Verify the global function exists
      local fn_name = completefunc:gsub("^v:lua%.", "")
      assert.is_not_nil(_G[fn_name], "Global completion function should exist")

      print("  Completefunc set correctly")

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)

  describe("submit", function()
    verified_it("should call on_submit callback when expression is submitted", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      -- Track on_submit calls
      local submitted = nil

      require("neodap.plugins.auto_context")(debugger)
      require("neodap.plugins.eval_buffer")(debugger, {
        on_submit = function(expression, frame, result, err)
          submitted = {
            expression = expression,
            frame = frame,
            result = result,
            err = err,
          }
        end,
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/stepping_test.py", ":p")

      print("\n=== EVAL BUFFER SUBMIT TEST ===")

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

      -- Step to get local variables
      local thread = nil
      for t in session:threads():iter() do
        thread = t
        break
      end
      thread:step_over()

      vim.wait(10000, function()
        return session.state:get() == "stopped"
      end)

      -- Use unique URI
      local uri = unique_eval_uri("@frame")
      vim.cmd("edit " .. uri)
      local bufnr = vim.fn.bufnr(uri)

      -- Type an expression
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "1 + 1" })

      -- Find and execute the <CR> callback directly (more reliable in headless tests)
      local cr_callback = nil
      local maps = vim.api.nvim_buf_get_keymap(bufnr, "n")
      for _, map in ipairs(maps) do
        if map.lhs == "<CR>" then
          cr_callback = map.callback
          break
        end
      end
      assert.is_not_nil(cr_callback, "Should have <CR> keymap with callback")

      -- Execute the submit callback
      vim.api.nvim_buf_call(bufnr, function()
        cr_callback()
      end)

      -- Wait for callback (increase wait time for async operations)
      vim.wait(10000, function()
        return submitted ~= nil
      end, 100)

      assert.is_not_nil(submitted, "Should have called on_submit")
      assert.equals("1 + 1", submitted.expression, "Should pass expression")
      assert.is_not_nil(submitted.frame, "Should pass frame")
      print(string.format("  Expression: %s", submitted.expression))
      print(string.format("  Result: %s", submitted.result and submitted.result.result or "nil"))

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("should close buffer when closeonsubmit is set", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      require("neodap.plugins.auto_context")(debugger)
      require("neodap.plugins.eval_buffer")(debugger)

      local script_path = vim.fn.fnamemodify("tests/fixtures/stepping_test.py", ":p")

      print("\n=== EVAL BUFFER CLOSE ON SUBMIT TEST ===")

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

      -- Use unique URI with closeonsubmit
      local uri = unique_eval_uri("@frame") .. "&closeonsubmit"
      vim.cmd("edit " .. uri)
      local bufnr = vim.fn.bufnr(uri)

      assert.is_true(vim.api.nvim_buf_is_valid(bufnr), "Buffer should be valid before submit")

      -- Type an expression and submit
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "1" })

      -- Find and execute the <CR> callback directly
      local cr_callback = nil
      local maps = vim.api.nvim_buf_get_keymap(bufnr, "n")
      for _, map in ipairs(maps) do
        if map.lhs == "<CR>" and map.callback then
          cr_callback = map.callback
          break
        end
      end
      assert.is_not_nil(cr_callback, "Should have <CR> keymap with callback")

      vim.api.nvim_buf_call(bufnr, function()
        cr_callback()
      end)

      -- Wait a bit for buffer deletion
      vim.wait(1000, function()
        return not vim.api.nvim_buf_is_valid(bufnr)
      end)

      assert.is_false(vim.api.nvim_buf_is_valid(bufnr), "Buffer should be deleted after submit")

      print("  Buffer closed on submit")

      session:disconnect(true)
      vim.wait(2000, function() return session.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)

  describe("cleanup", function()
    verified_it("should remove completion functions on dispose", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" },
      })

      require("neodap.plugins.auto_context")(debugger)
      require("neodap.plugins.eval_buffer")(debugger)

      local script_path = vim.fn.fnamemodify("tests/fixtures/stepping_test.py", ":p")

      print("\n=== EVAL BUFFER CLEANUP TEST ===")

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

      -- Use unique URI
      local uri = unique_eval_uri("@frame")
      vim.cmd("edit " .. uri)
      local bufnr = vim.fn.bufnr(uri)

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

  describe("js-debug completions", function()
    -- Helper to wait for js-debug child session (js-debug uses bootstrap/child pattern)
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

    verified_it("should get expression completions from js-debug", function()
      local debugger = sdk:create_debugger()

      -- Register js-debug adapter
      debugger:register_adapter("pwa-node", {
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
          local h, p = chunk:match("Debug server listening at (.*):(%d+)")
          return tonumber(p), h
        end,
      })

      require("neodap.plugins.auto_context")(debugger)
      require("neodap.plugins.eval_buffer")(debugger)

      local script_path = vim.fn.fnamemodify("tests/fixtures/stepping_test.js", ":p")

      print("\n=== JS-DEBUG COMPLETIONS TEST ===")

      debugger:add_breakpoint({ path = script_path }, 12)

      -- Start returns the bootstrap session
      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- js-debug creates a child session for actual debugging
      print("  Waiting for child session...")
      local session = wait_for_child_session(bootstrap)
      assert.is_not_nil(session, "Should have child session")
      print("  Got child session")

      -- Wait for stopped state on the child session
      vim.wait(15000, function()
        return session.state:get() == "stopped"
      end, 100)
      assert.equals("stopped", session.state:get(), "Session should be stopped")

      -- Check capabilities
      local supports_completions = session.capabilities and session.capabilities.supportsCompletionsRequest
      print(string.format("  js-debug supportsCompletionsRequest: %s", tostring(supports_completions)))

      -- Wait for thread to appear
      local thread = nil
      vim.wait(5000, function()
        for t in session:threads():iter() do
          if t.state:get() == "stopped" then
            thread = t
            return true
          end
        end
        return false
      end, 100)
      assert.is_not_nil(thread, "Should have stopped thread")

      local stack = thread:stack()
      local frame = stack:top()
      assert.is_not_nil(frame, "Should have frame")
      print(string.format("  Frame ID: %d", frame.id))

      -- Test completions with different inputs
      local test_cases = {
        { text = "val", column = 4, desc = "partial variable name" },
        { text = "value", column = 6, desc = "full variable name" },
        { text = "value.", column = 7, desc = "property access" },
        { text = "console.", column = 9, desc = "global object property" },
        { text = "", column = 1, desc = "empty input" },
      }

      for _, tc in ipairs(test_cases) do
        print(string.format("\n  Testing '%s' (column %d) - %s:", tc.text, tc.column, tc.desc))

        local body, err = neostate.settle(session.client:request("completions", {
          text = tc.text,
          column = tc.column,
          frameId = frame.id,
        }))

        if err then
          print(string.format("    Error: %s", tostring(err)))
        elseif body and body.targets then
          print(string.format("    Got %d completions", #body.targets))
          for i, target in ipairs(body.targets) do
            if i <= 5 then  -- Show first 5
              print(string.format("      [%d] label='%s', text='%s', type=%s",
                i, target.label or "", target.text or "", target.type or "nil"))
            end
          end
          if #body.targets > 5 then
            print(string.format("      ... and %d more", #body.targets - 5))
          end
        else
          print("    No completions")
        end
      end

      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)
end)
