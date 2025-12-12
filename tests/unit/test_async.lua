-- Unit tests for neodap.async module
local MiniTest = require("mini.test")
local a = require("neodap.async")

local T = MiniTest.new_set()

-- Helper to run async and wait for result
local function run_sync(fn, timeout)
  timeout = timeout or 1000
  local done, result, err = false, nil, nil
  a.run(fn, function(e, r)
    err, result = e, r
    done = true
  end)
  vim.wait(timeout, function() return done end, 10)
  if err then error(err) end
  return result
end

-- a.run tests
T["run"] = MiniTest.new_set()

T["run"]["executes function and calls callback with result"] = function()
  local done, result = false, nil
  a.run(function()
    return 42
  end, function(err, r)
    result = r
    done = true
  end)
  vim.wait(100, function() return done end, 10)
  MiniTest.expect.equality(result, 42)
end

T["run"]["calls callback with error on throw"] = function()
  local done, err = false, nil
  a.run(function()
    error("test error")
  end, function(e)
    err = e
    done = true
  end)
  vim.wait(100, function() return done end, 10)
  MiniTest.expect.equality(err ~= nil, true)
  MiniTest.expect.equality(tostring(err):match("test error") ~= nil, true)
end

T["run"]["returns context for cancellation"] = function()
  local ctx = a.run(function()
    return 1
  end)
  MiniTest.expect.equality(type(ctx), "table")
  MiniTest.expect.equality(type(ctx.cancel), "function")
end

-- a.wait tests
T["wait"] = MiniTest.new_set()

T["wait"]["awaits callback-based operation"] = function()
  local result = run_sync(function()
    return a.wait(function(cb)
      vim.schedule(function() cb(nil, "hello") end)
    end)
  end)
  MiniTest.expect.equality(result, "hello")
end

T["wait"]["throws on error"] = function()
  local done, err = false, nil
  a.run(function()
    a.wait(function(cb)
      vim.schedule(function() cb("oops", nil) end)
    end)
  end, function(e)
    err = e
    done = true
  end)
  vim.wait(100, function() return done end, 10)
  MiniTest.expect.equality(err ~= nil, true)
end

T["wait"]["captures trace frame"] = function()
  local done, err = false, nil
  a.run(function()
    a.wait(function(cb)
      vim.schedule(function() cb("fail", nil) end)
    end, "my_operation")
  end, function(e)
    err = e
    done = true
  end)
  vim.wait(100, function() return done end, 10)
  MiniTest.expect.equality(tostring(err):match("my_operation") ~= nil, true)
end

-- a.wait_all tests
T["wait_all"] = MiniTest.new_set()

T["wait_all"]["awaits multiple operations in parallel"] = function()
  local result = run_sync(function()
    return a.wait_all({
      function(cb) vim.schedule(function() cb(nil, 1) end) end,
      function(cb) vim.schedule(function() cb(nil, 2) end) end,
      function(cb) vim.schedule(function() cb(nil, 3) end) end,
    })
  end)
  MiniTest.expect.equality(result, { 1, 2, 3 })
end

T["wait_all"]["returns empty array for empty input"] = function()
  local result = run_sync(function()
    return a.wait_all({})
  end)
  MiniTest.expect.equality(result, {})
end

T["wait_all"]["throws on first error"] = function()
  local done, err = false, nil
  a.run(function()
    a.wait_all({
      function(cb) vim.schedule(function() cb(nil, 1) end) end,
      function(cb) vim.schedule(function() cb("error2", nil) end) end,
      function(cb) vim.schedule(function() cb(nil, 3) end) end,
    })
  end, function(e)
    err = e
    done = true
  end)
  vim.wait(100, function() return done end, 10)
  MiniTest.expect.equality(err ~= nil, true)
end

-- a.event tests
T["event"] = MiniTest.new_set()

T["event"]["waiter receives value when set"] = function()
  local result = run_sync(function()
    local ev = a.event()
    vim.schedule(function() ev:set("done") end)
    return a.wait(ev.wait)
  end)
  MiniTest.expect.equality(result, "done")
end

