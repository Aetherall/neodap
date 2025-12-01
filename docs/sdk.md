# Neodap SDK Reference

The Neodap SDK provides a reactive, high-level API for building debugging experiences in Neovim. It abstracts the Debug Adapter Protocol (DAP) while providing full access to debugging state through reactive primitives.

## Table of Contents

- [Getting Started](#getting-started)
- [Core Concepts](#core-concepts)
- [Debugger](#debugger)
- [Session](#session)
- [Thread](#thread)
- [Stack](#stack)
- [Frame](#frame)
- [Breakpoint](#breakpoint)
- [Variable](#variable)
- [Source](#source)
- [Context](#context)
- [URI System](#uri-system)

## Getting Started

```lua
local debugger = require("neodap")

-- Register debug adapters
debugger:register_adapter("python", {
  type = "stdio",
  command = "python3",
  args = { "-m", "debugpy.adapter" },
})

-- Start debugging (from within a coroutine)
local neostate = require("neostate")
neostate.void(function()
  local session = debugger:start({
    type = "python",
    request = "launch",
    program = "/path/to/script.py",
  })
end)()
```

## Core Concepts

### Reactive State

All state in the SDK is reactive. Instead of polling for changes, you subscribe to state and get notified when it changes:

```lua
-- React to session state changes
session.state:use(function(state)
  print("Session state:", state)  -- "initializing", "running", "stopped", "terminated"
end)

-- React to thread state
thread.state:use(function(state)
  if state == "stopped" then
    local stack = thread:stack()
    print("Stopped at:", stack:top().name)
  end
end)
```

### Lifecycle Management

All SDK objects are `Disposable`. When a parent is disposed, its children are automatically cleaned up:

```
Debugger
  └── Session
        ├── Thread
        │     └── Stack
        │           └── Frame
        │                 ├── Scope
        │                 │     └── Variable
        │                 └── EvaluateResult
        ├── Binding (breakpoint in session)
        └── Output
```

### Entity Store

The SDK maintains a centralized entity store with indexed lookups. Use views to query entities:

```lua
-- Get all stopped threads
local stopped = debugger.threads:where("by_state", "stopped")
for thread in stopped:iter() do
  print(thread.name:get())
end

-- Get frames for a specific session
local frames = debugger.frames:where("by_session_id", session.id)
```

## Debugger

The root object that manages all debug sessions, breakpoints, and global state.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `sessions` | `View<Session>` | All active debug sessions |
| `breakpoints` | `View<Breakpoint>` | All global breakpoints |
| `threads` | `View<Thread>` | All threads across sessions |
| `frames` | `View<Frame>` | All frames across sessions |
| `variables` | `View<Variable>` | All variables across sessions |
| `sources` | `View<Source>` | All source entities |
| `adapters` | `table` | Registered adapter configurations |

### Methods

#### `register_adapter(type, config)`

Register a debug adapter configuration.

```lua
-- stdio adapter (launches process)
debugger:register_adapter("python", {
  type = "stdio",
  command = "python3",
  args = { "-m", "debugpy.adapter" },
})

-- server adapter (launches server, connects via TCP)
debugger:register_adapter("pwa-node", {
  type = "server",
  command = "js-debug-adapter",
  args = { "${port}" },
  connect_condition = function(output)
    local port = output:match("Debug server listening at.*:(%d+)")
    return tonumber(port)
  end,
})

-- tcp adapter (connects to existing server)
debugger:register_adapter("remote", {
  type = "tcp",
  host = "localhost",
  port = 5678,
})
```

#### `start(config)`

Start a debugging session with VSCode-style launch configuration.

**Must be called from within a coroutine** (use `neostate.void()`).

```lua
neostate.void(function()
  local session = debugger:start({
    type = "python",
    request = "launch",  -- or "attach"
    name = "Debug Script",
    program = "/path/to/script.py",
    args = { "--verbose" },
    console = "internalConsole",
  })
end)()
```

#### `create_session(type, parent?)`

Low-level session creation (prefer `start()` for most cases).

```lua
local session = debugger:create_session("python")
session:initialize()
session:launch({ request = "launch", program = "/path/to/script.py" })
```

#### `add_breakpoint(source, line, opts?)`

Create a global breakpoint.

```lua
local bp = debugger:add_breakpoint(
  { path = "/path/to/file.py" },
  42,
  {
    condition = "x > 10",
    logMessage = "x = {x}",
    hitCondition = "5",
  }
)
```

#### `remove_breakpoint(breakpoint)`

Remove a global breakpoint.

```lua
debugger:remove_breakpoint(bp)
```

### Lifecycle Hooks

```lua
-- React to new sessions
debugger:onSession(function(session)
  print("New session:", session.name:get())
end)

-- React to new breakpoints
debugger:onBreakpoint(function(breakpoint)
  print("Breakpoint at:", breakpoint.line)
end)

-- React to new threads (across all sessions)
debugger:onThread(function(thread)
  print("Thread:", thread.name:get())
end)

-- React to new frames (across all sessions)
debugger:onFrame(function(frame)
  print("Frame:", frame.name)
end)

-- React to new stacks (across all sessions)
debugger:onStack(function(stack)
  print("Stack with", #stack.frames, "frames")
end)
```

### Context Management

```lua
-- Get global context
local ctx = debugger:context()

-- Get buffer-specific context
local buf_ctx = debugger:context(bufnr)

-- Resolve contextual URI
local frame = debugger:resolve_one("@frame")
```

## Session

Represents an individual debug session with a debug adapter.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `id` | `string` | Unique session identifier |
| `name` | `Signal<string>` | Session display name |
| `state` | `Signal<SessionState>` | Current state |
| `parent` | `Session?` | Parent session (for child sessions) |
| `capabilities` | `dap.Capabilities` | Adapter capabilities |
| `process_id` | `Signal<number?>` | OS process ID |
| `start_method` | `Signal<string?>` | How session started |

**SessionState**: `"initializing"` | `"running"` | `"stopped"` | `"terminated"`

### Methods

#### `initialize(args?)`

Initialize the debug session.

```lua
local err = session:initialize({
  clientID = "neodap",
  pathFormat = "path",
})
```

#### `launch(config)` / `attach(config)`

Launch or attach to a debuggee.

```lua
session:launch({
  request = "launch",
  program = "/path/to/script.py",
  args = { "--verbose" },
})

session:attach({
  request = "attach",
  processId = 12345,
})
```

#### `continue(thread_id?)`

Continue execution.

```lua
local err, all_continued = session:continue()  -- All threads
local err = session:continue(thread_id)        -- Specific thread
```

#### `disconnect(terminate?)`

Disconnect from the debug adapter.

```lua
session:disconnect()        -- Terminate debuggee
session:disconnect(false)   -- Detach without terminating
```

#### `restart(config?)`

Restart the debug session.

```lua
local new_session, err = session:restart()
```

#### `completions(text, column, opts?)`

Get DAP completions.

```lua
local err, items = session:completions("user.", 6, { frameId = frame.id })
```

#### Accessor Methods

```lua
session:threads()           -- View of threads in this session
session:frames()            -- View of frames in this session
session:bindings()          -- View of breakpoint bindings
session:outputs()           -- View of debug output
session:children()          -- View of child sessions
session:sources()           -- List of sources loaded in session
session:variables()         -- View of variables in session
```

### Lifecycle Hooks

```lua
session:onThread(fn)        -- New threads
session:onBinding(fn)       -- Breakpoint bindings
session:onOutput(fn)        -- Debug output
session:onChild(fn)         -- Child sessions
session:onSource(fn)        -- Loaded sources
session:onRestart(fn)       -- Before restart
session:onRestarted(fn)     -- After restart
```

## Thread

Represents a debug thread.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `id` | `number` | DAP thread ID |
| `global_id` | `string` | Unique ID across sessions |
| `name` | `Signal<string>` | Thread name |
| `state` | `Signal<"running"\|"stopped">` | Thread state |
| `stopReason` | `Signal<string?>` | Why thread stopped |

### Methods

#### `stack()`

Get current stack trace (fetches if needed).

```lua
local stack = thread:stack()
local top_frame = stack:top()
```

#### Stepping Methods

```lua
thread:step_over(granularity?)   -- Next line/statement/instruction
thread:step_into(granularity?)   -- Step into function
thread:step_out(granularity?)    -- Step out of function
thread:pause()                   -- Pause execution
thread:continue()                -- Resume execution
```

**Granularity**: `"statement"` | `"line"` | `"instruction"`

#### `exceptionInfo()`

Get exception details if stopped on exception.

```lua
if thread:stoppedOnException() then
  local info, err = thread:exceptionInfo()
  print(info.description)
end
```

#### Accessor Methods

```lua
thread:frames()          -- All frames (current + historical)
thread:current_frames()  -- Current stack frames only
thread:stacks()          -- All stacks for this thread
thread:stale_stacks()    -- Expired stacks (previous stops)
```

### Lifecycle Hooks

```lua
thread:onStopped(fn)        -- Called with (reason)
thread:onResumed(fn)        -- Called when thread resumes
thread:onStack(fn)          -- Called with (stack)
thread:onFrame(fn)          -- All frames
thread:onCurrentFrame(fn)   -- Current stack frames only
```

## Stack

Represents a stack trace at a point in time.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `id` | `string` | Unique stack identifier |
| `sequence` | `number` | Stack sequence number |
| `reason` | `string` | Why thread stopped |
| `frames` | `Collection<Frame>` | Stack frames |
| `index` | `Signal<number>` | Stack index (0 = current) |

### Methods

```lua
stack:top()           -- Get top frame
stack:is_current()    -- Check if current stack
stack:is_expired()    -- Check if stack is stale
```

### Lifecycle Hooks

```lua
stack:onExpired(fn)   -- Called when stack becomes stale
```

## Frame

Represents a stack frame.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `id` | `number` | DAP frame ID |
| `name` | `string` | Function/method name |
| `line` | `number` | Source line (1-indexed) |
| `column` | `number` | Source column |
| `source` | `Source` | Source entity |
| `endLine` | `number?` | End line |
| `endColumn` | `number?` | End column |
| `location` | `string` | Location key for indexing |

### Methods

#### `scopes()`

Get variable scopes.

```lua
local scopes = frame:scopes()
for scope in scopes:iter() do
  print(scope.name)  -- "Locals", "Globals", etc.
end
```

#### `evaluate(expression, context?, format?)`

Evaluate an expression.

```lua
local result, err = frame:evaluate("user.name", "watch")
print(result.value:get())
```

**Context**: `"watch"` | `"repl"` | `"hover"` | `"clipboard"` | `"variables"`

### Lifecycle Hooks

```lua
frame:onScope(fn)     -- Called with (scope)
```

## Breakpoint

Represents a global breakpoint definition.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `id` | `string` | Unique identifier |
| `source` | `table` | Source location `{ path, name }` |
| `line` | `number` | Line number |
| `column` | `number?` | Column number |
| `enabled` | `Signal<boolean>` | Enabled state |
| `condition` | `Signal<string?>` | Condition expression |
| `logMessage` | `Signal<string?>` | Log message template |
| `hitCondition` | `Signal<string?>` | Hit count condition |

### Binding Properties

When a breakpoint is bound to a session, a `Binding` object is created:

| Property | Type | Description |
|----------|------|-------------|
| `verified` | `Signal<boolean>` | Verified by adapter |
| `actualLine` | `Signal<number?>` | Adjusted line |
| `actualColumn` | `Signal<number?>` | Adjusted column |
| `hit` | `Signal<boolean>` | Currently hit |
| `message` | `Signal<string?>` | Adapter message |

## Variable

Represents a debug variable.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `name` | `string` | Variable name |
| `value` | `Signal<string>` | Current value |
| `type` | `Signal<string?>` | Type name |
| `evaluateName` | `string?` | Expression to evaluate |
| `variablesReference` | `number` | Reference for children |

### Methods

```lua
-- Get child variables (for objects/arrays)
local children = variable:variables()

-- Set variable value
local err = variable:set_value("new value")
```

## Source

Represents a source file (local or virtual).

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `path` | `string?` | Local file path |
| `name` | `string?` | Display name |
| `correlation_key` | `string` | Unique identifier |
| `sourceReference` | `number` | DAP reference (for virtual) |

### Methods

```lua
source:is_virtual()        -- Check if virtual source
source:uri()               -- Get URI (file:// or dap://)
source:location_uri()      -- Get location URI for buffers
source:fetch_content(cb?)  -- Fetch virtual source content
```

## Context

Debug context tracks the "current" frame for operations.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `frame_uri` | `Signal<string?>` | Current frame URI |
| `pinned` | `Signal<boolean>` | Manually pinned |

### Usage

```lua
-- Get current context
local ctx = debugger:context()

-- Get context for specific buffer
local buf_ctx = debugger:context(bufnr)

-- Pin context to specific frame
ctx.frame_uri:set(frame.uri)
ctx.pinned:set(true)

-- Watch context changes
ctx.frame_uri:use(function(uri)
  if uri then
    local frame = debugger:resolve_one(uri)
    print("Context frame:", frame.name)
  end
end)
```

## URI System

Neodap uses URIs to uniquely identify debug entities.

### Absolute URIs

```
dap:                                    -- Debugger root
dap:session:<id>                        -- Specific session
dap:session:<id>/thread:<id>            -- Thread in session
dap:session:<id>/thread:<id>/stack[0]   -- Current stack
dap:session:<id>/thread:<id>/stack[0]/frame[0]  -- Top frame
```

### Index Accessors

```
stack[0]    -- Current (most recent) stack
stack[-1]   -- Previous stack
frame[0]    -- Top frame
frame[1]    -- Second frame
```

### Contextual URIs

Contextual URIs use `@` to reference the current context:

```
@frame              -- Current context frame
@stack              -- Current context stack
@thread             -- Current context thread
@session            -- Current context session
@stack/frame[0]     -- Top frame of context stack
@session/thread     -- All threads in context session
```

### Resolution

```lua
-- Resolve absolute URI
local frame = debugger:resolve_one("dap:session:abc/thread:1/stack[0]/frame[0]")

-- Resolve contextual URI
local frame = debugger:resolve_one("@frame")

-- Resolve to collection
local threads = debugger:resolve("@session/thread")
for thread in threads:iter() do
  print(thread.name:get())
end
```

## Writing Plugins

Plugins are functions that receive the debugger and optional config:

```lua
-- my_plugin.lua
return function(debugger, config)
  config = config or {}

  -- React to sessions
  debugger:onSession(function(session)
    -- React to threads
    session:onThread(function(thread)
      -- React to stops
      thread:onStopped(function(reason)
        print("Stopped:", reason)
      end)
    end)
  end)

  -- Create commands
  vim.api.nvim_create_user_command("MyCommand", function()
    -- Command implementation
  end, {})

  -- Return cleanup function
  return function()
    vim.api.nvim_del_user_command("MyCommand")
  end
end
```

Usage:

```lua
require("my_plugin")(debugger, { option = "value" })
```
