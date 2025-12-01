# DAP Client

A low-level Debug Adapter Protocol (DAP) client implementation for Neovim.

## Overview

The DAP Client provides direct communication with debug adapters using the Debug Adapter Protocol. It handles:

- Protocol message encoding/decoding
- Transport layer abstraction (stdio, TCP, server)
- Request/response correlation
- Event handling
- Automatic timeouts

## Quick Start

```lua
local dap_client = require("dap-client")

-- Start a debug adapter via stdio
local client = dap_client.start("python3", { "-m", "debugpy.adapter" })

-- Send requests
client:request("initialize", {
  clientID = "neovim",
  adapterID = "python",
}, function(err, capabilities)
  if err then
    print("Error:", err)
    return
  end
  print("Capabilities:", vim.inspect(capabilities))
end)

-- Listen for events
client:on("stopped", function(body)
  print("Stopped:", body.reason)
end)

-- Close when done
client:close()
```

## Creating Clients

### stdio (Subprocess)

Launch a debug adapter as a subprocess and communicate via stdin/stdout.

```lua
local client = dap_client.start(command, args, opts)
```

**Parameters:**
- `command` (string): Executable to launch
- `args` (string[]): Command line arguments
- `opts` (table):
  - `cwd` (string): Working directory
  - `on_close` (function): Called when connection closes

**Example:**

```lua
local client = dap_client.start("python3", { "-m", "debugpy.adapter" }, {
  cwd = vim.fn.getcwd(),
  on_close = function()
    print("Connection closed")
  end,
})
```

### tcp (Direct Connection)

Connect to an existing debug adapter server via TCP.

```lua
local client = dap_client.connect(host, port, opts)
```

**Parameters:**
- `host` (string): Server hostname
- `port` (number): Server port
- `opts` (table):
  - `on_close` (function): Called when connection closes

**Example:**

```lua
local client = dap_client.connect("localhost", 5678, {
  on_close = function()
    print("Disconnected")
  end,
})
```

### Using create_adapter

The `create_adapter` function provides a unified interface for all adapter types:

```lua
local adapter = dap_client.create_adapter(config)
local client = adapter.connect()
```

**stdio:**

```lua
local adapter = dap_client.create_adapter({
  type = "stdio",
  command = "python3",
  args = { "-m", "debugpy.adapter" },
  cwd = "/path/to/project",
})
```

**tcp:**

```lua
local adapter = dap_client.create_adapter({
  type = "tcp",
  host = "localhost",
  port = 5678,
})
```

**server:**

Launch a server, parse its output to find the port, then connect via TCP:

```lua
local adapter = dap_client.create_adapter({
  type = "server",
  command = "js-debug-adapter",
  args = { "${port}" },
  cwd = "/path/to/project",
  connect_condition = function(output)
    -- Parse server output to find port
    local port = output:match("Debug server listening at.*:(%d+)")
    return tonumber(port)
  end,
})

local client = adapter.connect()
-- Server auto-terminates when last client closes
```

## Client API

### request(command, arguments, callback?)

Send a DAP request.

```lua
-- With callback
client:request("stackTrace", { threadId = 1 }, function(err, body)
  if err then
    print("Error:", err)
    return
  end
  for _, frame in ipairs(body.stackFrames) do
    print(frame.name)
  end
end)

-- In coroutine context (returns result directly)
local err, body = client:request("stackTrace", { threadId = 1 })
```

**Features:**
- Automatic 30-second timeout
- Supports both callback and coroutine styles
- Full type annotations via overloads

### on(event, handler)

Register an event handler.

```lua
client:on("stopped", function(body)
  print("Thread", body.threadId, "stopped:", body.reason)
end)

client:on("output", function(body)
  print(body.output)
end)
```

**Events:**
- `initialized` - Adapter is ready
- `stopped` - Thread stopped
- `continued` - Thread continued
- `exited` - Debuggee exited
- `terminated` - Session terminated
- `thread` - Thread started/exited
- `output` - Debug output
- `breakpoint` - Breakpoint state changed
- `module` - Module loaded/unloaded
- `loadedSource` - Source loaded/changed/removed
- `process` - Process information
- `capabilities` - Capabilities changed

### on_request(command, handler)

Handle reverse requests from the adapter.

```lua
client:on_request("runInTerminal", function(args)
  -- Launch process in terminal
  local pid = vim.fn.jobstart(args.args, { cwd = args.cwd })
  return { processId = pid }
end)

client:on_request("startDebugging", function(args)
  -- Start child debug session
  return {}
end)
```

### close()

Close the connection.

```lua
client:close()
```

### is_closing()

Check if connection is closing.

```lua
if client:is_closing() then
  print("Connection is shutting down")
end
```

## Type Annotations