T["event"]["multiple waiters all receive value"] = function()
  local ev = a.event()
  local results = {}

  a.run(function()
    results[1] = a.wait(ev.wait)
  end)
  a.run(function()
    results[2] = a.wait(ev.wait)
  end)

  vim.schedule(function() ev:set("shared") end)
  vim.wait(100, function() return results[1] and results[2] end, 10)

  MiniTest.expect.equality(results[1], "shared")
  MiniTest.expect.equality(results[2], "shared")
end

T["event"]["set only fires once"] = function()
  local ev = a.event()
  ev:set("first")
  ev:set("second")

  local result = run_sync(function()
    return a.wait(ev.wait)
  end)
  MiniTest.expect.equality(result, "first")
end

-- a.timeout tests
T["timeout"] = MiniTest.new_set()

T["timeout"]["returns result if operation completes in time"] = function()
  local result = run_sync(function()
    return a.timeout(1000, function(cb)
      vim.schedule(function() cb(nil, "fast") end)
    end)
  end)
  MiniTest.expect.equality(result, "fast")
end

T["timeout"]["throws timeout error if operation is slow"] = function()
  local done, err = false, nil
  a.run(function()
    a.timeout(10, function(cb)
      -- Never calls cb
    end)
  end, function(e)
    err = e
    done = true
  end)
  vim.wait(200, function() return done end, 10)
  MiniTest.expect.equality(err ~= nil, true)
  MiniTest.expect.equality(tostring(err):match("timeout") ~= nil, true)
end

-- a.mutex tests
T["mutex"] = MiniTest.new_set()

