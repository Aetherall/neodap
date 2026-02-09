# Task Backend Design

## Overview

Clean delegation of process and lifecycle management to a task backend (overseer.nvim or built-in), while neodap focuses on DAP protocol and debugging semantics.

---

## Architecture

### Layered Design

```
┌─────────────────────────────────────────────────────┐
│                     neodap                           │
│  DAP protocol, breakpoints, threads, entity graph    │
│                                                      │
│  Session entity ───► threads, frames, variables      │
│        │                                             │
│        └── adapter_task_id, session_task_id          │
└───────────┬─────────────────────────────────────────┘
            │ TaskBackend interface
┌───────────▼─────────────────────────────────────────┐
│                    Backend                           │
│  Process management, lifecycle, templates, UI        │
│                                                      │
│  Implementations:                                    │
│  - neodap.backends.overseer (delegates to overseer)  │
│  - neodap.backends.builtin  (simple built-in)        │
└─────────────────────────────────────────────────────┘
```

### Responsibilities

**neodap owns:**
- DAP protocol handling
- Debugging semantics (breakpoints, stepping, inspection)
- Session entity with DAP state (threads, frames, variables)
- Reactive UI bindings

**Backend owns:**
- Process spawning and management
- Task lifecycle (pending → running → complete → disposed)
- Templates (launch configurations)
- Compound tasks
- Output buffering
- Task UI (listing, selection)
- Persistence (optional)

### Key Insight

The backend is infrastructure that can be swapped. neodap only needs:
1. Process handles for DAP communication
2. Task handles for lifecycle tracking
3. Templates for configuration UI (optional)

Entities like Adapter, SessionConfiguration, and CompoundConfiguration are **not needed** in neodap - the backend manages these concerns.

---

## Backend Interface

### ProcessHandle

Represents a spawned process or network connection for DAP communication.

```lua
---@class neodap.ProcessHandle
---@field task_id number                     -- backend task ID for reference
---@field write fun(data: string)            -- write to stdin/socket
---@field on_data fun(cb: fun(data: string)) -- receive stdout/socket data
---@field on_exit fun(cb: fun(code: number)) -- process exit notification
---@field kill fun()                         -- terminate process/connection
```

### TaskHandle

Represents a managed task for lifecycle tracking.

```lua
---@class neodap.TaskHandle
---@field id number
---@field name string
---@field status string                      -- pending | running | completed | disposed
---@field metadata table                     -- arbitrary data
---@field parent_id number|nil               -- for task hierarchy
---@field start fun()
---@field stop fun()
---@field dispose fun()
---@field get_bufnr fun(): number|nil        -- output buffer
---@field on fun(event: string, cb: fun(...))
```

### TaskBackend

The main interface neodap uses.

```lua
---@class neodap.TaskBackend
-- Process management
---@field spawn fun(opts: SpawnOpts): ProcessHandle      -- spawn process (includes task_id)
---@field connect fun(host: string, port: number): ProcessHandle  -- TCP connection (includes task_id)
---@field run_in_terminal fun(opts: TerminalOpts): { pid: number }  -- for runInTerminal reverse request

-- Task lifecycle
---@field create_task fun(opts: TaskOpts): TaskHandle
---@field list_tasks fun(opts?: ListOpts): TaskHandle[]

-- Template management (optional, for UI integration)
---@field register_template fun(template: TemplateDefinition)
---@field list_templates fun(opts?: SearchOpts): Template[]
---@field run_template fun(name: string, params: table, cb: fun(task: TaskHandle))

-- Events
---@field on fun(event: string, cb: fun(...))  -- task_created, task_started, etc.
```

### SpawnOpts

```lua
---@class neodap.SpawnOpts
---@field cmd string|string[]
---@field args string[]|nil
---@field cwd string|nil
---@field env table<string, string>|nil
---@field on_stdout fun(data: string)|nil
---@field on_stderr fun(data: string)|nil
---@field on_exit fun(code: number)|nil
```

