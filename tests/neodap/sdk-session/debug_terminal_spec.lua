-- Test JavaScript Debug Terminal functionality
-- Uses pwa-node with runtimeExecutable=bash and console=integratedTerminal
-- js-debug sends runInTerminal with NODE_OPTIONS containing the bootloader
-- When user runs node commands, js-debug sends startDebugging for child sessions

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

describe("JavaScript Debug Terminal", function()
  verified_it("should auto-debug node processes started in debug terminal", function()
    local debugger = sdk:create_debugger()

    -- Register pwa-node adapter (js-debug handles node-terminal internally)
    debugger:register_adapter("pwa-node", {
      type = "server",
      command = "js-debug",
      args = { "0" },
      connect_condition = function(chunk)
        local h, p = chunk:match("Debug server listening at (.*):(%d+)")
        if h and p then return tonumber(p), h end
        return nil
      end
    })

    local test_file = vim.fn.fnamemodify("./tests/fixtures/simple_node.js", ":p")

    -- Add breakpoint BEFORE starting terminal (so child session will have it)
    debugger:add_breakpoint({ path = test_file }, 4) -- line: const x = 42

    -- Start debug terminal using pwa-node with integratedTerminal console
    -- We pass runtimeExecutable which js-debug uses as the shell to run
    local root_session = debugger:start({
      type = "pwa-node",
      request = "launch",
      name = "Test Debug Terminal",
      -- Use runtimeExecutable to specify what to run (bash as shell)
      runtimeExecutable = "bash",
      -- No program - we want just a shell
      console = "integratedTerminal",
      cwd = vim.fn.getcwd(),
    })

    -- Wait for terminal buffer to appear
    local term_buf = nil
    vim.wait(5000, function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match("Test Debug Terminal") then
          term_buf = buf
          return true
        end
      end
      return false
    end, 100)

    assert(term_buf, "Terminal buffer should be created")

    -- Get terminal job channel
    local ok, channel = pcall(vim.api.nvim_buf_get_var, term_buf, "terminal_job_id")
    if not ok then
      -- Try alternative method
      for _, chan in ipairs(vim.api.nvim_list_chans()) do
        if chan.buffer == term_buf then
          channel = chan.id
          break
        end
      end
    end

    assert(channel, "Should have terminal channel")
    term_chan = channel

    -- Auto-fetch stack when thread stops in any session
    debugger:onSession(function(session)
      session:onThread(function(thread)
        thread:onStopped(function()
          neostate.void(function()
            thread:stack()
          end)()
        end)
      end)
    end)

    -- Send command to run node in the terminal
    vim.fn.chansend(term_chan, "node " .. test_file .. "\n")

    -- Wait for child session to be created and stopped at breakpoint
    local child_session = nil
    vim.wait(15000, function()
      for session in debugger.sessions:iter() do
        if session.parent == root_session and session.state:get() == "stopped" then
          child_session = session
          return true
        end
      end
      return false
    end, 100)

    assert(child_session, "Child session should be created for node process")
    assert.are.equal("stopped", child_session.state:get(), "Child should be stopped at breakpoint")

    -- Verify we have a thread
    local thread = nil
    for t in child_session:threads():iter() do
      thread = t
      break
    end
    assert(thread, "Child session should have a thread")

    -- Verify stack and breakpoint location
    local stack = thread:stack()
    assert(stack, "Should have stack trace")

    local top_frame = stack:top()
    assert(top_frame, "Should have top frame")
    assert.are.equal(4, top_frame.line, "Should be stopped at line 4")

    -- Continue execution so program finishes
    child_session.client:request("continue", { threadId = thread.id })

    -- Wait for child session to terminate
    vim.wait(5000, function()
      return child_session.state:get() == "terminated"
    end, 100)

    -- Cleanup - disconnect root session
    root_session:disconnect(true)
    vim.wait(2000, function()
      return root_session.state:get() == "terminated"
    end, 100)

    debugger:dispose()

    return true
  end)
end)
