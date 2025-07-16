local Class = require('neodap.tools.class')
local Connection = require("neodap.adapter.components.connection")
local Executable = require("neodap.adapter.components.executable")
local Logger = require("neodap.tools.logger")



---@class AdapterProps

---@class ExecutableTCPAdapterProps: AdapterProps


---@class ExecutableTCPAdapter: ExecutableTCPAdapterProps
---@field executableOptions ExecutableStartOptions
---@field connectionOptions { host: string, port: integer }
---@field executable Executable?
---@field connection Connection?
---@field new Constructor<ExecutableTCPAdapterProps>
local ExecutableTCPAdapter = Class()


---@class ExecutableTCPAdapterCreateOptions
---@field executable { cmd: string, cwd: string }
---@field connection { host: string, port?: integer }


---@param opts ExecutableTCPAdapterCreateOptions
function ExecutableTCPAdapter.create(opts)
  local port = Connection.get_free_port()

  local instance = ExecutableTCPAdapter:new({
    executableOptions = {
      cmd = opts.executable.cmd,
      args = { tostring(port) },
      cwd = opts.executable.cwd,
    },
    connectionOptions = {
      host = opts.connection.host,
      port = port,
    },
  })

  return instance
end

---@param opts { onMessage: fun(message: dap.AnyIncomingMessage) }
---@return fun(message: dap.AnyOutgoingMessage), fun()
---@async
function ExecutableTCPAdapter:start(opts)
  local boot = not self.executable

  if boot then
    self.executable = Executable.spawn(self.executableOptions)
  end

  if not self.executable then
    local log = Logger.get("Core:Adapter")
    log:error("Failed to start debug adapter executable")
    error("Failed to start executable")
  end


  local connection = Connection.start({
    host = self.connectionOptions.host,
    port = self.connectionOptions.port,
    onMessage = opts.onMessage
  })

  if not connection then
    local log = Logger.get("Core:Adapter")
    local addr = self.connectionOptions.host .. ":" .. self.connectionOptions.port
    log:error("Failed to connect to debug adapter at", addr)
    error("Failed to connect to " .. addr)
  end

  self.executable.usage = self.executable.usage + 1

  -- print("Connected to " .. self.connectionOptions.host .. ":" .. self.connectionOptions.port)


  local close = function()
    self.executable.usage = self.executable.usage - 1
    connection:close()
    if self.executable.usage == 0 then
      self.executable:close()
    end
  end

  local send = function(message)
    if not connection then
      error("Connection is not established")
    end

    connection:send(message)
  end

  return send, close
end

return ExecutableTCPAdapter
