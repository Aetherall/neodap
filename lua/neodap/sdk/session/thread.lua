---@class Thread : Class
---@field session Session
---@field id number
---@field global_id string
---@field name Signal<string>
---@field state Signal<"running"|"stopped">
---@field stopReason Signal<string?>
---@field current_stack Signal<Stack?>

local neostate = require("neostate")
local Stack = require("neodap.sdk.session.stack")

local M = {}

-- =============================================================================
-- THREAD
-- =============================================================================

---@class Thread : Class
local Thread = neostate.Class("Thread")

function Thread:init(session, thread_id)
  self.session = session
  self.id = thread_id

  -- Global unique identifier across all sessions
  self.global_id = session.id .. ":" .. thread_id

  -- URI and key for EntityStore
  self.uri = "dap:session:" .. session.id .. "/thread:" .. thread_id
  self.key = "thread:" .. thread_id
  self._type = "thread"

  -- Eager expansion: threads auto-expand in tree views
  self.eager = true

  -- Track stack sequence for URI generation
  self._stack_sequence = 0

  -- Guard to prevent concurrent stack fetches (race condition fix)
  self._stack_fetch_promise = nil

  self.name = self:signal("Thread " .. thread_id, "name")
  self.state = self:signal("running", "state")
  self.stopReason = self:signal(nil, "stopReason")
  self._current_stack = self:signal(nil, "current_stack")

  -- Fetch thread name from DAP
  self:_fetch_name()
end

---Get current stack (fetches if needed)
---@return Stack?
function Thread:stack()
  local stack = self._current_stack:get()
  if stack then
    return stack
  end

  return self:fetch_stack_trace()
end

---Internal: Fetch thread name from DAP (fire-and-forget)
function Thread:_fetch_name()
  -- Fire and forget - fetch name in background without blocking
  -- Use void() here because this is an internal background operation
  neostate.void(function()
    local result, err = neostate.settle(self.session.client:request("threads", vim.empty_dict()))
    if err or not result or not result.threads then return end

    for _, t in ipairs(result.threads) do
      if t.id == self.id then
        self.name:set(t.name or ("Thread " .. self.id))
        break
      end
    end
  end)()
end

---Internal: Handle stopped event
---@param reason string
---@param is_focus boolean  -- Is this the thread that actually stopped?
function Thread:_on_stopped(reason, is_focus)
  self.stopReason:set(reason)
  self.state:set("stopped")

  if is_focus then
    -- Mark current stack as stale (if exists) using release() to avoid disposal
    local current = self._current_stack:release()
    if current then
      current:_mark_expired()
    end
  end
end

---Internal: Handle continued event
function Thread:_on_continued()
  self.state:set("running")
  self.stopReason:set(nil)

  -- Mark current stack as stale (if exists) using release() to avoid disposal
  local current = self._current_stack:release()
  if current then
    current:_mark_expired()
  end
end

---Fetch stack trace for this thread
---@return Stack? stack
function Thread:fetch_stack_trace()
  -- Check if a fetch is already in progress (race condition guard)
  if self._stack_fetch_promise then
    -- Wait for the existing fetch to complete and return its result
    return neostate.await(self._stack_fetch_promise)
  end

  -- Create a promise to guard concurrent access
  self._stack_fetch_promise = neostate.Promise()

  local result, err = neostate.settle(self.session.client:request("stackTrace", {
    threadId = self.id,
    startFrame = 0,
    levels = 20, -- Default limit
  }))

  if err or not result then
    self._stack_fetch_promise:resolve(nil)
    self._stack_fetch_promise = nil
    return nil
  end

  -- Increment stack sequence for new stack
  self._stack_sequence = self._stack_sequence + 1

  local stack = Stack.Stack:new(
    self,
    result.stackFrames,
    self.stopReason:get() or "unknown",
    self._stack_sequence
  )

  self._current_stack:set(stack)

  -- Resolve promise and clear guard
  self._stack_fetch_promise:resolve(stack)
  self._stack_fetch_promise = nil

  return stack
end

---Step over (next)
---@param granularity? "statement"|"line"|"instruction"
---@return string? error
function Thread:step_over(granularity)
  -- Mark current stack as stale before stepping using release() to avoid disposal
  local current = self._current_stack:release()
  if current then
    current:_mark_expired()
  end

  local result, err = neostate.settle(self.session.client:request("next", {
    threadId = self.id,
    granularity = granularity,
  }))
  return err
end

