-- Unit tests for neodap.error module
local MiniTest = require("mini.test")
local E = require("neodap.error")
local a = require("neodap.async")

local T = MiniTest.new_set()

-- ============================================================================
-- NeodapError construction
-- ============================================================================
T["NeodapError"] = MiniTest.new_set()

T["NeodapError"]["user() creates error with show_user=true and level=ERROR"] = function()
  local err = E.user("something broke")
  MiniTest.expect.equality(err.message, "something broke")
  MiniTest.expect.equality(err.show_user, true)
  MiniTest.expect.equality(err.level, vim.log.levels.ERROR)
end

T["NeodapError"]["warn() creates error with show_user=true and level=WARN"] = function()
  local err = E.warn("heads up")
  MiniTest.expect.equality(err.message, "heads up")
  MiniTest.expect.equality(err.show_user, true)
  MiniTest.expect.equality(err.level, vim.log.levels.WARN)
end

T["NeodapError"]["internal() creates error with show_user=false"] = function()
  local err = E.internal("cleanup failed")
  MiniTest.expect.equality(err.message, "cleanup failed")
  MiniTest.expect.equality(err.show_user, false)
end

T["NeodapError"]["tostring returns message"] = function()
  local err = E.user("test message")
  MiniTest.expect.equality(tostring(err), "test message")
end

T["NeodapError"]["user() accepts data option"] = function()
  local err = E.user("broke", { data = { key = "value" } })
  MiniTest.expect.equality(err.data.key, "value")
end

-- ============================================================================
-- Type checking: E.is()
-- ============================================================================
T["is"] = MiniTest.new_set()

T["is"]["returns true for NeodapError"] = function()
  MiniTest.expect.equality(E.is(E.user("x")), true)
  MiniTest.expect.equality(E.is(E.warn("x")), true)
  MiniTest.expect.equality(E.is(E.internal("x")), true)
end

T["is"]["returns false for non-NeodapError"] = function()
  MiniTest.expect.equality(E.is("string error"), false)
  MiniTest.expect.equality(E.is(nil), false)
  MiniTest.expect.equality(E.is(42), false)
  MiniTest.expect.equality(E.is({ message = "looks like one" }), false)
end

-- ============================================================================
-- Unwrapping: E.unwrap()
-- ============================================================================
T["unwrap"] = MiniTest.new_set()

T["unwrap"]["returns NeodapError directly"] = function()
  local err = E.user("direct")
  MiniTest.expect.equality(E.unwrap(err), err)
end

T["unwrap"]["extracts NeodapError from AsyncError wrapper"] = function()
  local inner = E.user("wrapped")
  local async_err = a.AsyncError.new(inner, {})
  MiniTest.expect.equality(E.unwrap(async_err), inner)
end

T["unwrap"]["extracts NeodapError from AsyncError.wrap()"] = function()
  local inner = E.user("via wrap")
  local frame = { name = "test", source = "test.lua", line = 1 }
  local async_err = a.AsyncError.wrap(inner, frame)
  MiniTest.expect.equality(E.unwrap(async_err), inner)
end

T["unwrap"]["returns nil for plain string"] = function()
  MiniTest.expect.equality(E.unwrap("plain string"), nil)
end

T["unwrap"]["returns nil for AsyncError wrapping string"] = function()
  local async_err = a.AsyncError.new("string message", {})
  MiniTest.expect.equality(E.unwrap(async_err), nil)
end

T["unwrap"]["returns nil for nil"] = function()
  MiniTest.expect.equality(E.unwrap(nil), nil)
end

-- ============================================================================
-- E.report() behavior
-- ============================================================================
T["report"] = MiniTest.new_set()

-- Capture vim.notify calls for testing
local function with_notify_capture(fn)
  local calls = {}
  local orig = vim.notify
  vim.notify = function(msg, level, opts)
    table.insert(calls, { msg = msg, level = level, opts = opts })
  end
  local ok, err = pcall(fn)
  vim.notify = orig
  if not ok then error(err) end
  return calls
end

