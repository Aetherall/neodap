local function read_content_length()
  local line = io.read("*l")
  if not line then return nil end
  local len = line:match("Content%-Length: (%d+)")
  if len then return tonumber(len) end
  return nil
end

while true do
  local len = read_content_length()
  if not len then break end

  -- Skip empty line
  io.read("*l")

  local body = io.read(len)
  if not body then break end

  -- Simple echo server logic
  -- We need to parse JSON to know if it's a request or notification
  -- But for simplicity, let's just assume we receive valid JSON and reply

  -- We can't easily use vim.json here if running with plain lua, but nvim -l has it.
  -- Let's assume nvim -l

  local ok, msg = pcall(vim.json.decode, body)
  if ok then
    if msg.type == "request" then
      if msg.command == "echo" then
        local response = {
          seq = msg.seq + 100,
          type = "response",
          request_seq = msg.seq,
          command = msg.command,
          success = true,
          body = msg.arguments
        }
        local json = vim.json.encode(response)
        io.write(string.format("Content-Length: %d\r\n\r\n%s", #json, json))
        io.flush()
      elseif msg.command == "trigger" then
        local notif = {
          seq = msg.seq + 101,
          type = "event",
          event = "event",
          body = { data = "fired" }
        }
        local json = vim.json.encode(notif)
        io.write(string.format("Content-Length: %d\r\n\r\n%s", #json, json))
        io.flush()
      elseif msg.command == "reverse" then
        -- Send a reverse request to client
        local req = {
          seq = msg.seq + 102,
          type = "request",
          command = "reverse_echo",
          arguments = { text = "from_server" }
        }
        local json = vim.json.encode(req)
        io.write(string.format("Content-Length: %d\r\n\r\n%s", #json, json))
        io.flush()
        
        -- We also send a response to the original request to finish it
        local response = {
          seq = msg.seq + 103,
          type = "response",
          request_seq = msg.seq,
          command = msg.command,
          success = true,
          body = {}
        }
        local json2 = vim.json.encode(response)
        io.write(string.format("Content-Length: %d\r\n\r\n%s", #json2, json2))
        io.flush()
      end
    end
  end
end
