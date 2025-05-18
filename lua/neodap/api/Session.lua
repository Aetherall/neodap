local Class = require("neodap.tools.class")

local Thread = require("neodap.api.Thread")

---@class api.SessionProps
---@field ref Session
---@field threads { [integer]: api.Thread }

---@class api.Session: api.SessionProps
---@field new Constructor<api.SessionProps>
local Session = Class();

---@param ref Session
function Session.wrap(ref)
  ---@type api.Session
  local instance = Session:new({
    ref = ref,
    threads = {},
  })

  instance:listen()

  return instance
end

function Session:listen()
  self.ref.events:on('thread', function(body)
    if body.reason == 'started' then
      local thread = Thread.instanciate(self, body.threadId)
      self.threads[body.threadId] = thread
    end
  end, { name = "SessionThreadStarted", priority = 2 })

  self.ref.events:on('thread', function(body)
    if body.reason == 'exited' then
      self.threads[body.threadId] = nil
    end
  end, { name = "SessionThreadExited", priority = 98 })
end

function Session:onInitialized(listener, opts)
  return self.ref.events:on('initialized', listener, opts)
end

---@param listener fun(body: dap.OutputEventBody)
function Session:onOutput(listener, opts)
  return self.ref.events:on('output', listener, opts)
end

---@param listener fun(thread: api.Thread, body: dap.ThreadEventBody)
---@param opts? { name?: string, priority?: integer, once?: boolean }
function Session:onThread(listener, opts)
  return self.ref.events:on('thread', function(body)
    if body.reason == 'started' then
      listener(self.threads[body.threadId], body)
    end
  end, opts)
end

function Session:onTerminated(listener, opts)
  return self.ref.events:on('terminated', listener, opts)
end

function Session:onExited(listener, opts)
  return self.ref.events:on('exited', listener, opts)
end

return Session
