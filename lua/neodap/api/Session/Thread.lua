local Class = require("neodap.tools.class")
local Stack = require("neodap.api.Session.Stack")
local Hookable = require("neodap.transport.hookable")
local Logger = require("neodap.tools.logger")

---@class api.ThreadProps
---@field id integer
---@field session api.Session
---@field hookable Hookable
---@field stopped boolean
---@field public _stack? api.Stack

---@class api.Thread: api.ThreadProps
---@field new Constructor<api.ThreadProps>
---@field public _stack? api.Stack
---@field stopped boolean
local Thread = Class();

local log = Logger.get("DAP:Thread")


function Thread.instanciate(session, id, parentHookable)
  -- TODO: listen for thread events and clear stack when continued or exited
  -- TODO: add a virtual listener onResumed that allows to hook to a continue only once, ignoring subsequent continues until the next stopped
  local instance = Thread:new({
    id = id,
    session = session,
    _stack = nil,
    hookable = Hookable.create(parentHookable),
    stopped = false,
  })

  instance:listen() -- Start listening for thread events

  return instance
end

function Thread:listen()
  local uniqueId = "Thread(" .. self.id .. ")"

  self:onStopped(function(body)
    log:debug("Thread", self.id, "stopped")
    self.stopped = true
    if self._stack then
      self._stack:invalidate() -- Invalidate existing stack if paused again
    end
    self._stack = nil          -- Clear stack when stopped
  end, { priority = 1, name = uniqueId .. ".InvalidateStackOnStopped" })

  -- self:onContinued(function(body)
  --   -- if self.stopped then
  --     if self._stack then
  --       self._stack:invalidate() -- Invalidate existing stack if paused again
  --     end
  --     self._stack = nil          -- Clear stack when continued after a stop
  --   -- end
  -- end, { priority = 1, name = uniqueId .. ".InvalidateStackOnContinued" })


  self:onContinued(function(body)
    -- local log = Logger.get("DAP:Thread")
    log:trace("Thread", self.id, "continued")
    if self._stack then
      self._stack:invalidate() -- Invalidate existing stack if paused again
    end
    self._stack = nil          -- Clear stack when continued after a stop
    if self.stopped then
      self.stopped = false
      log:debug("Thread", self.id, "resumed")
      self.hookable:emit('resumed', body)
    end
  end, { priority = 1, name = uniqueId .. ".EmitResume" })
end

---@param listener fun(body: dap.StoppedEventBody)
---@param opts? HookOptions
---@return fun()
function Thread:onStopped(listener, opts)
  -- local log = Logger.get("DAP:Thread")
  log:debug("Thread", self.id, "registering onStopped listener")
  return self.session.ref.events:on('stopped', function(body)
    -- log:info("Thread", self.id, "received stopped event for threadId:", body.threadId, "reason:", body.reason, "line:", body.line)
    if body.threadId == self.id then
      -- log:trace("Thread", self.id, "MATCHED - calling listener for stopped event")
      listener(body)
    else
      -- log:trace("Thread", self.id, "no match - ignoring stopped event")
    end
  end, opts)
end

---@param listener fun(body: dap.ContinuedEventBody)
---@param opts? HookOptions
---@return fun()
function Thread:onContinued(listener, opts)
  return self.session.ref.events:on('continued', function(body)
    if body.threadId == self.id then
      listener(body)
    end
  end, opts)
end

---@param listener fun(body: dap.ThreadEventBody)
---@param opts? HookOptions
---@return fun()
function Thread:onExited(listener, opts)
  return self.session.ref.events:on('thread', function(body)
    if body.reason == 'exited' and body.threadId == self.id then
      listener(body)
    end
  end, opts)
end

---@param listener async fun(body: dap.ContinuedEventBody)
---@param opts? HookOptions
---@return fun()
function Thread:onResumed(listener, opts)
  return self.hookable:on('resumed', listener, opts)
end

function Thread:pause()
  return self.session.ref.calls:pause({
    threadId = self.id,
  })
end

function Thread:continue()
  return self.session.ref.calls:continue({
    threadId = self.id,
  })
end

function Thread:stepIn()
  -- local log = Logger.get("DAP:Thread")
  log:info("Thread", self.id, "initiating stepIn")
  local args = {
    threadId = self.id,
    singleThread = true, -- Prevent other threads from resuming during step
    granularity = "line" -- Step by line for proper stepping behavior
  }
  log:debug("stepIn args:", args)
  return self.session.ref.calls:stepIn(args)
end

function Thread:stepOver()
  -- local log = Logger.get("DAP:Thread")
  log:info("Thread", self.id, "initiating stepOver (next command)")
  local args = {
    threadId = self.id,
    singleThread = true, -- Prevent other threads from resuming during step
    granularity = "line" -- Step by line for proper stepping behavior
  }
  log:debug("stepOver args:", args)
  return self.session.ref.calls:next(args)
end

function Thread:stepOut()
  -- local log = Logger.get("DAP:Thread")
  log:info("Thread", self.id, "initiating stepOut")
  local args = {
    threadId = self.id,
    singleThread = true, -- Prevent other threads from resuming during step
    granularity = "line" -- Step by line for proper stepping behavior
  }
  log:debug("stepOut args:", args)
  return self.session.ref.calls:stepOut(args)
end

---@return api.Stack?
function Thread:stack()
  if not self.stopped then
    return nil -- Stack is only available when the thread is stopped
  end

  if self._stack then
    return self._stack
  end

  -- local log = Logger.get("DAP:Thread")
  log:trace("Thread", self.id, "fetching stack trace")
  local stack = self.session.ref.calls:stackTrace({
    threadId = self.id,
    -- levels = 1,
  }):wait()

  log:debug("Thread", self.id, "stack trace received:", stack)
  self._stack = Stack.instanciate(self, stack, self.hookable)

  return self._stack
end

--- Destroys this thread and all its child resources
--- This method ensures complete cleanup of stack and handlers
function Thread:destroy()
  -- Clean up stack if it exists
  if self._stack and self._stack.destroy then
    self._stack:destroy()
  end
  
  -- Clean up our hookable (and all handlers registered on it)
  if self.hookable and not self.hookable.destroyed then
    self.hookable:destroy()
  end
  
  -- Clear references
  self._stack = nil
end

return Thread
