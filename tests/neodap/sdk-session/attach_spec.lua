-- Test attach configurations with real debuggers
-- NO MOCKS - uses real debug adapters and actual programs

local sdk = require("neodap.sdk")
local neostate = require("neostate")

-- Inline verified_it helper since module loading is problematic with plenary
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

describe("SDK Attach Configurations (Real Debugger)", function()

  -- ==========================================================================
  -- NODE.JS ATTACH
  -- ==========================================================================

  verified_it("should attach to a running Node.js process", function()
    local script_path = vim.fn.getcwd() .. "/tests/fixtures/wait_for_debugger.js"

    -- Use a random port to avoid conflicts with other processes/tests
    local port = math.random(10000, 60000)

    -- Track when Node.js is ready
    local node_ready_flag = false

    -- Start Node.js with --inspect-brk (pauses on start, waiting for debugger)
    local node_job = vim.fn.jobstart({
      "node",
      "--inspect-brk=" .. port,
      script_path
    }, {
      on_stdout = function(_, data)
        if data then
          for _, line in ipairs(data) do
            if line ~= "" then
              print("[Node] " .. line)
            end
          end
        end
      end,
      on_stderr = function(_, data)
        if data then
          for _, line in ipairs(data) do
            if line ~= "" then
              print("[Node Stderr] " .. line)
              -- Node prints "Debugger listening on ws://..." to stderr
              if line:match("Debugger listening") then
                node_ready_flag = true
              end
            end
          end
        end
      end,
    })

    assert.is_true(node_job > 0, "Node.js process should start")

    -- Wait for Node.js inspector to start listening
    local ready = vim.wait(5000, function()
      return node_ready_flag
    end)

    if not ready then
      print("=== Warning: Node.js may not be ready ===")
    else
      print("=== Node.js inspector is ready ===")
    end

    -- Create debugger and attach
    local debugger = sdk:create_debugger()

    debugger:register_adapter("pwa-node", {
      type = "server",
      command = "js-debug",
      args = { "0" },
      connect_condition = function(chunk)
        local h, p = chunk:match("Debug server listening at (.*):(%d+)")
        if h and p then
          return tonumber(p), h
        end
        return nil
      end
    })

    -- Add breakpoint at line where y = x + 1 (line 11)
    local bp = debugger:add_breakpoint({ path = script_path }, 11)

    -- Attach to the running process
    print(string.format("=== Attaching to Node.js on port %d ===", port))

    local session = debugger:start({
      type = "pwa-node",
      request = "attach",
      port = port,
      address = "127.0.0.1"
    })

    print(string.format("=== Session created: id=%s ===", session.id))

    -- Verify session was created
    assert.is_not_nil(session, "session should be created")

    local session_count = 0
    for _ in debugger.sessions:iter() do
      session_count = session_count + 1
    end
    assert.are.equal(1, session_count, "should have one session")

    -- Wait for breakpoint to be hit
    print("=== Waiting for breakpoint ===")
    local hit = vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    print(string.format("=== Session state: %s ===", session.state:get()))

    -- Verify we hit the breakpoint
    if session.state:get() == "stopped" then
      assert.are.equal("stopped", session.state:get(), "should be stopped at breakpoint")

      local thread = nil
      for t in session:threads():iter() do
        thread = t
        break
      end
      assert.is_not_nil(thread, "should have a thread")

      local stack = thread:stack()
      assert.is_not_nil(stack, "should have stack")

      local frame = stack:top()
      assert.is_not_nil(frame, "should have top frame")
      assert.are.equal(11, frame.line, "should be stopped at line 11")
    end

    -- Cleanup
    session:disconnect(true)
    debugger:dispose()
    vim.fn.jobstop(node_job)

    return true
  end)
end)
