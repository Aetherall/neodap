local sdk = require("neodap.sdk")
local frame_highlights = require("neodap.plugins.frame_highlights")

-- =============================================================================
-- Test Helpers
-- =============================================================================

local ns_name = "dap_frame_highlights"

---Get highlight at a specific line in buffer
---@param bufnr number
---@param line number 1-indexed line number
---@return string? hl_group
local function highlight_at(bufnr, line)
  local ns = vim.api.nvim_create_namespace(ns_name)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { line - 1, 0 }, { line - 1, -1 }, { details = true })
  -- Plugin uses column-based hl_group, not line_hl_group
  return marks[1] and marks[1][4].hl_group or nil
end

---Get all highlights in buffer as { line = hl_group }
---@param bufnr number
---@return table<number, string>
local function highlights_in(bufnr)
  local ns = vim.api.nvim_create_namespace(ns_name)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  local result = {}
  for _, mark in ipairs(marks) do
    -- Plugin uses column-based hl_group, not line_hl_group
    result[mark[2] + 1] = mark[4].hl_group  -- Convert to 1-indexed
  end
  return result
end

---Count highlights in buffer
---@param bufnr number
---@return number
local function highlight_count(bufnr)
  local ns = vim.api.nvim_create_namespace(ns_name)
  return #vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
end

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

describe("Frame Highlights Plugin", function()

  describe("highlight groups", function()
    it("defines context (green), session (blue), other (purple) highlights", function()
      local debugger = sdk:create_debugger()
      local cleanup = frame_highlights(debugger)

      -- Context = green
      local ctx = vim.api.nvim_get_hl(0, { name = "DapFrameContext" })
      assert.is_truthy(ctx.fg and ctx.bg)

      -- Session = blues (0-4)
      for i = 0, 4 do
        local hl = vim.api.nvim_get_hl(0, { name = "DapFrameSessionTop" .. i })
        assert.is_truthy(hl.fg and hl.bg, "Missing DapFrameSessionTop" .. i)
      end

      -- Other = purples (0-4)
      for i = 0, 4 do
        local hl = vim.api.nvim_get_hl(0, { name = "DapFrameOther" .. i })
        assert.is_truthy(hl.fg and hl.bg, "Missing DapFrameOther" .. i)
      end

      cleanup()
      debugger:dispose()
    end)
  end)

  describe("with Python debugger", function()
    local debugger, cleanup, session, bufnr, script_path

    local function setup_debug_session()
      debugger = sdk:create_debugger()
      cleanup = frame_highlights(debugger)

      debugger:register_adapter("python", {
        type = "stdio",
        command = "python3",
        args = { "-m", "debugpy.adapter" }
      })

      script_path = vim.fn.fnamemodify("tests/fixtures/stack_test.py", ":p")
      debugger:add_breakpoint({ path = script_path }, 7)

      vim.cmd("edit " .. script_path)
      bufnr = vim.api.nvim_get_current_buf()

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
      vim.cmd("bwipeout! " .. bufnr)
    end

    async_test("highlights context frame in green", function()
      setup_debug_session()

      local thread = session:threads():iter()()
      local stack = thread:stack()
      local top = stack:top()

      debugger:context():pin(top.uri)
      wait(500)

      assert.equals("DapFrameContext", highlight_at(bufnr, top.line))

      teardown()
      return true
    end)

    async_test("clears highlights when frames expire", function()
      setup_debug_session()

      local thread = session:threads():iter()()
      local stack = thread:stack()
      debugger:context():pin(stack:top().uri)
      wait(500)

      assert.is_true(highlight_count(bufnr) > 0)

      session:continue()
      wait(2000, function() return highlight_count(bufnr) == 0 end)

      assert.equals(0, highlight_count(bufnr))

      teardown()
      return true
    end)

    async_test("changes highlight when context switches frames", function()
      setup_debug_session()

      local thread = session:threads():iter()()
      local stack = thread:stack()
      local frames = {}
      for f in stack:frames():iter() do frames[#frames + 1] = f end

      assert.is_true(#frames >= 2, "Need 2+ frames")

      -- Pin frame 1 → green
      debugger:context():pin(frames[1].uri)
      wait(500)
      assert.equals("DapFrameContext", highlight_at(bufnr, frames[1].line))

      -- Pin frame 2 → frame 1 becomes blue, frame 2 becomes green
      debugger:context():pin(frames[2].uri)
      wait(500)

      assert.is_truthy(highlight_at(bufnr, frames[1].line):match("^DapFrameSessionTop"))
      assert.equals("DapFrameContext", highlight_at(bufnr, frames[2].line))

      teardown()
      return true
    end)
  end)
end)
