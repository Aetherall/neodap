-- Coroutine-based async system for neodap
-- See ASYNC.md for full documentation
local M = {}

local contexts = setmetatable({}, { __mode = "k" })

-- Context: carries values, trace frames, cancellation through async chain
local Context = {}
Context.__index = Context

function Context.new(parent)
  local ctx = setmetatable({
    parent = parent,
    values = {},
    frames = {},
    cancelled = false,
    cleanups = {},
    children = setmetatable({}, { __mode = "v" }), -- weak refs to children
  }, Context)
  -- Register with parent so we get cancelled when parent is
  if parent then
    parent:onCleanup(function()
      ctx:cancel()
    end)
  end
  return ctx
end

---Register a cleanup function to run when context is cancelled
---@param fn function Cleanup function
function Context:onCleanup(fn)
  table.insert(self.cleanups, fn)
end

function Context:with(key, value)
  local child = Context.new(self)
  child.values[key] = value
  return child
end

function Context:get(key)
  if self.values[key] ~= nil then return self.values[key] end
  if self.parent then return self.parent:get(key) end
  return nil
end

function Context:cancel()
  if self.cancelled then return end
  self.cancelled = true
  -- Run all cleanup functions in reverse order (includes child cancellations)
  for i = #self.cleanups, 1, -1 do
    pcall(self.cleanups[i])
  end
  self.cleanups = {}
end

function Context:done()
  if self.cancelled then return true end
  if self.parent then return self.parent:done() end
  return false
end

M.Context = Context

-- AsyncError: wraps errors with trace frames
local AsyncError = {}
AsyncError.__index = AsyncError

function AsyncError.new(message, frames)
  return setmetatable({ message = message, frames = frames or {} }, AsyncError)
end

function AsyncError:__tostring()
  local lines = { "AsyncError: " .. tostring(self.message) }
  for i = #self.frames, 1, -1 do
    local f = self.frames[i]
    table.insert(lines, string.format("  at %s (%s:%d)", f.name, f.source, f.line))
  end
  return table.concat(lines, "\n")
end

function AsyncError.wrap(err, frame)
  if getmetatable(err) == AsyncError then
    table.insert(err.frames, frame)
    return err
  end
  return AsyncError.new(err, { frame })
end

M.AsyncError = AsyncError

-- Get current coroutine's context
function M.context()
  return contexts[coroutine.running()]
end

-- Yield to main thread (use when you need vim API access)
function M.main(cb)
  vim.schedule(function() cb(nil) end)
end

-- Default error handler - logs unhandled async errors
local function default_error_handler(err, result)
  if not err then return end -- Success, ignore
  if err == "cancelled" then return end
  vim.schedule(function()
    vim.notify("async error: " .. tostring(err), vim.log.levels.ERROR)
  end)
end

-- Task: returned by a.run(), both awaitable and cancellable
local Task = {}
Task.__index = Task

-- Make Task callable as an awaitable
function Task:__call(cb)
  if self.done then
    cb(self.err, self.result)
  else
    table.insert(self.waiters, cb)
  end
end

function Task:cancel()
  self.ctx:cancel()
end

function Task:onCleanup(fn)
  self.ctx:onCleanup(fn)
end

M.Task = Task

-- Run async function in new coroutine
-- Returns a Task that is both awaitable and cancellable:
--   local task = a.run(function() return value end)
--   task:cancel()  -- cancel the task
--   local result = a.wait(task)  -- await the result
-- If no parent_ctx is provided, defaults to scoped.current() if available
function M.run(fn, callback, parent_ctx)
  callback = callback or default_error_handler

  -- Default to scoped.current() if no parent context provided
  if parent_ctx == nil then
    local ok, scoped = pcall(require, "neodap.scoped")
    if ok and scoped.current then
      parent_ctx = scoped.current()
    end
  end

  local co = coroutine.create(fn)
  local ctx = Context.new(parent_ctx)
  contexts[co] = ctx

  local task = setmetatable({
    ctx = ctx,
    done = false,
    err = nil,
    result = nil,
    waiters = {},
  }, Task)

  local function complete(err, result)
    task.done = true
    task.err = err
    task.result = result
    callback(err, result)
    for _, waiter in ipairs(task.waiters) do
      waiter(err, result)
    end
    task.waiters = {}
  end

  local function step(...)
    if coroutine.status(co) == "dead" then return end
    if ctx:done() then
      complete("cancelled")
      return
    end

    local ok, result = coroutine.resume(co, ...)

    if not ok then
      complete(result)
      return
    end

    if coroutine.status(co) == "dead" then
      complete(nil, result)
      return
    end

    result(step)
  end

  step()
  return task
end

-- Wait for callback-based operation
function M.wait(fn, label)
  local ctx = contexts[coroutine.running()]

  if ctx and ctx:done() then
    error(AsyncError.new("cancelled", {}), 0)
  end

  local info = debug.getinfo(2, "Sln") or {}
  local frame = {
    name = label or info.name or "?",
    source = info.short_src or "?",
    line = info.currentline or 0,
  }

  if ctx then table.insert(ctx.frames, frame) end

  local err, result = coroutine.yield(function(step)
    fn(function(e, r)
      step(e, r)
    end)
  end)

  if ctx then table.remove(ctx.frames) end

  if err then error(AsyncError.wrap(err, frame), 0) end
  return result
end