### TerminalOpts

For `runInTerminal` reverse request - runs command in visible/interactive terminal.

```lua
---@class neodap.TerminalOpts
---@field kind "integrated"|"external"|nil  -- terminal type hint
---@field title string|nil                   -- terminal title
---@field cmd string|string[]
---@field args string[]|nil
---@field cwd string|nil
---@field env table<string, string>|nil
```

---

## Session Entity

The only neodap entity needed. Tracks DAP state and links to backend tasks.

```lua
{
  uri = "session://{id}",
  sessionId = "abc123",
  name = "Debug Python",
  state = "running",               -- starting | running | stopped | terminated

  -- Links to backend (not entities, just IDs)
  adapter_task_id = 42,            -- backend task managing adapter process
  session_task_id = 43,            -- backend task for session lifecycle
}
```

**Relationships (existing):**
```lua
Session.threads ←→ Thread.session
Session.breakpointBindings ←→ BreakpointBinding.session
Session.sourceBindings ←→ SourceBinding.session
-- ... etc
```

---

## Data Flow

### Launching a Debug Session

```
1. User selects template from backend (or calls neodap API directly)
         │
         ▼
2. Backend runs template builder, produces config
   - Or: neodap receives config directly
         │
         ▼
3. neodap resolves adapter type from config.type
         │
         ▼
4. neodap calls backend.spawn() or backend.connect()
   - For stdio: spawn adapter process
   - For server: spawn server, wait for port, then connect
   - For tcp: connect to external adapter
   - Returns ProcessHandle
         │
         ▼
5. neodap creates Session entity
   - Stores adapter_task_id from spawn/connect
   - Calls backend.create_task() for session lifecycle tracking
   - Stores session_task_id
         │
         ▼
6. neodap speaks DAP protocol over ProcessHandle
   - initialize → launch/attach → configurationDone
         │
         ▼
7. DAP events update Session's related entities
   - threads, breakpoints, output, etc.
```

### Adapter Lifecycle by Type

**stdio:**
```
backend.spawn(cmd, args) → ProcessHandle
    │
    └── 1:1 with Session
    └── killed when Session terminates
```

**server:**
```
backend.spawn(server_cmd) → ProcessHandle (server process)
    │
    ├── neodap waits for port (connect_condition on stdout)
    │
    └── backend.connect(host, port) → ProcessHandle (per session)
        ├── Session 1
        ├── Session 2
        └── Session N

Server task killed when last Session disconnects
```

**tcp:**
```
backend.connect(host, port) → ProcessHandle
    │
    └── 1:1 with Session
    └── closed when Session terminates
```

### Server Adapter Sharing

neodap decides whether to reuse an existing adapter or spawn a new one. This is DAP/session logic, not backend concern.

```lua
-- neodap internal state for server adapters
local server_adapters = {
  ["pwa-node"] = {
    process = process_handle,      -- from backend.spawn()
    sessions = { session1, session2 },
  }
}

-- When launching a session with server adapter:
-- 1. Check if server_adapters[adapter_type] exists
-- 2. If yes: backend.connect() to existing server
-- 3. If no: backend.spawn() server, wait for port, then backend.connect()

-- When session terminates:
-- 1. Remove from server_adapters[adapter_type].sessions
-- 2. If sessions empty: process_handle:kill()
```

### Dual Tracking (neodap + Backend)

Both neodap and backend track adapter processes, for different purposes:

| Concern | Owner | Why |
|---------|-------|-----|
| Adapter reuse logic | neodap (`server_adapters`) | DAP/session decision |
| Process visibility | Backend (task list) | UI shows running processes |
| Cleanup trigger | neodap | Knows when last session disconnects |
| Actual cleanup | Backend (`process.kill()`) | Owns the process |

