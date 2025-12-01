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

describe("exception_highlight plugin", function()
  describe("highlight behavior", function()
    verified_it("should create red highlight on exception stop", function()
      local debugger = sdk:create_debugger()

      -- Register adapter with 'all' exceptions filter
      debugger:register_adapter("pwa-node", {
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
          local h, p = chunk:match("Debug server listening at (.*):(%d+)")
          return tonumber(p), h
        end,
        exceptionFilters = {
          { filter = "all", label = "All Exceptions", default = true },
        }
      })

      -- Load exception_highlight plugin
      require("neodap.plugins.exception_highlight")(debugger)

      local script_path = vim.fn.fnamemodify("tests/fixtures/caught_exception_test.js", ":p")

      print("\n=== EXCEPTION HIGHLIGHT TEST ===")

      -- Open the file in a buffer first (plugin needs buffer to highlight)
      vim.cmd("edit " .. script_path)
      local bufnr = vim.fn.bufnr(script_path)
      assert.is_true(bufnr > 0, "Buffer should be opened")

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      -- Wait for child session
      local session = wait_for_child_session(bootstrap)
      if not session then
        error("No child session created")
      end

      -- Wait for exception stop
      local exception_stopped = false
      vim.wait(15000, function()
        if session.state:get() == "stopped" then
          for thread in session:threads():iter() do
            if thread:stoppedOnException() then
              exception_stopped = true
              return true
            end
          end
        end
        return session.state:get() == "terminated"
      end)

      assert.is_true(exception_stopped, "Should stop on exception")

      -- Give plugin time to set highlight
      vim.wait(500)

      -- Check for extmark in namespace
      local ns = vim.api.nvim_create_namespace("dap_exception_highlight")
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

      print(string.format("  Found %d extmarks", #extmarks))
      assert.is_true(#extmarks > 0, "Should have exception highlight extmark")

      -- Check extmark is on line 5 (0-indexed = 4)
      local extmark = extmarks[1]
      local line = extmark[2]
      print(string.format("  Extmark on line %d", line + 1))
      assert.equals(4, line, "Extmark should be on line 5 (0-indexed: 4)")

      -- Check extmark has virtual text
      local details = extmark[4]
      assert.is_not_nil(details.virt_text, "Should have virtual text")
      print(string.format("  Virtual text: %s", vim.inspect(details.virt_text)))

      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)

    verified_it("should clear highlight when thread resumes", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("pwa-node", {
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
          local h, p = chunk:match("Debug server listening at (.*):(%d+)")
          return tonumber(p), h
        end,
        exceptionFilters = {
          { filter = "all", label = "All Exceptions", default = true },
        }
      })

      require("neodap.plugins.exception_highlight")(debugger)

      local script_path = vim.fn.fnamemodify("tests/fixtures/caught_exception_test.js", ":p")

      print("\n=== EXCEPTION HIGHLIGHT CLEAR TEST ===")

      vim.cmd("edit " .. script_path)
      local bufnr = vim.fn.bufnr(script_path)

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      local session = wait_for_child_session(bootstrap)
      if not session then
        error("No child session created")
      end

      -- Wait for first exception stop
      vim.wait(15000, function()
        if session.state:get() == "stopped" then
          for thread in session:threads():iter() do
            if thread:stoppedOnException() then
              return true
            end
          end
        end
        return false
      end)

      -- Give plugin time
      vim.wait(500)

      local ns = vim.api.nvim_create_namespace("dap_exception_highlight")
      local extmarks_before = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      print(string.format("  Extmarks before continue: %d", #extmarks_before))
      assert.is_true(#extmarks_before > 0, "Should have highlight before continue")

      -- Continue execution
      session:continue()

      -- Wait for either second exception or termination
      vim.wait(10000, function()
        return session.state:get() == "stopped" or session.state:get() == "terminated" or bootstrap.state:get() == "terminated"
      end)

      -- Give plugin time to update
      vim.wait(500)

      -- Check highlight was cleared (if terminated) or still present (if stopped on second exception)
      local extmarks_after = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      print(string.format("  Extmarks after continue: %d", #extmarks_after))
      print(string.format("  Session state: %s", session.state:get()))

      -- If stopped on second exception, highlight should still be there
      -- If terminated, highlight should be cleared
      if session.state:get() == "stopped" then
        assert.is_true(#extmarks_after > 0, "Should have highlight for second exception")
      end

      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      -- After dispose, all highlights should be cleared
      vim.wait(500)
      local extmarks_final = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      print(string.format("  Extmarks after dispose: %d", #extmarks_final))
      assert.equals(0, #extmarks_final, "Should clear all highlights on dispose")

      return true
    end)

    verified_it("should show exception message in virtual text", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("pwa-node", {
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
          local h, p = chunk:match("Debug server listening at (.*):(%d+)")
          return tonumber(p), h
        end,
        exceptionFilters = {
          { filter = "all", label = "All Exceptions", default = true },
        }
      })

      require("neodap.plugins.exception_highlight")(debugger)

      local script_path = vim.fn.fnamemodify("tests/fixtures/caught_exception_test.js", ":p")

      print("\n=== EXCEPTION MESSAGE TEST ===")

      vim.cmd("edit " .. script_path)
      local bufnr = vim.fn.bufnr(script_path)

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      local session = wait_for_child_session(bootstrap)
      if not session then
        error("No child session created")
      end

      -- Wait for exception stop
      vim.wait(15000, function()
        if session.state:get() == "stopped" then
          for thread in session:threads():iter() do
            if thread:stoppedOnException() then
              return true
            end
          end
        end
        return session.state:get() == "terminated"
      end)

      vim.wait(500)

      local ns = vim.api.nvim_create_namespace("dap_exception_highlight")
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

      assert.is_true(#extmarks > 0, "Should have extmark")

      local details = extmarks[1][4]
      assert.is_not_nil(details.virt_text, "Should have virtual text")

      -- Virtual text should contain the error message
      local virt_text_str = details.virt_text[1][1]
      print(string.format("  Virtual text content: %s", virt_text_str))

      -- The message should contain "Value cannot be zero" or similar
      local has_message = virt_text_str:match("Value") or virt_text_str:match("Error")
      assert.is_truthy(has_message, "Virtual text should contain exception message")

      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)

  describe("non-exception stops", function()
    verified_it("should not highlight on breakpoint stops", function()
      local debugger = sdk:create_debugger()

      debugger:register_adapter("pwa-node", {
        type = "server",
        command = "js-debug",
        args = { "0" },
        connect_condition = function(chunk)
          local h, p = chunk:match("Debug server listening at (.*):(%d+)")
          return tonumber(p), h
        end,
        exceptionFilters = {
          { filter = "all", label = "All Exceptions", default = false },  -- Disabled
        }
      })

      require("neodap.plugins.exception_highlight")(debugger)

      local script_path = vim.fn.fnamemodify("tests/fixtures/caught_exception_test.js", ":p")

      print("\n=== NO HIGHLIGHT ON BREAKPOINT TEST ===")

      vim.cmd("edit " .. script_path)
      local bufnr = vim.fn.bufnr(script_path)

      -- Set breakpoint before exception
      debugger:add_breakpoint({ path = script_path }, 14)

      local bootstrap = debugger:start({
        type = "pwa-node",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      local session = wait_for_child_session(bootstrap)
      if not session then
        error("No child session created")
      end

      -- Wait for breakpoint stop
      vim.wait(15000, function()
        return session.state:get() == "stopped"
      end)

      -- Verify it's a breakpoint stop, not exception
      local is_exception = false
      for thread in session:threads():iter() do
        if thread:stoppedOnException() then
          is_exception = true
        end
      end
      assert.is_false(is_exception, "Should not be exception stop")

      vim.wait(500)

      -- Check no exception highlight
      local ns = vim.api.nvim_create_namespace("dap_exception_highlight")
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})

      print(string.format("  Extmarks on breakpoint: %d", #extmarks))
      assert.equals(0, #extmarks, "Should not have exception highlight on breakpoint")

      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()

      return true
    end)
  end)
end)
