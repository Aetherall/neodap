local Class = require("neodap.tools.class")
local Stack = require("neodap.api.Stack")

---@class api.ThreadProps
---@field id integer
---@field session api.Session
---@field _stack? api.Stack | nil

---@class api.Thread: api.ThreadProps
---@field new Constructor<api.ThreadProps>
local Thread = Class();


function Thread.instanciate(session, id)
  -- TODO: listen for thread events and clear stack when continued or exited
  -- TODO: add a virtual listener onResumed that allows to hook to a continue only once, ignoring subsequent continues until the next stopped
  return Thread:new({
    id = id,
    session = session,
    _stack = nil,
  })
end

---@param listener fun(body: dap.StoppedEventBody)
function Thread:onStopped(listener, opts)
  return self.session.ref.events:on('stopped', function(body)
    if body.threadId == self.id then
      listener(body)
    end
  end, opts)
end

---@param listener fun(body: dap.ContinuedEventBody)
function Thread:onContinued(listener, opts)
  return self.session.ref.events:on('continued', function(body)
    if body.threadId == self.id then
      listener(body)
    end
  end, opts)
end

function Thread:onExited(listener, opts)
  return self.session.ref.events:on('thread', function(body)
    if body.reason == 'exited' and body.threadId == self.id then
      listener(body)
    end
  end, opts)
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

---@return api.Stack
function Thread:stack()
  -- if self._stack then
  --   return self._stack
  -- end

  local stack = self.session.ref.calls:stackTrace({
    threadId = self.id,
    -- levels = 1,
  }):wait()

  self._stack = Stack.instanciate(self, stack)

  return self._stack
end

return Thread
