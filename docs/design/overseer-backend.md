# Overseer Backend Design

## Overview

The Overseer backend integrates neodap with [overseer.nvim](https://github.com/stevearc/overseer.nvim) for task visibility. Debug adapter processes and sessions appear in Overseer's task list.

## Task Types

### dap-process (Adapter Tasks)

Real processes spawned for DAP adapters. Uses a custom Overseer strategy that:
- Runs the adapter command via `vim.system`
- Provides raw stdio access (not terminal-based)
- Exposes `ProcessHandle` for DAP protocol communication or port detection

### dap-session (Session Tasks)

Virtual representation of debug sessions. Uses a simple strategy that:
- Provides `get_bufnr()` returning `dap://stdout/session:<id>`
- Tracks session lifecycle (running → completed)
- No actual process execution

## Adapter Types and Tasks

### stdio adapters (e.g., debugpy)

```
┌─────────────────┐     ┌─────────────────┐
│  dap-process    │     │  dap-session    │
│  (debugpy)      │────▶│  (session)      │
│                 │     │                 │
│  ProcessHandle  │     │  output buffer  │
└─────────────────┘     └─────────────────┘
```

- 1 dap-process task: adapter process (`python -m debugpy.adapter`)
- 1 dap-session task: debug session communicating via stdio

### server adapters (e.g., js-debug)

```
┌─────────────────┐     ┌─────────────────┐
│  dap-process    │     │  dap-session    │
│  (js-debug)     │────▶│  (bootstrap)    │
│                 │     └─────────────────┘
│  ProcessHandle  │     ┌─────────────────┐
│  (port detect)  │────▶│  dap-session    │
└─────────────────┘     │  (debuggee)     │
                        └─────────────────┘
```

- 1 dap-process task: server process
- 2+ dap-session tasks: bootstrap session + debuggee session(s)
- Sessions connect via TCP to the server

### tcp adapters (attach to remote)

```
┌─────────────────┐
│  dap-session    │
│  (session)      │
│                 │
│  output buffer  │
└─────────────────┘
```

- 0 dap-process tasks: no process spawned
- 1+ dap-session tasks: connected via TCP to external adapter

## Backend Interface

```lua
---@class neodap.TaskBackend
local M = {}

--- Spawn adapter process
--- Creates dap-process task in Overseer
---@param opts neodap.SpawnOpts
---@return neodap.ProcessHandle
function M.spawn(opts)
  -- opts.command: string
  -- opts.args: string[]?
  -- opts.cwd: string?
  -- opts.env: table?
  -- opts.name: string?
  -- Returns ProcessHandle for stdio/port detection
end

--- Connect to create a session
--- Creates dap-session task in Overseer
---@param opts neodap.ConnectOpts
---@return neodap.ProcessHandle
function M.connect(opts)
  -- For stdio adapters:
  --   opts.process: ProcessHandle (from spawn)
  --   opts.session_id: string
  --
  -- For server/tcp adapters:
  --   opts.host: string
  --   opts.port: number
  --   opts.session_id: string
  --
  -- Returns ProcessHandle for DAP protocol communication
end

--- Run command in terminal (for runInTerminal reverse request)
---@param opts neodap.RunInTerminalOpts
---@return neodap.TaskHandle
function M.run_in_terminal(opts)
  -- Uses native Overseer terminal task
end
```

## ProcessHandle Interface

```lua
---@class neodap.ProcessHandle
---@field task_id number Overseer task ID
---@field write fun(data: string) Write to stdin
---@field on_data fun(cb: fun(data: string)) Subscribe to stdout
---@field on_stderr fun(cb: fun(data: string)) Subscribe to stderr
---@field on_exit fun(cb: fun(code: number)) Subscribe to exit
---@field kill fun() Terminate the process/session
```

## Overseer Strategies

### overseer/strategy/dap-process.lua

```lua
-- Runs actual adapter process via vim.system
-- Provides ProcessHandle for DAP communication
-- No output buffer (adapter output is DAP protocol, not user-visible)

function M.new(opts)
  return {
    start = function(self, task)
      -- vim.system({ command, args... })
      -- Call opts.on_process(handle) with ProcessHandle
    end,
    get_bufnr = function() return nil end,
    -- ...
  }
end
```

### overseer/strategy/dap-session.lua

```lua
-- Virtual session task (no process execution)
-- Provides output buffer via entity_buffer framework

function M.new(opts)
  return {
    start = function(self, task)
      -- No process to start
      -- Call opts.on_session(handle) with session handle
    end,
    get_bufnr = function()
      -- Return dap://stdout/session:<id> buffer
      local uri = "dap://stdout/session:" .. opts.session_id
      local bufnr = vim.fn.bufnr(uri)
      if bufnr == -1 then
        bufnr = vim.fn.bufadd(uri)
        vim.fn.bufload(bufnr)
      end
      return bufnr
    end,
    -- ...
  }
end
```

## Flow Examples

### stdio adapter (debugpy)

```lua
-- 1. Spawn adapter process
local process = backend.spawn({
  command = "python",
  args = { "-m", "debugpy.adapter" },
  name = "debugpy",
})
-- Creates: dap-process task "debugpy"

-- 2. Create session (wraps process stdio)
local session = backend.connect({
  process = process,
  session_id = "abc123",
  name = "myapp.py",
})
-- Creates: dap-session task "myapp.py"
-- Returns: ProcessHandle using process's stdio
```

### server adapter (js-debug)

```lua
-- 1. Spawn server
local server = backend.spawn({
  command = "js-debug",
  args = { "0" },
  name = "js-debug",
})
-- Creates: dap-process task "js-debug"

-- 2. Detect port from server output
server.on_data(function(data)
  local port = data:match(":(%d+)")
  if port then
    -- 3. Create bootstrap session
    local session1 = backend.connect({
      host = "127.0.0.1",
      port = tonumber(port),
      session_id = "sess1",
      name = "bootstrap",
    })
    -- Creates: dap-session task "bootstrap"
  end
end)

-- 4. Later, js-debug's startDebugging creates child session
local session2 = backend.connect({
  host = "127.0.0.1",
  port = port,
  session_id = "sess2",
  name = "demo.js",
})
-- Creates: dap-session task "demo.js"
```

### tcp adapter (attach to remote)

```lua
-- 1. Connect to remote adapter (no spawn)
local session = backend.connect({
  host = "192.168.1.100",
  port = 9229,
  session_id = "remote1",
  name = "remote debug",
})
-- Creates: dap-session task "remote debug"
-- No dap-process task (adapter is external)
```

## Task List Example

After launching js-debug to debug `demo.js`:

```
Overseer
────────────────────────────
RUNNING  js-debug (adapter)     [dap-process]
RUNNING  bootstrap              [dap-session]
RUNNING  demo.js                [dap-session]  ← output buffer shown
────────────────────────────
```

Selecting "demo.js" shows the session's stdout/console output via `dap://stdout/session:<id>`.