T["mutex"]["serializes access"] = function()
  local order = {}
  local m = a.mutex()

  a.run(function()
    a.wait(m.lock)
    table.insert(order, "a_start")
    a.wait(function(cb) vim.defer_fn(function() cb(nil) end, 50) end)
    table.insert(order, "a_end")
    m:unlock()
  end)

  a.run(function()
    a.wait(m.lock)
    table.insert(order, "b_start")
    table.insert(order, "b_end")
    m:unlock()
  end)

  vim.wait(200, function() return #order == 4 end, 10)
  MiniTest.expect.equality(order, { "a_start", "a_end", "b_start", "b_end" })
end

-- a.wrap tests
T["wrap"] = MiniTest.new_set()

T["wrap"]["wraps function"] = function()
  local function async_add(x, y, cb)
    vim.schedule(function() cb(nil, x + y) end)
  end

  local wrapped = a.wrap(async_add)
  local result = run_sync(function()
    return wrapped(2, 3)
  end)
  MiniTest.expect.equality(result, 5)
end

T["wrap"]["wraps object methods"] = function()
  local obj = {
    value = 10,
    add = function(self, x, cb)
      vim.schedule(function() cb(nil, self.value + x) end)
    end,
    sync_method = function(self)
      return self.value * 2
    end,
  }

  local wrapped = a.wrap(obj, { "add" })
  local result = run_sync(function()
    return wrapped:add(5)
  end)
  MiniTest.expect.equality(result, 15)

  -- Sync method still works
  MiniTest.expect.equality(wrapped:sync_method(), 20)
end

-- Context tests
T["context"] = MiniTest.new_set()

T["context"]["returns nil outside async"] = function()
  MiniTest.expect.equality(a.context(), nil)
end

T["context"]["returns context inside async"] = function()
  local ctx_inside = nil
  a.run(function()
    ctx_inside = a.context()
  end)
  vim.wait(50, function() return ctx_inside ~= nil end, 10)
  MiniTest.expect.equality(type(ctx_inside), "table")
end

T["context"]["inherits values from parent"] = function()
  local child_value = nil
  local parent_ctx = a.Context.new()
  parent_ctx.values.key = "parent_value"

  a.run(function()
    child_value = a.context():get("key")
  end, nil, parent_ctx)

  vim.wait(50, function() return child_value ~= nil end, 10)
  MiniTest.expect.equality(child_value, "parent_value")
end

T["context"]["child values shadow parent"] = function()
  local result = nil
  local parent_ctx = a.Context.new()
  parent_ctx.values.key = "parent"

  local child_ctx = parent_ctx:with("key", "child")

  a.run(function()
    result = a.context():get("key")
  end, nil, child_ctx)

  vim.wait(50, function() return result ~= nil end, 10)
  MiniTest.expect.equality(result, "child")
end

-- Cancellation tests
T["cancellation"] = MiniTest.new_set()

T["cancellation"]["cancelled context throws at next wait"] = function()
  local done, err = false, nil
  local ctx = a.run(function()
    a.wait(function(cb)
      -- Simulate slow operation
      vim.defer_fn(function() cb(nil, "done") end, 100)
    end)
  end, function(e)
    err = e
    done = true
  end)

  -- Cancel before operation completes
  ctx:cancel()

  vim.wait(200, function() return done end, 10)
  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(err, "cancelled")
end

T["cancellation"]["done() propagates up parent chain"] = function()
  local parent = a.Context.new()
  local child = a.Context.new(parent)

  MiniTest.expect.equality(child:done(), false)
  parent:cancel()
  MiniTest.expect.equality(child:done(), true)
end

-- AsyncError tests
T["AsyncError"] = MiniTest.new_set()

T["AsyncError"]["formats with trace"] = function()
  local err = a.AsyncError.new("test message", {
    { name = "inner", source = "a.lua", line = 10 },
    { name = "outer", source = "b.lua", line = 20 },
  })
  local str = tostring(err)
  MiniTest.expect.equality(str:match("AsyncError: test message") ~= nil, true)
  MiniTest.expect.equality(str:match("inner") ~= nil, true)
  MiniTest.expect.equality(str:match("outer") ~= nil, true)
end

T["AsyncError"]["wrap accumulates frames"] = function()
  local err = a.AsyncError.new("original", {})
  local wrapped = a.AsyncError.wrap(err, { name = "added", source = "c.lua", line = 30 })
  MiniTest.expect.equality(#wrapped.frames, 1)
  MiniTest.expect.equality(wrapped.frames[1].name, "added")
end

-- a.memoize tests
T["memoize"] = MiniTest.new_set()

T["memoize"]["coalesces concurrent calls"] = function()
  local call_count = 0
  local obj = { id = 1 }

  local function fetch(self)
    call_count = call_count + 1
    a.wait(function(cb) vim.defer_fn(function() cb(nil, "result") end, 50) end)
    return "done"
  end

  local memoized = a.memoize(fetch)

  local results = {}
  memoized(obj, function(err, r) results[1] = r end)
  memoized(obj, function(err, r) results[2] = r end)
  memoized(obj, function(err, r) results[3] = r end)

  vim.wait(200, function() return results[1] and results[2] and results[3] end, 10)

  MiniTest.expect.equality(call_count, 1) -- Only one call
  MiniTest.expect.equality(results[1], "done")
  MiniTest.expect.equality(results[2], "done")
  MiniTest.expect.equality(results[3], "done")
end

T["memoize"]["propagates errors to all waiters"] = function()
  local obj = { id = 1 }

  local function fetch(self)
    a.wait(function(cb) vim.defer_fn(function() cb(nil) end, 20) end)
    error("fetch failed", 0)
  end

  local memoized = a.memoize(fetch)

  local errors = {}
  memoized(obj, function(err) errors[1] = err end)
  memoized(obj, function(err) errors[2] = err end)

  vim.wait(200, function() return errors[1] and errors[2] end, 10)

  MiniTest.expect.equality(errors[1] ~= nil, true)
  MiniTest.expect.equality(errors[2] ~= nil, true)
end

T["memoize"]["allows new call after completion"] = function()
  local call_count = 0
  local obj = { id = 1 }

  local function fetch(self)
    call_count = call_count + 1
    return "result"
  end

  local memoized = a.memoize(fetch)

  local done1, done2 = false, false
  memoized(obj, function() done1 = true end)
  vim.wait(100, function() return done1 end, 10)

  memoized(obj, function() done2 = true end)
  vim.wait(100, function() return done2 end, 10)

  MiniTest.expect.equality(call_count, 2) -- Two separate calls
end

return T