The client provides full type annotations for all DAP messages via EmmyLua overloads:

```lua
-- Type-safe request (LSP knows argument and return types)
client:request("setBreakpoints", {
  source = { path = "/path/to/file.py" },
  breakpoints = { { line = 42 } },
}, function(err, body)
  -- body is typed as dap.SetBreakpointsResponseBody
  for _, bp in ipairs(body.breakpoints) do
    print(bp.verified, bp.line)
  end
end)

-- Type-safe events
client:on("stopped", function(body)
  -- body is typed as dap.StoppedEventBody
  print(body.threadId, body.reason, body.text)
end)
```

## DAP Protocol Reference

### Initialization Sequence

```lua
-- 1. Initialize
client:request("initialize", {
  clientID = "neovim",
  clientName = "Neovim DAP",
  adapterID = "python",
  pathFormat = "path",
  linesStartAt1 = true,
  columnsStartAt1 = true,
  supportsVariableType = true,
  supportsRunInTerminalRequest = true,
}, function(err, capabilities)
  -- capabilities contains adapter features
end)

-- 2. Wait for initialized event
client:on("initialized", function()
  -- 3. Set breakpoints
  client:request("setBreakpoints", { ... })

  -- 4. Configuration done
  client:request("configurationDone", {}, function()
    -- Ready to debug
  end)
end)

-- 5. Launch or attach
client:request("launch", {
  request = "launch",
  program = "/path/to/script.py",
})
```

### Common Requests

**Breakpoints:**

```lua
client:request("setBreakpoints", {
  source = { path = "/path/to/file.py" },
  breakpoints = {
    { line = 10 },
    { line = 20, condition = "x > 5" },
    { line = 30, logMessage = "x = {x}" },
  },
}, callback)

client:request("setExceptionBreakpoints", {
  filters = { "raised", "uncaught" },
}, callback)
```

**Execution:**

```lua
client:request("continue", { threadId = 1 }, callback)
client:request("next", { threadId = 1 }, callback)
client:request("stepIn", { threadId = 1 }, callback)
client:request("stepOut", { threadId = 1 }, callback)
client:request("pause", { threadId = 1 }, callback)
```

**State Inspection:**

```lua
client:request("threads", {}, function(err, body)
  for _, thread in ipairs(body.threads) do
    print(thread.id, thread.name)
  end
end)

client:request("stackTrace", {
  threadId = 1,
  startFrame = 0,
  levels = 20,
}, function(err, body)
  for _, frame in ipairs(body.stackFrames) do
    print(frame.name, frame.source.path, frame.line)
  end
end)

client:request("scopes", { frameId = 1 }, function(err, body)
  for _, scope in ipairs(body.scopes) do
    print(scope.name, scope.variablesReference)
  end
end)

client:request("variables", {
  variablesReference = 100,
}, function(err, body)
  for _, var in ipairs(body.variables) do
    print(var.name, var.value, var.type)
  end
end)
```

**Evaluation:**

```lua
client:request("evaluate", {
  expression = "user.name",
  frameId = 1,
  context = "watch",
}, function(err, body)
  print(body.result, body.type)
end)

client:request("setVariable", {
  variablesReference = 100,
  name = "x",
  value = "42",
}, function(err, body)
  print(body.value)
end)
```

**Session Control:**

```lua
client:request("disconnect", {
  terminateDebuggee = true,
}, callback)

client:request("terminate", {}, callback)

client:request("restart", {
  arguments = { ... },  -- Updated launch args
}, callback)
```

## Error Handling

All errors are handled internally and logged at appropriate levels:

- **Decode errors**: WARN level
- **Connection failures**: ERROR level
- **Process crashes**: WARN level
- **Server output**: DEBUG level

```lua
-- Check for errors in callbacks
client:request("stackTrace", { threadId = 999 }, function(err, body)
  if err then
    -- Handle error (e.g., invalid thread ID)
    vim.notify("Error: " .. err, vim.log.levels.ERROR)
    return
  end
  -- Process body
end)
```

## Server Adapter Details

The server adapter type provides automatic server lifecycle management:

```lua
local adapter = dap_client.create_adapter({
  type = "server",
  command = "js-debug-adapter",
  args = {},
  connect_condition = function(output)
    local port = output:match("listening on port (%d+)")
    return tonumber(port)
  end,
})

-- First connect() starts the server
local client1 = adapter.connect()

-- Subsequent connect() reuses existing server
local client2 = adapter.connect()

-- When all clients close, server auto-terminates
client1:close()
client2:close()  -- Server shuts down after this
```

**Features:**
- Server starts on first connection
- Multiple clients can share the server
- Server auto-terminates when last client closes
- 5-second connection timeout
- Server output logged at DEBUG level
