local Class = require("neodap.tools.class")
local nio = require("nio")


---@class HandlersProps
---@field sequence number
---@field handlers { [dap.AnyReverseRequestCommand]?: fun(message: dap.AnyReverseRequest) }
---@field send fun(message: dap.AnyOutgoingMessage)

---@class Handlers: HandlersProps
---@field new Constructor<HandlersProps>
local Handlers = Class()


function Handlers.create()
  local instance = Handlers:new({
    sequence = 0,
    handlers = {},
    send = function(message)
      error("Session is not bound yet.")
    end,
  })

  return instance
end

---@param sender fun(message: dap.AnyOutgoingMessage)
function Handlers:bind(sender)
  self.send = sender
end

---@param message dap.AnyReverseRequest
function Handlers:receive(message)
  local command = message.command
  local handler = self.handlers[command]

  if handler then
    local args = message.arguments or {}
    nio.run(function()
      handler(message)
    end)
  else
    local response = {
      seq = message.seq,
      type = "response",
      command = command,
      success = false,
      message = "No handler for command: " .. command,
    }
    self.send(response)
  end
end

---@alias Handle<C, A> fun(self: Handlers, command: C, handler: async fun(args: A), opts?: { name?: string, priority?: number, once?: boolean })
---@alias HandleHandlers Handle<'startDebugging', dap.StartDebuggingRequest>| Handle<'runInTerminal', dap.RunInTerminalRequest>

---@type HandleHandlers
function Handlers:handle(command, handler)
  self.handlers[command] = handler
end

return Handlers