---Step into
---@param granularity? "statement"|"line"|"instruction"
---@return string? error
function Thread:step_into(granularity)
  -- Mark current stack as stale before stepping using release() to avoid disposal
  local current = self._current_stack:release()
  if current then
    current:_mark_expired()
  end

  local result, err = neostate.settle(self.session.client:request("stepIn", {
    threadId = self.id,
    granularity = granularity,
  }))
  return err
end

---Step out
---@param granularity? "statement"|"line"|"instruction"
---@return string? error
function Thread:step_out(granularity)
  -- Mark current stack as stale before stepping using release() to avoid disposal
  local current = self._current_stack:release()
  if current then
    current:_mark_expired()
  end

  local result, err = neostate.settle(self.session.client:request("stepOut", {
    threadId = self.id,
    granularity = granularity,
  }))
  return err
end

---Pause thread execution
---@return string? error
function Thread:pause()
  local result, err = neostate.settle(self.session.client:request("pause", {
    threadId = self.id,
  }))
  return err
end

---Continue thread execution
---@return string? error
function Thread:continue()
  local result, err = neostate.settle(self.session.client:request("continue", {
    threadId = self.id,
  }))
  return err
end

---Check if thread stopped on exception
---@return boolean
function Thread:stoppedOnException()
  local reason = self.stopReason:get()
  return reason == "exception"
end

---Get exception info if stopped on exception
---@return dap.ExceptionInfoResponseBody? info, string? error
function Thread:exceptionInfo()
  if not self:stoppedOnException() then
    return nil, "Thread did not stop on exception"
  end

  -- Check if adapter supports exception info
  local caps = self.session.capabilities
  if not caps or not caps.supportsExceptionInfoRequest then
    return nil, "Adapter does not support exceptionInfo request"
  end

  local result, err = neostate.settle(self.session.client:request("exceptionInfo", {
    threadId = self.id,
  }))

  if err then
    return nil, err
  end

  return result, nil
end

---Get filtered frames for this thread (across all stacks)
---@return table Filtered collection of frames
function Thread:frames()
  if not self._frames then
    self._frames = self.session.debugger.frames:where(
      "by_thread_id",
      self.global_id,
      "Frames:Thread:" .. self.global_id
    )
  end
  return self._frames
end

---Get current frames only (active stack)
---@return table Filtered collection of frames
function Thread:current_frames()
  if not self._current_frames then
    self._current_frames = self:frames():where(
      "by_is_current",
      true,
      "CurrentFrames:Thread:" .. self.global_id
    )
  end
  return self._current_frames
end

---Get all stacks for this thread
---@return View Filtered view of stacks
function Thread:stacks()
  if not self._stacks then
    self._stacks = self.session.debugger.stacks:where(
      "by_thread_id",
      self.global_id,
      "Stacks:Thread:" .. self.global_id
    )
  end
  return self._stacks
end

---Get stale stacks for this thread (expired stacks from previous stops)
---@return View Filtered view of stale stacks
function Thread:stale_stacks()
  if not self._stale_stacks then
    self._stale_stacks = self:stacks():where(
      "by_is_current",
      false,
      "StaleStacks:Thread:" .. self.global_id
    )
  end
  return self._stale_stacks
end

-- =============================================================================
-- LIFECYCLE HOOKS
-- =============================================================================

---Register callback for when thread stops
---@param fn function  -- Called with (reason: string)
---@return function unsubscribe
function Thread:onStopped(fn)
  -- Use state changes for stopped events (current + future)
  return self.state:use(function(state)
    if state == "stopped" then
      fn(self.stopReason:get() or "unknown")
    end
  end)
end

---Register callback for when thread resumes after being stopped
---@param fn function  -- Called with no arguments
---@return function unsubscribe
function Thread:onResumed(fn)
  -- Track transitions from stopped to running
  local was_stopped = self.state:get() == "stopped"

  return self.state:watch(function(state)
    if was_stopped and state == "running" then
      fn()
    end
    was_stopped = (state == "stopped")
  end)
end

---Register callback for stack traces (current + future)
---@param fn function  -- Called with (stack)
---@return function unsubscribe
function Thread:onStack(fn)
  return self._current_stack:use(function(stack)
    if stack then
      fn(stack)
    end
  end)
end

---Register callback for all frames in this thread (historical + current)
---@param fn function  -- Called with (frame)
---@return function unsubscribe
function Thread:onFrame(fn)
  return self:frames():each(fn)
end

---Register callback for frames in the current stack only
---@param fn function  -- Called with (frame)
---@return function unsubscribe
function Thread:onCurrentFrame(fn)
  return self:current_frames():each(fn)
end

M.Thread = Thread

-- Backwards compatibility
function M.create(session, thread_id)
  return Thread:new(session, thread_id)
end

return M
