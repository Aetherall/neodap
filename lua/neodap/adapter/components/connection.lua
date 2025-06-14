local Class = require("neodap.tools.class")

local rpc = require("neodap.adapter.components.rpc")
local nio = require("nio")


---@class ConnectionProps
---@field client uv_tcp_t
---@field host string
---@field port integer

---@class Connection: ConnectionProps
---@field new Constructor<ConnectionProps>
local Connection = Class()


---@class ConnectionStartOptions
---@field host string
---@field port integer
---@field onMessage fun(data: dap.AnyIncomingMessage)

---@async
---@param opts ConnectionStartOptions
function Connection.start(opts)
  local client = Connection:connect(opts)
  if not client then
    return nil
  end

  local instance = Connection:new({
    client = client,
    host = opts.host,
    port = opts.port,
  })

  instance:read(
    function(data)
      local payload = vim.json.decode(data)
      opts.onMessage(payload)
    end,
    function()
      -- print("Connection ended")
    end
  )

  return instance
end

---@return nil
function Connection:close()
  if self.client then
    if not self.client:is_closing() then
      self.client:shutdown()
      self.client:close()
      self.client = nil
    end
  end
end

---@async
---@param opts { host: string, port: number }
---@return string|uv_tcp_t
function Connection.attempt(opts)
  local attempt = nio.control.future()
  local client = assert(vim.uv.new_tcp(), "Must be able to create TCP Client")

  client:connect(opts.host, opts.port, function(err)
    if err then
      attempt.set(err)
      client:close()
    else
      attempt.set(client)
    end
  end)

  return attempt:wait()
end

---@async
---@param opts { host: string, port: number }
---@return uv_tcp_t?
function Connection:connect(opts)
  local connection = nio.control.future()

  local attempt = 1;
  local max_attempts = 100;

  ---@async
  nio.run(function()
    while attempt <= max_attempts do
      local result = self.attempt(opts)

      if type(result) ~= "string" then
        return connection.set(result)
      end

      attempt = attempt + 1
      nio.sleep(1000)
    end

    connection:set()
  end)

  return connection:wait()
end

---@param on_data fun(data: string)
---@param on_end fun()
function Connection:read(on_data, on_end)
  self.client:read_start(rpc.create_read_loop(on_data, on_end))
end

local json_encode = vim.json.encode

function Connection:send(request)
  local msg = rpc.msg_with_content_length(json_encode(request))
  if self.client then
    self.client:write(msg)
  end
end

---@return integer
function Connection.get_free_port()
  local tcp = assert(vim.uv.new_tcp(), "Must be able to create tcp client")
  tcp:bind('127.0.0.1', 0)
  local port = tcp:getsockname().port
  tcp:shutdown()
  tcp:close()
  return port
end

return Connection