-- Wait for multiple operations in parallel
function M.wait_all(fns, label)
  local ctx = contexts[coroutine.running()]

  if ctx and ctx:done() then
    error(AsyncError.new("cancelled", {}), 0)
  end

  local info = debug.getinfo(2, "Sln") or {}
  local frame = {
    name = label or info.name or "wait_all",
    source = info.short_src or "?",
    line = info.currentline or 0,
  }

  if ctx then table.insert(ctx.frames, frame) end

  if #fns == 0 then
    if ctx then table.remove(ctx.frames) end
    return {}
  end

  local err, results = coroutine.yield(function(step)
    local res, pending, done = {}, #fns, false
    for i, fn in ipairs(fns) do
      fn(function(e, r)
        if done then return end
        if e then
          done = true
          step(e, nil)
        else
          res[i] = r
          pending = pending - 1
          if pending == 0 then
            done = true
            step(nil, res)
          end
        end
      end)
    end
  end)

  if ctx then table.remove(ctx.frames) end

  if err then error(AsyncError.wrap(err, frame), 0) end
  return results
end

-- One-shot event for coordination
function M.event()
  local waiters, fired, value = {}, false, nil
  return {
    wait = function(cb)
      if fired then cb(nil, value) else table.insert(waiters, cb) end
    end,
    set = function(self, v)
      if fired then return end
      fired, value = true, v
      for _, cb in ipairs(waiters) do
        cb(nil, v)
      end
    end,
  }
end

-- Wrap operation with timeout
function M.timeout(ms, fn)
  local ctx = contexts[coroutine.running()]
  local info = debug.getinfo(2, "Sln") or {}
  local frame = {
    name = "timeout",
    source = info.short_src or "?",
    line = info.currentline or 0,
  }

  if ctx then table.insert(ctx.frames, frame) end

  local err, result = coroutine.yield(function(step)
    local done, timer = false, vim.uv.new_timer()
    timer:start(ms, 0, function()
      if done then return end
      done = true
      timer:close()
      step("timeout")
    end)
    fn(function(e, r)
      if done then return end
      done = true
      timer:close()
      step(e, r)
    end)
  end)

  if ctx then table.remove(ctx.frames) end

  if err then error(AsyncError.wrap(err, frame), 0) end
  return result
end

-- Mutex for serializing access
function M.mutex()
  local locked, waiting = false, {}
  return {
    lock = function(cb)
      if not locked then
        locked = true
        cb(nil)
        return
      end
      table.insert(waiting, cb)
    end,
    unlock = function(self)
      local next = table.remove(waiting, 1)
      if next then
        next(nil)
      else
        locked = false
      end
    end,
  }
end

-- Deprecated: use a.fn() instead which auto-detects callbacks
-- Wrap async method to take callback as last argument
function M.async(fn)
  return function(self, ...)
    local args = { ... }
    local callback = table.remove(args)
    M.run(function()
      return fn(self, unpack(args))
    end, callback)
  end
end

-- Wrap function to run inline if in async context, or spawn context if sync
-- Usage: api.toggle = a.fn(function(loc) ... end)
function M.fn(fn)
  return function(...)
    if M.context() then return fn(...) end
    local args = { ... }
    local result
    M.run(function() result = fn(unpack(args)) end)
    return result
  end
end

-- Memoize/coalesce concurrent calls to an async method by self
-- Usage: Thread.fetchStackTrace = a.memoize(Thread.fetchStackTrace)
-- Runs inline when in async context (like a.fn), but coalesces concurrent calls
function M.memoize(fn)
  local cache = setmetatable({}, { __mode = "k" })

  return function(self)
    local entry = cache[self]

    -- If already in async context, run inline (with coalescing)
    if M.context() then
      if entry then
        -- In progress, wait for it
        return M.wait(function(cb)
          table.insert(entry.waiters, cb)
        end, "memoize:wait")
      end

      -- Start computation
      entry = { waiters = {} }
      cache[self] = entry

      local ok, result = pcall(fn, self)
      cache[self] = nil

      -- Notify waiters
      for _, cb in ipairs(entry.waiters) do
        if ok then
          cb(nil, result)
        else
          cb(result)
        end
      end

      if not ok then error(result, 0) end
      return result
    end

    -- Not in async context
    -- If already in progress from another call, just return
    if entry then
      return
    end

    -- Start computation in new context
    entry = { waiters = {} }
    cache[self] = entry

    M.run(function()
      local ok, result = pcall(fn, self)
      cache[self] = nil

      -- Notify waiters
      for _, cb in ipairs(entry.waiters) do
        if ok then
          cb(nil, result)
        else
          cb(result)
        end
      end

      if not ok then error(result, 0) end
    end)
  end
end

-- Wrap callback-last function/methods into async
function M.wrap(target, methods)
  -- Wrap a single function
  if type(target) == "function" then
    return function(...)
      local args = { ... }
      return M.wait(function(cb)
        args[#args + 1] = cb
        target(unpack(args))
      end)
    end
  end

  -- Build async method lookup
  local async = {}
  for _, name in ipairs(methods) do
    async[name] = true
  end

  -- Proxy: wrap async methods, delegate rest
  return setmetatable({}, {
    __index = function(_, name)
      local v = target[name]
      if not async[name] then
        return v -- sync: delegate as-is
      end
      -- Async method: wrap it
      return function(_, ...)
        local args = { ... }
        return M.wait(function(cb)
          args[#args + 1] = cb
          v(target, unpack(args))
        end, name)
      end
    end,
  })
end

return M
