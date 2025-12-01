local sdk = require("neodap.sdk")
local dap_breakpoint = require("neodap.plugins.dap_breakpoint")

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

describe("DapBreakpoint Plugin", function()

  describe("with Python debugger", function()
    local debugger, cleanup, session, script_path

    local function setup_debug_session()
      debugger = sdk:create_debugger()
      cleanup = dap_breakpoint(debugger)

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")

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

    async_test("toggle creates breakpoint with adjusted column (fallback to col 1)", function()
      setup_debug_session()

      -- Open the script file and position cursor
      vim.cmd.edit(script_path)
      vim.api.nvim_win_set_cursor(0, { 10, 4 }) -- Line 10, col 4 (0-indexed)
      wait(100)

      -- Toggle breakpoint at cursor
      -- Since debugpy doesn't support breakpointLocations, adjust defaults to col 1
      vim.cmd("DapBreakpoint")
      wait(100)

      -- Check breakpoint was created with adjusted column (col 1)
      local bp = debugger.breakpoints:get_one("by_location", script_path .. ":10:1")
      assert.is_truthy(bp)
      assert.equals(10, bp.line)
      assert.equals(1, bp.column)

      teardown()
      return true
    end)

    async_test("toggle removes breakpoint at adjusted location", function()
      setup_debug_session()

      vim.cmd.edit(script_path)
      vim.api.nvim_win_set_cursor(0, { 10, 4 }) -- col 5 (1-indexed)
      wait(100)

      -- Add breakpoint (adjusted to col 1)
      vim.cmd("DapBreakpoint")
      wait(100)

      local bp = debugger.breakpoints:get_one("by_location", script_path .. ":10:1")
      assert.is_truthy(bp)

      -- Move to different column on same line - adjust will still return col 1
      vim.api.nvim_win_set_cursor(0, { 10, 15 }) -- col 16 (1-indexed)
      wait(100)

      -- Toggle should REMOVE the existing breakpoint at adjusted location (col 1)
      vim.cmd("DapBreakpoint")
      wait(100)

      bp = debugger.breakpoints:get_one("by_location", script_path .. ":10:1")
      assert.is_falsy(bp)

      teardown()
      return true
    end)

    async_test("toggle with line number targets correct line (col 1)", function()
      setup_debug_session()

      vim.cmd.edit(script_path)
      wait(100)

      -- Toggle at line 15 (defaults to col 1)
      vim.cmd("DapBreakpoint 15")
      wait(100)

      local bp = debugger.breakpoints:get_one("by_location", script_path .. ":15:1")
      assert.is_truthy(bp)
      assert.equals(15, bp.line)
      assert.equals(1, bp.column)

      teardown()
      return true
    end)

    async_test("toggle with line:col targets exact position", function()
      setup_debug_session()

      vim.cmd.edit(script_path)
      wait(100)

      -- Toggle at line 12, column 8
      vim.cmd("DapBreakpoint 12:8")
      wait(100)

      local bp = debugger.breakpoints:get_one("by_location", script_path .. ":12:8")
      assert.is_truthy(bp)
      assert.equals(12, bp.line)
      assert.equals(8, bp.column)

      teardown()
      return true
    end)

  end)

  describe("cleanup", function()
    it("removes command on cleanup", function()
      local debugger = sdk:create_debugger()
      local cleanup = dap_breakpoint(debugger)

      -- Verify command exists
      local ok = pcall(vim.cmd, "DapBreakpoint")
      -- Command exists but may error due to no buffer - that's ok

      cleanup()

      -- Verify command is removed
      ok = pcall(vim.api.nvim_get_commands, { builtin = false })
      local commands = vim.api.nvim_get_commands({ builtin = false })
      assert.is_nil(commands.DapBreakpoint)

      debugger:dispose()
    end)

    it("cleans up on debugger dispose", function()
      local debugger = sdk:create_debugger()
      dap_breakpoint(debugger)

      debugger:dispose()

      -- Verify command is removed
      local commands = vim.api.nvim_get_commands({ builtin = false })
      assert.is_nil(commands.DapBreakpoint)
    end)
  end)

  describe("completion", function()
    it("returns subcommands", function()
      local debugger = sdk:create_debugger()
      local cleanup = dap_breakpoint(debugger)

      -- Get completion for DapBreakpoint
      local completions = vim.fn.getcompletion("DapBreakpoint ", "cmdline")

      assert.is_truthy(vim.tbl_contains(completions, "toggle"))
      assert.is_truthy(vim.tbl_contains(completions, "condition"))
      assert.is_truthy(vim.tbl_contains(completions, "log"))
      assert.is_truthy(vim.tbl_contains(completions, "enable"))
      assert.is_truthy(vim.tbl_contains(completions, "disable"))

      cleanup()
      debugger:dispose()
    end)
  end)
end)