They stay in sync:
- neodap calls `backend.spawn()` → backend creates task, returns `ProcessHandle` with `task_id`
- neodap stores `ProcessHandle` in `server_adapters`
- neodap calls `process.kill()` when done → backend cleans up task

This separation keeps DAP logic in neodap while backend provides infrastructure and visibility.

### Config Transformation (`on_config`)

Adapter's `on_config` hook runs in neodap, after receiving config from backend template:

```
Backend template builder
         │
         ▼
    produces config { type = "node", program = "app.js", ... }
         │
         ▼
neodap receives config
         │
         ▼
neodap resolves adapter from config.type
         │
         ▼
adapter.on_config(config)  ← transforms config
         │
         ▼
neodap speaks DAP with transformed config
```

Backend doesn't know about adapter-specific transforms - that's neodap's responsibility.

### Child Sessions (`startDebugging`)

When adapter requests a child session via `startDebugging` reverse request:

```
Parent session already running:
  server ProcessHandle (from spawn)
  session1 ProcessHandle (from connect)
  parent TaskHandle

Adapter sends startDebugging request
         │
         ▼
neodap handles request:
  1. backend.connect(host, port) → session2 ProcessHandle (new connection, same server)
  2. backend.create_task({ parent_id }) → child TaskHandle
  3. Create child Session entity linked to parent
  4. Speak DAP over new ProcessHandle
```

