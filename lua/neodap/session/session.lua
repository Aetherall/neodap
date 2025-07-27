local Class    = require("neodap.tools.class")
local Events   = require("neodap.transport.events")
local Calls    = require("neodap.transport.calls")
local Handlers = require("neodap.transport.handlers")
local nio      = require("nio")
local Logger   = require("neodap.tools.logger")


---@class SessionProps
---@field id integer
---@field manager Manager
---@field parent Session?
---@field adapter ExecutableTCPAdapter
---@field calls Calls
---@field events Events
---@field handlers Handlers
---@field capabilities? table
---@field children { [integer]: Session }


---@class Session: SessionProps
---@field new Constructor<SessionProps>
local Session = Class()


---@class SessionCreateOptions
---@field manager Manager
---@field adapter ExecutableTCPAdapter
---@field parent Session?

---@param opts SessionCreateOptions
---@return Session
function Session.create(opts)
  local id = opts.manager:generateSessionId()

  local events = Events.create()
  local calls = Calls.create()
  local handlers = Handlers.create()


  local instance = Session:new({
    id = id,
    adapter = opts.adapter,
    events = events,
    calls = calls,
    handlers = handlers,
    children = {},
    manager = opts.manager,
    parent = opts.parent,
  })

  opts.manager:addSession(instance)

  return instance
end

---@class SessionStartOptions
---@field configuration table
---@field request "launch" | "attach"

---@param opts SessionStartOptions
---@async
function Session:Start(opts)
  local send, close = self.adapter:start({
    onMessage = function(message)
      if message.type == "event" then
        -- Enhanced DAP event tracing
        local log = Logger.get("DAP:Session")
        log:debug("Session received DAP event:", message.event)
        log:trace("DAP event body:", message.body or {})

        -- Special attention to thread events that affect stepping
        if message.event == "stopped" then
          log:debug("STOPPED EVENT:", "threadId:", message.body.threadId, "reason:", message.body.reason, "line:",
            message.body.line)
          log:trace("STOPPED EVENT FULL BODY:", message.body)
        elseif message.event == "continued" then
          log:debug("CONTINUED EVENT:", "threadId:", message.body.threadId, "allThreadsContinued:",
            message.body.allThreadsContinued)
        elseif message.event == "breakpoint" then
          log:debug("BREAKPOINT EVENT:", message.body)
        end
        self.events:push(message)
      elseif message.type == "request" then
        self.handlers:receive(message)
      elseif message.type == "response" then
        -- Enhanced DAP response tracing
        local log = Logger.get("DAP:Session")
        log:debug("Session received DAP response:", message.command, "seq:", message.seq, "success:", message.success)
        log:trace("DAP response details:", message)

        -- Special attention to step command responses
        if message.command == "next" or message.command == "stepIn" or message.command == "stepOut" then
          log:debug("STEP RESPONSE IN SESSION:", message.command, "success:", message.success, "body:", message.body)
        end

        self.calls:receive(message)
      else
        local log = Logger.get("Core:Session")
        log:warn("Unknown message type:", message.type)
      end
    end,
  })

  self.handlers:bind(send)
  self.calls:bind(send)

  ---@async
  self.handlers:handle('startDebugging', function(request)
    local child = Session.create({
      manager = self.manager,
      adapter = self.adapter,
      parent = self,
    })

    self.children[child.id] = child

    child:Start(request.arguments)

    self.calls:answer(request, { success = true })
  end)


  self.events:on('terminated', function(body)
    close()
    if self.parent then
      self.parent.children[self.id] = nil
    end
    self.manager:removeSession(self)
    -- print("Session " .. self.id .. " terminated")

    -- Some debug adapters (like js-debug) don't send an 'exited' event
    -- Generate a synthetic one to maintain consistency with DAP spec
    self.events:push({
      event = "exited",
      body = {
        exitCode = 0 -- Default exit code since we don't have the actual one
      }
    })
  end)


  self.capabilities = self.calls:initialize({
    clientID = "neovim",
    adapterID = "js-debug",
    linesStartAt1 = true,
    columnsStartAt1 = true,
    pathFormat = "path",
    supportsVariableType = true,
    supportsVariablePaging = true,
    supportsRunInTerminalRequest = false,
    supportsStartDebuggingRequest = true,
    locale = "en-US",
  }):wait()

  -- print(vim.inspect(self.capabilities))

  if self.capabilities.supportsConfigurationDoneRequest then
    self.calls:configurationDone({}):wait()
  end

  self.calls:launch(opts.configuration):wait()
end

function Session:Close()

end

return Session