T["report"]["notifies user for plain string error"] = function()
  local calls = with_notify_capture(function()
    E.report("something went wrong")
  end)
  MiniTest.expect.equality(#calls, 1)
  MiniTest.expect.equality(calls[1].msg, "[neodap] something went wrong")
  MiniTest.expect.equality(calls[1].level, vim.log.levels.ERROR)
end

T["report"]["notifies user for NeodapError with show_user=true"] = function()
  local calls = with_notify_capture(function()
    E.report(E.user("user error"))
  end)
  MiniTest.expect.equality(#calls, 1)
  MiniTest.expect.equality(calls[1].msg, "[neodap] user error")
  MiniTest.expect.equality(calls[1].level, vim.log.levels.ERROR)
end

T["report"]["uses WARN level for E.warn()"] = function()
  local calls = with_notify_capture(function()
    E.report(E.warn("warning"))
  end)
  MiniTest.expect.equality(#calls, 1)
  MiniTest.expect.equality(calls[1].msg, "[neodap] warning")
  MiniTest.expect.equality(calls[1].level, vim.log.levels.WARN)
end

T["report"]["suppresses notification for E.internal()"] = function()
  local calls = with_notify_capture(function()
    E.report(E.internal("internal"))
  end)
  MiniTest.expect.equality(#calls, 0)
end

T["report"]["suppresses notification for cancelled string"] = function()
  local calls = with_notify_capture(function()
    E.report("cancelled")
  end)
  MiniTest.expect.equality(#calls, 0)
end

T["report"]["suppresses notification for AsyncError wrapping cancelled"] = function()
  local calls = with_notify_capture(function()
    E.report(a.AsyncError.new("cancelled", {}))
  end)
  MiniTest.expect.equality(#calls, 0)
end

T["report"]["extracts clean message from AsyncError wrapping string"] = function()
  local calls = with_notify_capture(function()
    local frame = { name = "test", source = "test.lua", line = 1 }
    E.report(a.AsyncError.wrap("DAP error message", frame))
  end)
  MiniTest.expect.equality(#calls, 1)
  MiniTest.expect.equality(calls[1].msg, "[neodap] DAP error message")
end

T["report"]["extracts clean message from AsyncError wrapping NeodapError"] = function()
  local calls = with_notify_capture(function()
    local frame = { name = "test", source = "test.lua", line = 1 }
    E.report(a.AsyncError.wrap(E.warn("wrapped warning"), frame))
  end)
  MiniTest.expect.equality(#calls, 1)
  MiniTest.expect.equality(calls[1].msg, "[neodap] wrapped warning")
  MiniTest.expect.equality(calls[1].level, vim.log.levels.WARN)
end

T["report"]["suppresses for AsyncError wrapping E.internal()"] = function()
  local calls = with_notify_capture(function()
    local frame = { name = "test", source = "test.lua", line = 1 }
    E.report(a.AsyncError.wrap(E.internal("internal"), frame))
  end)
  MiniTest.expect.equality(#calls, 0)
end

T["report"]["does nothing for nil"] = function()
  local calls = with_notify_capture(function()
    E.report(nil)
  end)
  MiniTest.expect.equality(#calls, 0)
end

-- ============================================================================
-- E.create_command() integration
-- ============================================================================
T["create_command"] = MiniTest.new_set()

T["create_command"]["reports errors thrown in handler"] = function()
  local calls = with_notify_capture(function()
    E.create_command("TestNeodapErrorCmd", function()
      error(E.warn("command validation failed"), 0)
    end, { desc = "test" })

    vim.cmd("TestNeodapErrorCmd")
    pcall(vim.api.nvim_del_user_command, "TestNeodapErrorCmd")
  end)
  MiniTest.expect.equality(#calls, 1)
  MiniTest.expect.equality(calls[1].msg, "[neodap] command validation failed")
  MiniTest.expect.equality(calls[1].level, vim.log.levels.WARN)
end

T["create_command"]["does not report when handler succeeds"] = function()
  local calls = with_notify_capture(function()
    E.create_command("TestNeodapSuccessCmd", function()
      -- no error
    end, { desc = "test" })

    vim.cmd("TestNeodapSuccessCmd")
    pcall(vim.api.nvim_del_user_command, "TestNeodapSuccessCmd")
  end)
  MiniTest.expect.equality(#calls, 0)
end

T["create_command"]["reports plain string errors"] = function()
  local calls = with_notify_capture(function()
    E.create_command("TestNeodapPlainCmd", function()
      error("plain error message", 0)
    end, { desc = "test" })

    vim.cmd("TestNeodapPlainCmd")
    pcall(vim.api.nvim_del_user_command, "TestNeodapPlainCmd")
  end)
  MiniTest.expect.equality(#calls, 1)
  MiniTest.expect.equality(calls[1].msg:match("plain error message") ~= nil, true)
end

-- ============================================================================
-- Integration: async default_error_handler routes through E.report()
-- ============================================================================
T["async_integration"] = MiniTest.new_set()

T["async_integration"]["async errors are reported to user"] = function()
  local done = false
  local calls = with_notify_capture(function()
    a.run(function()
      error("async failure", 0)
    end)
    -- default_error_handler uses vim.schedule, so we need to flush
    vim.wait(200, function()
      done = true
      return false
    end, 10)
  end)
  -- The notification happens via vim.schedule, so it may have fired during vim.wait
  MiniTest.expect.equality(#calls >= 1, true)
  if #calls > 0 then
    MiniTest.expect.equality(calls[1].msg:match("async failure") ~= nil, true)
  end
end

T["async_integration"]["cancelled async errors are suppressed"] = function()
  local calls = with_notify_capture(function()
    local task = a.run(function()
      a.wait(function(cb)
        -- Never resolves, will be cancelled
      end, "waiting")
    end)
    task:cancel()
    vim.wait(200, function() return false end, 10)
  end)
  MiniTest.expect.equality(#calls, 0)
end

T["async_integration"]["E.internal() errors are suppressed in async"] = function()
  local calls = with_notify_capture(function()
    a.run(function()
      error(E.internal("internal only"), 0)
    end)
    vim.wait(200, function() return false end, 10)
  end)
  MiniTest.expect.equality(#calls, 0)
end

-- ============================================================================
-- E.keymap() integration
-- ============================================================================
T["keymap"] = MiniTest.new_set()

T["keymap"]["reports errors thrown in keymap handler"] = function()
  local test_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(test_buf)

  local calls = with_notify_capture(function()
    E.keymap("n", "<F20>", function()
      error(E.warn("keymap failed"), 0)
    end, { buffer = test_buf, desc = "test" })

    -- Trigger the keymap
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<F20>", true, false, true), "x", false)
  end)

  pcall(vim.api.nvim_buf_delete, test_buf, { force = true })
  MiniTest.expect.equality(#calls, 1)
  MiniTest.expect.equality(calls[1].msg, "[neodap] keymap failed")
  MiniTest.expect.equality(calls[1].level, vim.log.levels.WARN)
end

T["keymap"]["does not report when handler succeeds"] = function()
  local test_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(test_buf)

  local calls = with_notify_capture(function()
    E.keymap("n", "<F20>", function()
      -- no error
    end, { buffer = test_buf, desc = "test" })

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<F20>", true, false, true), "x", false)
  end)

  pcall(vim.api.nvim_buf_delete, test_buf, { force = true })
  MiniTest.expect.equality(#calls, 0)
end

return T
