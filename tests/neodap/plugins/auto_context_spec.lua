local sdk = require("neodap.sdk")
local auto_context = require("neodap.plugins.auto_context")

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

-- =============================================================================
-- Tests
-- =============================================================================

describe("AutoContext Plugin", function()

  describe("with Python debugger", function()
    local debugger, cleanup, session, script_path

    local function setup_debug_session()
      debugger = sdk:create_debugger()
      cleanup = auto_context(debugger)

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
      vim.cmd("bufdo bwipeout!")
    end

    async_test("uses buffer-local context (not global)", function()
      setup_debug_session()

      -- Open the script file (triggers BufEnter)
      vim.cmd.edit(script_path)
      local bufnr = vim.api.nvim_get_current_buf()
      wait(200)

      -- Buffer context should be pinned
      local buf_ctx = debugger:context(bufnr)
      assert.is_truthy(buf_ctx:is_pinned())

      local frame_uri = buf_ctx.frame_uri:get()
      assert.is_truthy(frame_uri)
      assert.is_truthy(frame_uri:match("frame:"))

      teardown()
      return true
    end)

    async_test("entering file without frames unpins buffer context", function()
      setup_debug_session()

      -- First pin context by entering script file
      vim.cmd.edit(script_path)
      local script_bufnr = vim.api.nvim_get_current_buf()
      wait(200)

      local script_ctx = debugger:context(script_bufnr)
      assert.is_truthy(script_ctx:is_pinned())

      -- Now open a different file with no frames
      local other_file = vim.fn.fnamemodify("tests/minimal_init.lua", ":p")
      vim.cmd.edit(other_file)
      local other_bufnr = vim.api.nvim_get_current_buf()
      wait(200)

      -- Other buffer's context should NOT be pinned
      local other_ctx = debugger:context(other_bufnr)
      assert.is_falsy(other_ctx:is_pinned())

      -- Original buffer's context should STILL be pinned (isolation!)
      assert.is_truthy(script_ctx:is_pinned())

      teardown()
      return true
    end)

    async_test("stays sticky when moving cursor on same line", function()
      setup_debug_session()

      -- Open the script file
      vim.cmd.edit(script_path)
      local bufnr = vim.api.nvim_get_current_buf()
      wait(200)

      local ctx = debugger:context(bufnr)
      local initial_uri = ctx.frame_uri:get()
      assert.is_truthy(initial_uri)

      -- Get the pinned line
      local initial_line = vim.api.nvim_win_get_cursor(0)[1]

      -- Move cursor to different column on SAME line
      vim.api.nvim_win_set_cursor(0, { initial_line, 5 })
      wait(200)

      -- Should stay sticky - same URI
      assert.equals(initial_uri, ctx.frame_uri:get())

      teardown()
      return true
    end)

    async_test("stays sticky when moving to line without frames", function()
      setup_debug_session()

      -- Open the script file
      vim.cmd.edit(script_path)
      local bufnr = vim.api.nvim_get_current_buf()
      wait(200)

      local ctx = debugger:context(bufnr)
      local initial_uri = ctx.frame_uri:get()
      assert.is_truthy(initial_uri)

      -- Move cursor to line 1 (likely no frame there)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      wait(200)

      -- Should stay sticky - same URI (no frame at line 1)
      assert.equals(initial_uri, ctx.frame_uri:get())

      teardown()
      return true
    end)

    async_test("frame changes trigger context update", function()
      setup_debug_session()

      local thread = session:threads():iter()()
      local stack = thread:stack()
      local top = stack:top()

      -- Open the script file
      vim.cmd.edit(script_path)
      local bufnr = vim.api.nvim_get_current_buf()
      wait(200)

      local ctx = debugger:context(bufnr)
      local initial_uri = ctx.frame_uri:get()
      assert.is_truthy(initial_uri)

      -- Step to create new frame
      thread:step_over()
      wait(5000, function() return session.state:get() == "stopped" end)
      wait(200) -- Wait for reactive update

      -- Context should be updated
      assert.is_truthy(ctx:is_pinned())

      teardown()
      return true
    end)

    async_test("each buffer maintains independent context", function()
      setup_debug_session()

      -- Open the script file
      vim.cmd.edit(script_path)
      local script_bufnr = vim.api.nvim_get_current_buf()
      wait(200)

      local script_ctx = debugger:context(script_bufnr)
      local script_uri = script_ctx.frame_uri:get()
      assert.is_truthy(script_uri)

      -- Open another file (no frames)
      local other_file = vim.fn.fnamemodify("tests/minimal_init.lua", ":p")
      vim.cmd.edit(other_file)
      local other_bufnr = vim.api.nvim_get_current_buf()
      wait(200)

      local other_ctx = debugger:context(other_bufnr)

      -- Both contexts should exist independently
      assert.is_truthy(script_ctx:is_pinned())
      assert.is_falsy(other_ctx:is_pinned())

      -- Script buffer's URI should be unchanged
      assert.equals(script_uri, script_ctx.frame_uri:get())

      teardown()
      return true
    end)
  end)

  describe("cleanup", function()
    it("removes autocmds on cleanup", function()
      local debugger = sdk:create_debugger()
      local cleanup = auto_context(debugger)

      -- Verify augroup exists
      local ok = pcall(vim.api.nvim_get_autocmds, { group = "DapAutoContext" })
      assert.is_true(ok)

      cleanup()

      -- Verify augroup is removed
      ok = pcall(vim.api.nvim_get_autocmds, { group = "DapAutoContext" })
      assert.is_false(ok)

      debugger:dispose()
    end)

    it("cleans up on debugger dispose", function()
      local debugger = sdk:create_debugger()
      auto_context(debugger)

      -- Verify augroup exists
      local ok = pcall(vim.api.nvim_get_autocmds, { group = "DapAutoContext" })
      assert.is_true(ok)

      debugger:dispose()

      -- Verify augroup is removed
      ok = pcall(vim.api.nvim_get_autocmds, { group = "DapAutoContext" })
      assert.is_false(ok)
    end)
  end)
end)
