local Class = require("neodap.tools.class")
local Stack = require("neodap.api.Stack")
local Hookable = require("neodap.transport.hookable")

---@class api.ThreadProps
---@field id integer
---@field session api.Session
---@field _stack? api.Stack | nil
---@field hookable Hookable
---@field stopped boolean

---@class api.Thread: api.ThreadProps
---@field new Constructor<api.ThreadProps>
local Thread = Class();


function Thread.instanciate(session, id)
  -- TODO: listen for thread events and clear stack when continued or exited
  -- TODO: add a virtual listener onResumed that allows to hook to a continue only once, ignoring subsequent continues until the next stopped
  local instance = Thread:new({
    id = id,
    session = session,
    _stack = nil,
    hookable = Hookable.create(),
    stopped = false,
  })

  instance:listen() -- Start listening for thread events

  return instance
end

function Thread:listen()
  self:onPaused(function(body)
    self.stopped = true
    if self._stack then
      self._stack:invalidate() -- Invalidate existing stack if paused again
    end
    self._stack = nil          -- Clear stack when stopped
  end, { priority = 1, name = "clear-stack" })

  self:onContinued(function(body)
    if self.stopped then
      if self._stack then
        self._stack:invalidate() -- Invalidate existing stack if paused again
      end
      self._stack = nil        -- Clear stack when continued after a stop
    end
  end, { priority = 1, name = "clear-stack-continued" })


  self:onContinued(function(body)
    -- print("Thread " .. self.id .. " continued\n")
    if self.stopped then
      self.stopped = false
      self.hookable:emit('resumed', body)
    end
  end, { priority = 2, name = "emit-thread-resumed" })
end

---@param listener fun(body: dap.StoppedEventBody)
---@param opts? HookOptions
---@return fun()
function Thread:onPaused(listener, opts)
  return self.session.ref.events:on('stopped', function(body)
    if body.threadId == self.id then
      listener(body)
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
function Thread:onStopped(listener, opts)
  return self.session.ref.events:on('thread', function(body)
    if body.reason == 'exited' and body.threadId == self.id then
      listener(body)
    end
  end, opts)
end

---@param listener fun(body: dap.ContinuedEventBody)
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
  return self.session.ref.calls:stepIn({
    threadId = self.id,
    singleThread = true, -- Prevent other threads from resuming during step
    granularity = "line" -- Step by line for proper stepping behavior
  })
end

function Thread:stepOver()
  return self.session.ref.calls:next({
    threadId = self.id,
    singleThread = true, -- Prevent other threads from resuming during step
    granularity = "line" -- Step by line for proper stepping behavior
  })
end

function Thread:stepOut()
  return self.session.ref.calls:stepOut({
    threadId = self.id,
    singleThread = true, -- Prevent other threads from resuming during step
    granularity = "line" -- Step by line for proper stepping behavior
  })
end

---@return api.Stack?
function Thread:stack()
  if not self.stopped then
    return nil -- Stack is only available when the thread is stopped
  end

  if self._stack then
    return self._stack
  end

  local stack = self.session.ref.calls:stackTrace({
    threadId = self.id,
    -- levels = 1,
  }):wait()

  self._stack = Stack.instanciate(self, stack)

  return self._stack
end

return Thread
