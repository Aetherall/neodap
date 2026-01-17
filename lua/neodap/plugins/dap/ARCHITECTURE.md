# neodap.plugins.dap Architecture

## Purpose

Bridge between `dap-lua` (standalone transport) and `neodap` (SDK entities). This plugin:
- Augments SDK entities with DAP methods
- Manages session lifecycle and state
- Wires DAP events to entity state changes
- Provides fetch methods to hydrate the entity graph from DAP

## Design Principles

### Entity-First

The plugin does not expose a public API. It augments SDK entities:

```lua
-- Plugin augments entities, no separate API
neodap.use(require("neodap.plugins.dap"))

-- Methods are on the entities
local session = debugger:debug(opts)
thread:fetchStackTrace()
session:disconnect()
```

### Synchronous Returns, Async State

`debugger:debug()` returns a Session entity synchronously. The entity's `state` property reflects async progress:

```lua
local session = debugger:debug({
  adapter = { type = "server", ... },
  config = { request = "launch", program = "..." },
})

-- session.state: "starting" → "running" → "stopped" → "terminated"
```

Consumers observe state changes via neograph reactivity, not callbacks.

### Graph as API

Related entities are accessed via neograph edge collections. Fetch methods hydrate the graph:

```lua
thread:fetchStackTrace()  -- Populates graph

for stack in thread.stacks:iter() do
  for frame in stack.frames:iter() do
    print(frame.name:get())
  end
end
```

## Session States

```
starting → running ⇄ stopped → terminated
              ↑_________↓
```

| State | Description |
|-------|-------------|
| `starting` | Connecting to adapter, initializing |
| `running` | Debuggee executing |
| `stopped` | Hit breakpoint, paused |
| `terminated` | Session ended (normal or error) |

On error during `starting`, state transitions to `terminated` with error info.

## Wiring

### debugger:debug() Flow

```
User calls debugger:debug(opts)
         │
         ▼
┌─────────────────────────────────┐
│  1. Create Session entity       │
│     state = "starting"          │
│     debugger.sessions:add(sess) │
└─────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│  2. Call dap-lua.Session.create │
│     opts.adapter                │
│     opts.config                 │
└─────────────────────────────────┘
         │
         ├── on success ──────────────────┐
         │                                ▼
         │                   ┌─────────────────────────┐
         │                   │ 3a. Store DapSession    │
         │                   │     state = "running"   │
         │                   │     Subscribe to events │
         │                   └─────────────────────────┘
         │
         └── on error ────────────────────┐
                                          ▼
                             ┌─────────────────────────┐
                             │ 3b. state = "terminated"│
                             │     Store error info    │
                             └─────────────────────────┘
         │
         ▼
   Return Session entity (sync)
```

### Event → State Mapping

```
DapSession events              Session entity state
─────────────────              ────────────────────
on("stopped")        ────►     state = "stopped"
on("continued")      ────►     state = "running"
on("terminated")     ────►     state = "terminated"
on("exited")         ────►     state = "terminated"
```

### Child Sessions

When DapSession emits `"child"` event (e.g., js-debug's `startDebugging`):

1. Create child Session entity with `state = "starting"`
2. Set `child.parent = parentSession`
3. Add to `parentSession.children`
4. Subscribe to child DapSession events
5. On ready: `state = "running"`

Child sessions appear reactively via neograph.

## Methods Added to Entities

### Debugger

| Method | Description |
|--------|-------------|
| `:debug(opts)` | Start debug session, returns Session entity |

### Session

| Method | Description |
|--------|-------------|
| `:disconnect()` | Disconnect from adapter |
| `:terminate()` | Terminate debuggee |
| `:setBreakpoints(source, breakpoints)` | Set breakpoints for a source |
| `:setExceptionBreakpoints(filters)` | Configure exception breakpoints |

### Thread

| Method | Description |
|--------|-------------|
| `:continue()` | Continue execution |
| `:pause()` | Pause execution |
| `:stepOver()` | Step over |
| `:stepIn()` | Step into |
| `:stepOut()` | Step out |
| `:fetchStackTrace()` | Fetch stack trace, populate Stack/Frame entities |

### Frame

| Method | Description |
|--------|-------------|
| `:fetchScopes()` | Fetch scopes, populate Scope entities |
| `:evaluate(expr, callback)` | Evaluate expression in frame context |

### Scope

| Method | Description |
|--------|-------------|
| `:fetchVariables()` | Fetch variables, populate Variable entities |

### Variable

| Method | Description |
|--------|-------------|
| `:fetchChildren()` | Fetch child variables, populate child Variable entities |
| `:setValue(value, callback)` | Set variable value |

## Internal Storage

The plugin maintains a private mapping between Session entities and DapSession instances:

```lua
-- Private to plugin
local dap_sessions = {}  -- Session entity → DapSession

-- Lookup for forwarding requests
local dap_session = dap_sessions[session_entity]
dap_session.client:request("continue", { threadId = id })
```

## Separation from dap-lua

```
dap-lua (transport layer)        neodap.plugins.dap (integration layer)
─────────────────────────        ────────────────────────────────────────
Pure DAP protocol                Entity state management
Callbacks                        Neograph reactivity
No state concept                 state: starting/running/stopped/terminated
No entity knowledge              Creates/updates entities
Standalone, reusable             Neodap-specific
```