**Key points:**
- Child gets its own `ProcessHandle` (new TCP connection to same server)
- Server process is shared (tracked in neodap's `server_adapters` state)
- Backend task has `parent_id` for hierarchy in task UI
- Each session has independent DAP protocol conversation

```lua
-- In neodap's startDebugging handler:
function handle_start_debugging(parent_session, request)
  local config = request.arguments.configuration

  -- Reuse parent's server (already running)
  local server = server_adapters[config.type]
  local process = backend.connect(server.host, server.port)

  -- Create child task with parent link
  local child_task = backend.create_task({
    name = config.name or "child",
    parent_id = parent_session.session_task_id,
  })

  -- Create child Session entity
  local child_session = Session.new({
    adapter_task_id = server.process.task_id,  -- shared server
    session_task_id = child_task.id,
    parent = parent_session,
  })

  -- Speak DAP over new connection
  dap_initialize(process, config)
end
```

---

## Template Integration

Launch configurations (launch.json, .code-workspace) are registered as **backend templates**.

```lua
-- neodap registers templates with backend
backend.register_template({
  name = "Debug Python",
  params = {
    program = { type = "string", desc = "Python file to debug" },
    args = { type = "list", subtype = { type = "string" } },
  },
  builder = function(params)
    return {
      -- This becomes the DAP launch config
      type = "python",
      request = "launch",
      program = params.program,
      args = params.args,
    }
  end,
})

-- User runs template via backend UI
-- Backend calls builder, passes result to neodap
-- neodap launches debug session with the config
```

### Compound Configurations

Handled entirely by backend. Backend templates can reference other templates:

```lua
backend.register_template({
  name = "Full Stack",
  builder = function(params)
    -- Backend handles launching multiple tasks
    return {
      tasks = {
        { template = "Debug Backend" },
        { template = "Debug Frontend" },
      }
    }
  end,
})
```

---

## Backend Implementations

### overseer backend

```lua
-- neodap.backends.overseer
local M = {}

function M.spawn(opts)
  local task = overseer.new_task({
    cmd = opts.cmd,
    args = opts.args,
    cwd = opts.cwd,
    env = opts.env,
    components = { "default" },
  })
  task:start()

  return {
    write = function(data)
      -- write to task stdin (requires custom component or strategy)
    end,
    on_data = function(cb)
      task:subscribe("on_output", function(_, data)
        cb(table.concat(data))
      end)
    end,
    on_exit = function(cb)
      task:subscribe("on_complete", function()
        cb(task.exit_code or 0)
      end)
    end,
    kill = function()
      task:stop()
    end,
  }
end

function M.connect(host, port)
  -- Use vim.uv.new_tcp() for network connection
  local tcp = vim.uv.new_tcp()
  -- ... connect logic
  return process_handle
end

function M.create_task(opts)
  local task = overseer.new_task({
    name = opts.name,
    cmd = { "true" },  -- no-op command for lifecycle tracking
    metadata = opts.metadata,
  })
  return wrap_task_handle(task)
end

function M.register_template(template)
  overseer.register_template(template)
end

function M.list_templates(opts)
  -- Query overseer templates
end

function M.run_template(name, params, cb)
  overseer.run_task({ name = name, params = params }, cb)
end

return M
```

### builtin backend

Simple implementation using `vim.system()` and internal state.

```lua
-- neodap.backends.builtin
local M = {}
local tasks = {}
local templates = {}
local next_id = 0

function M.spawn(opts)
  local stdout_cb, exit_cb

  local handle = vim.system(
    type(opts.cmd) == "table" and opts.cmd or { opts.cmd },
    {
      args = opts.args,
      cwd = opts.cwd,
      env = opts.env,
      stdin = true,
      stdout = function(err, data)
        if data and stdout_cb then stdout_cb(data) end
      end,
      stderr = function(err, data)
        if data and opts.on_stderr then opts.on_stderr(data) end
      end,
    },
    function(result)
      if exit_cb then exit_cb(result.code) end
    end
  )

  return {
    write = function(data) handle:write(data) end,
    on_data = function(cb) stdout_cb = cb end,
    on_exit = function(cb) exit_cb = cb end,
    kill = function() handle:kill(9) end,
  }
end

function M.connect(host, port)
  local tcp = vim.uv.new_tcp()
  -- ... TCP connection logic
  return process_handle
end

function M.create_task(opts)
  next_id = next_id + 1
  local task = {
    id = next_id,
    name = opts.name,
    status = "pending",
    metadata = opts.metadata or {},
    parent_id = opts.parent_id,
  }
  tasks[task.id] = task
  return wrap_task_handle(task)
end

function M.register_template(template)
  templates[template.name] = template
end

function M.list_templates(opts)
  return vim.tbl_values(templates)
end

function M.run_template(name, params, cb)
  local template = templates[name]
  if template then
    local config = template.builder(params)
    -- Return config to neodap for launching
    cb(config)
  end
end

return M
```

---

## Summary

| Concern | Owner |
|---------|-------|
| DAP protocol | neodap |
| Threads, frames, variables | neodap (Session entity) |
| Breakpoints | neodap |
| Entity graph, reactive UI | neodap |
| Process spawning | Backend |
| Task lifecycle | Backend |
| Templates (launch configs) | Backend |
| Compound configurations | Backend |
| Task UI, persistence | Backend |

**Dropped from neodap:**
- ~~Adapter entity~~ → backend task + `adapter_task_id` on Session
- ~~SessionConfiguration entity~~ → backend templates
- ~~CompoundConfiguration entity~~ → backend compound tasks

---

## Resolved Questions

- [x] **`runInTerminal` reverse request** → `backend.run_in_terminal(opts)` dedicated method
- [x] **Server adapter sharing** → neodap manages internally, decides reuse vs spawn
- [x] **`spawn()` return type** → `ProcessHandle` includes `task_id` field
- [x] **`on_config` timing** → runs in neodap after receiving config from backend
- [x] **`startDebugging` reverse request** → neodap connects to shared server, creates child task with `parent_id`
- [x] **Dual tracking** → neodap tracks for DAP logic, backend tracks for visibility/cleanup; they stay in sync

---

## References

- [overseer.nvim](https://github.com/stevearc/overseer.nvim) - Task runner with template/component system
- overseer Strategy interface: `reset()`, `start(task)`, `stop()`, `dispose()`, `get_bufnr()`
- overseer already has DAP awareness: `dap = true` option for preLaunchTask/postDebugTask
