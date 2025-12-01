-- Test concurrent debug sessions sharing the same adapter

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

describe("Concurrent Debug Sessions", function()
  verified_it("should run two sessions on different files with separate adapters", function()
    local debugger = sdk:create_debugger()

    -- Register Python adapter (like other working tests)
    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local file_a = vim.fn.fnamemodify("./tests/fixtures/concurrent_a.py", ":p")
    local file_b = vim.fn.fnamemodify("./tests/fixtures/concurrent_b.py", ":p")

    -- Add breakpoints to both files (line 4 = result = ...)
    debugger:add_breakpoint({ path = file_a }, 4)
    debugger:add_breakpoint({ path = file_b }, 4)

    -- Auto-fetch stack when threads stop
    debugger:onSession(function(session)
      session:onThread(function(thread)
        thread:onStopped(function()
          neostate.void(function()
            thread:stack()
          end)()
        end)
      end)
    end)

    -- Start first session
    local session_a = debugger:start({
      type = "python",
      request = "launch",
      name = "Session A",
      program = file_a,
      console = "internalConsole",
    })

    -- Start second session
    local session_b = debugger:start({
      type = "python",
      request = "launch",
      name = "Session B",
      program = file_b,
      console = "internalConsole",
    })

    -- Each session has its own adapter (separate debugpy instances)
    assert.are_not.equal(session_a.adapter, session_b.adapter, "Sessions should have separate adapters")

    -- Wait for both sessions to stop at breakpoints
    local both_stopped = vim.wait(15000, function()
      return session_a.state:get() == "stopped" and session_b.state:get() == "stopped"
    end, 100)

    if not both_stopped then
      print("Session A state: " .. session_a.state:get())
      print("Session B state: " .. session_b.state:get())
    end

    assert.are.equal("stopped", session_a.state:get(), "Session A should be stopped")
    assert.are.equal("stopped", session_b.state:get(), "Session B should be stopped")

    -- Verify session A stopped at correct file
    local thread_a = nil
    for t in session_a:threads():iter() do
      thread_a = t
      break
    end
    assert(thread_a, "Session A should have a thread")

    local stack_a = thread_a:stack()
    local frame_a = stack_a:top()
    assert(frame_a, "Session A should have a top frame")
    assert.are.equal(4, frame_a.line, "Session A should be at line 4")
    assert(frame_a.source.path:match("concurrent_a.py"), "Session A should be in concurrent_a.py")

    -- Verify session B stopped at correct file
    local thread_b = nil
    for t in session_b:threads():iter() do
      thread_b = t
      break
    end
    assert(thread_b, "Session B should have a thread")

    local stack_b = thread_b:stack()
    local frame_b = stack_b:top()
    assert(frame_b, "Session B should have a top frame")
    assert.are.equal(4, frame_b.line, "Session B should be at line 4")
    assert(frame_b.source.path:match("concurrent_b.py"), "Session B should be in concurrent_b.py")

    -- Continue both sessions
    session_a.client:request("continue", { threadId = thread_a.id })
    session_b.client:request("continue", { threadId = thread_b.id })

    -- Wait for both to terminate
    vim.wait(5000, function()
      return session_a.state:get() == "terminated" and session_b.state:get() == "terminated"
    end, 100)

    -- Cleanup
    debugger:dispose()

    return true
  end)

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

  verified_it("should run two js-debug sessions on different files", function()
    local debugger = sdk:create_debugger()

    -- Register js-debug adapter
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

    local file_a = vim.fn.fnamemodify("./tests/fixtures/concurrent_a.js", ":p")
    local file_b = vim.fn.fnamemodify("./tests/fixtures/concurrent_b.js", ":p")

    -- Add breakpoints to both files (line 4 = const result = ...)
    debugger:add_breakpoint({ path = file_a }, 4)
    debugger:add_breakpoint({ path = file_b }, 4)

    -- Auto-fetch stack when threads stop
    debugger:onSession(function(session)
      session:onThread(function(thread)
        thread:onStopped(function()
          neostate.void(function()
            thread:stack()
          end)()
        end)
      end)
    end)

    -- Start first bootstrap session
    local bootstrap_a = debugger:start({
      type = "pwa-node",
      request = "launch",
      name = "Session A",
      program = file_a,
      console = "internalConsole",
    })

    -- Start second bootstrap session
    local bootstrap_b = debugger:start({
      type = "pwa-node",
      request = "launch",
      name = "Session B",
      program = file_b,
      console = "internalConsole",
    })

    -- Each bootstrap has its own adapter (separate js-debug instances)
    assert.are_not.equal(bootstrap_a.adapter, bootstrap_b.adapter, "Bootstrap sessions should have separate adapters")

    -- js-debug creates child sessions for actual debugging
    local session_a = wait_for_child_session(bootstrap_a)
    local session_b = wait_for_child_session(bootstrap_b)

    assert(session_a, "Bootstrap A should have a child session")
    assert(session_b, "Bootstrap B should have a child session")

    -- Wait for both child sessions to stop at breakpoints
    local both_stopped = vim.wait(15000, function()
      return session_a.state:get() == "stopped" and session_b.state:get() == "stopped"
    end, 100)

    if not both_stopped then
      print("Session A state: " .. session_a.state:get())
      print("Session B state: " .. session_b.state:get())
    end

    assert.are.equal("stopped", session_a.state:get(), "Session A should be stopped")
    assert.are.equal("stopped", session_b.state:get(), "Session B should be stopped")

    -- Verify session A stopped at correct file
    local thread_a = nil
    for t in session_a:threads():iter() do
      thread_a = t
      break
    end
    assert(thread_a, "Session A should have a thread")

    local stack_a = thread_a:stack()
    local frame_a = stack_a:top()
    assert(frame_a, "Session A should have a top frame")
    assert.are.equal(4, frame_a.line, "Session A should be at line 4")
    assert(frame_a.source.path:match("concurrent_a.js"), "Session A should be in concurrent_a.js")

    -- Verify session B stopped at correct file
    local thread_b = nil
    for t in session_b:threads():iter() do
      thread_b = t
      break
    end
    assert(thread_b, "Session B should have a thread")

    local stack_b = thread_b:stack()
    local frame_b = stack_b:top()
    assert(frame_b, "Session B should have a top frame")
    assert.are.equal(4, frame_b.line, "Session B should be at line 4")
    assert(frame_b.source.path:match("concurrent_b.js"), "Session B should be in concurrent_b.js")

    -- Continue both sessions
    session_a.client:request("continue", { threadId = thread_a.id })
    session_b.client:request("continue", { threadId = thread_b.id })

    -- Wait for both bootstrap sessions to terminate
    vim.wait(5000, function()
      return bootstrap_a.state:get() == "terminated" and bootstrap_b.state:get() == "terminated"
    end, 100)

    -- Cleanup
    debugger:dispose()

    return true
  end)
end)
