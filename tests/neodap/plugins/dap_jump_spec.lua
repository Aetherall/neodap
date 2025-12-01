local sdk = require("neodap.sdk")
local dap_jump = require("neodap.plugins.dap_jump")

-- =============================================================================
-- Test Helpers
-- =============================================================================

---Wait for condition with timeout
---@param ms number
---@param fn function
local function wait(ms, fn)
  vim.wait(ms, fn or function() return false end, 50)
end

---Run async test in coroutine
local function async_test(name, fn, timeout_ms)
  timeout_ms = timeout_ms or 30000
  return it(name, function()
    local done, err, result = false, nil, nil
    local co = coroutine.create(function()
      local ok, res = pcall(fn)
      if not ok then err = res else result = res end
      done = true
    end)
    coroutine.resume(co)
    assert(vim.wait(timeout_ms, function() return done end, 100),
      string.format("Test '%s' timed out", name))
    if err then error(err) end
    assert(result == true, "Test must return true")
  end)
end

---Get current buffer and cursor position
---@return { bufname: string, line: number, col: number }
local function current_position()
  local bufnr = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  return {
    bufname = vim.api.nvim_buf_get_name(bufnr),
    line = pos[1],
    col = pos[2],
  }
end

-- =============================================================================
-- Tests
-- =============================================================================

describe("DapJump Plugin", function()

  describe("with Python debugger", function()
    local debugger, cleanup, session, script_path

    local function setup_debug_session()
      debugger = sdk:create_debugger()
      cleanup = dap_jump(debugger)

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")
      debugger:add_breakpoint({ path = script_path }, 7)

      session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      wait(10000, function() return session.state:get() == "stopped" end)
    end

    local function teardown()
      session:disconnect(true)
      wait(2000, function() return session.state:get() == "terminated" end)
      cleanup()
      debugger:dispose()
      -- Close all buffers
      vim.cmd("bufdo bwipeout!")
    end

    async_test("@frame jumps to context frame", function()
      setup_debug_session()

      local thread = session:threads():iter()()
      local stack = thread:stack()
      local top = stack:top()

      -- Pin context to top frame
      debugger:context():pin(top.uri)
      wait(100)

      -- Jump to @frame
      vim.cmd("DapJump @frame")
      wait(100)

      local pos = current_position()
      assert.is_truthy(pos.bufname:match("stack_test.py$"))
      assert.equals(top.line, pos.line)

      teardown()
      return true
    end)

    async_test("@stack jumps to stack top frame", function()
      setup_debug_session()

      local thread = session:threads():iter()()
      local stack = thread:stack()
      local top = stack:top()

      -- Pin context to any frame in stack
      debugger:context():pin(top.uri)
      wait(100)

      -- Jump to @stack (should go to top frame)
      vim.cmd("DapJump @stack")
      wait(100)

      local pos = current_position()
      assert.is_truthy(pos.bufname:match("stack_test.py$"))
      assert.equals(top.line, pos.line)

      teardown()
      return true
    end)

    async_test("@thread jumps to thread latest stack top frame", function()
      setup_debug_session()

      local thread = session:threads():iter()()
      local stack = thread:stack()
      local top = stack:top()

      -- Pin context
      debugger:context():pin(top.uri)
      wait(100)

      -- Jump to @thread (should go to thread's latest stack's top frame)
      vim.cmd("DapJump @thread")
      wait(100)

      local pos = current_position()
      assert.is_truthy(pos.bufname:match("stack_test.py$"))
      assert.equals(top.line, pos.line)

      teardown()
      return true
    end)

    async_test("@session jumps to session first thread top frame", function()
      setup_debug_session()

      local thread = session:threads():iter()()
      local stack = thread:stack()
      local top = stack:top()

      -- Pin context
      debugger:context():pin(top.uri)
      wait(100)

      -- Jump to @session (should drill down to first thread's top frame)
      vim.cmd("DapJump @session")
      wait(100)

      local pos = current_position()
      assert.is_truthy(pos.bufname:match("stack_test.py$"))
      assert.equals(top.line, pos.line)

      teardown()
      return true
    end)

    async_test("explicit frame URI jumps correctly", function()
      setup_debug_session()

      local thread = session:threads():iter()()
      local stack = thread:stack()
      local frames = {}
      for f in stack:frames():iter() do frames[#frames + 1] = f end

      assert.is_true(#frames >= 2, "Need 2+ frames")

      -- Pin context to first frame
      debugger:context():pin(frames[1].uri)
      wait(100)

      -- Jump explicitly to second frame by URI
      vim.cmd("DapJump " .. frames[2].uri)
      wait(100)

      local pos = current_position()
      assert.equals(frames[2].line, pos.line)

      teardown()
      return true
    end)
  end)

  describe("error handling", function()
    it("shows error for invalid URI", function()
      local debugger = sdk:create_debugger()
      local cleanup = dap_jump(debugger)

      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.ERROR and msg:match("Could not resolve") then
          notify_called = true
        end
      end

      vim.cmd("DapJump @frame")

      vim.notify = original_notify

      assert.is_true(notify_called)

      cleanup()
      debugger:dispose()
    end)

    async_test("shows error when window has winfixbuf (strategy=error)", function()
      local debugger = sdk:create_debugger()
      local cleanup = dap_jump(debugger, { strategy = "error" })

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")
      debugger:add_breakpoint({ path = script_path }, 7)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      wait(10000, function() return session.state:get() == "stopped" end)

      local thread = session:threads():iter()()
      local stack = thread:stack()
      local top = stack:top()
      debugger:context():pin(top.uri)
      wait(100)

      -- Set winfixbuf on current window
      vim.wo.winfixbuf = true

      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.ERROR and msg:match("winfixbuf") then
          notify_called = true
        end
      end

      vim.cmd("DapJump @frame")

      vim.notify = original_notify
      vim.wo.winfixbuf = false

      assert.is_true(notify_called)

      session:disconnect(true)
      wait(2000, function() return session.state:get() == "terminated" end)
      cleanup()
      debugger:dispose()
      vim.cmd("bufdo bwipeout!")
      return true
    end)

    async_test("silent strategy does not error on winfixbuf", function()
      local debugger = sdk:create_debugger()
      local cleanup = dap_jump(debugger, { strategy = "silent" })

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      local script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")
      debugger:add_breakpoint({ path = script_path }, 7)

      local session = debugger:start({
        type = "python",
        request = "launch",
        program = script_path,
        console = "internalConsole",
      })

      wait(10000, function() return session.state:get() == "stopped" end)

      local thread = session:threads():iter()()
      local stack = thread:stack()
      local top = stack:top()
      debugger:context():pin(top.uri)
      wait(100)

      -- Set winfixbuf on current window
      vim.wo.winfixbuf = true

      local error_called = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.ERROR then
          error_called = true
        end
      end

      vim.cmd("DapJump @frame")

      vim.notify = original_notify
      vim.wo.winfixbuf = false

      -- Silent strategy should NOT show error
      assert.is_false(error_called)

      session:disconnect(true)
      wait(2000, function() return session.state:get() == "terminated" end)
      cleanup()
      debugger:dispose()
      vim.cmd("bufdo bwipeout!")
      return true
    end)
  end)
end)
