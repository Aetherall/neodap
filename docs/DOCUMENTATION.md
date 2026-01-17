# neodap Technical Documentation

**Version:** 1.0
**Status:** Production
**License:** MIT

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Core Concepts](#3-core-concepts)
4. [Entity System](#4-entity-system)
5. [Reactivity System](#5-reactivity-system)
6. [Plugin System](#6-plugin-system)
7. [DAP Integration](#7-dap-integration)
8. [Async System](#8-async-system)
9. [Identity System](#9-identity-system)
10. [Context API](#10-context-api)
11. [API Reference](#11-api-reference)
12. [Extension Guide](#12-extension-guide)
13. [Testing](#13-testing)
14. [Configuration](#14-configuration)
15. [Appendices](#15-appendices)

---

## 1. Executive Summary

### 1.1 Overview

neodap is a Debug Adapter Protocol (DAP) client for Neovim, built on a reactive graph database architecture. Unlike traditional debugger implementations that rely on imperative state management, neodap models the entire debug state as a graph of interconnected entities with reactive properties.

### 1.2 Key Features

- **Reactive State Management**: All debug state is stored in a graph database with automatic change propagation
- **Plugin Architecture**: All functionality is provided through composable plugins
- **Entity-Based Design**: Debug concepts (sessions, threads, frames, variables) are first-class entities
- **Dual Identity System**: URIs for stable entity identity, URLs for navigation paths
- **Hierarchical Sessions**: Full support for child debug sessions (e.g., js-debug multi-target)
- **Scoped Subscriptions**: Automatic cleanup of reactive subscriptions

### 1.3 Design Philosophy

neodap separates concerns into distinct layers:

| Layer | Responsibility | Location |
|-------|----------------|----------|
| **Transport** | DAP protocol communication | `lua/dap-lua/` |
| **SDK** | Entity graph and reactivity | `lua/neodap/` |
| **Plugins** | Features and UI | `lua/neodap/plugins/` |
| **Graph DB** | Reactive graph database (vendored) | `lua/neograph/` |

This separation enables:
- Testing transport logic independently from UI
- Swapping transport implementations without affecting the SDK
- Building custom debugging experiences through plugin composition

---

## 2. Architecture Overview

### 2.1 System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Interface                          │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │ tree_buffer │  │ breakpoint   │  │ frame_highlights        │ │
│  │             │  │ _signs       │  │ inline_values           │ │
│  └──────┬──────┘  └──────┬───────┘  └───────────┬─────────────┘ │
└─────────┼────────────────┼──────────────────────┼───────────────┘
          │                │                      │
          ▼                ▼                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Plugin Layer                                 │
│  ┌──────────┐  ┌───────────┐  ┌──────────┐  ┌────────────────┐  │
│  │ dap/     │  │ step_cmd  │  │ bulk_cmd │  │ breakpoint_cmd │  │
│  │ (core)   │  │ control   │  │          │  │ focus_cmd      │  │
│  └────┬─────┘  └─────┬─────┘  └────┬─────┘  └───────┬────────┘  │
└───────┼──────────────┼─────────────┼────────────────┼───────────┘
        │              │             │                │
        ▼              ▼             ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        neodap SDK                                │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                   Entity Graph (neograph)                   │ │
│  │  ┌──────────┐  ┌─────────┐  ┌────────┐  ┌──────────────┐   │ │
│  │  │ Debugger │──│ Session │──│ Thread │──│ Stack/Frame  │   │ │
│  │  └────┬─────┘  └────┬────┘  └────────┘  └──────────────┘   │ │
│  │       │             │                                       │ │
│  │       │             ▼                                       │ │
│  │       │        ┌─────────────┐  ┌────────────────────────┐ │ │
│  │       └───────▶│ Breakpoint  │──│ BreakpointBinding      │ │ │
│  │                └─────────────┘  └────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌──────────────┐  ┌────────────┐  ┌────────────────────────┐   │
│  │ Scoped       │  │ Async      │  │ Identity (URI/URL)     │   │
│  │ Reactivity   │  │ System     │  │ System                 │   │
│  └──────────────┘  └────────────┘  └────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     dap-lua Transport                            │
│  ┌──────────────┐  ┌────────────────┐  ┌─────────────────────┐  │
│  │ DapClient    │  │ Adapters       │  │ DapSession          │  │
│  │ (protocol)   │  │ stdio/tcp/     │  │ (lifecycle)         │  │
│  │              │  │ server         │  │                     │  │
│  └──────────────┘  └────────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  Debug Adapter   │
                    │  (debugpy,       │
                    │   js-debug, etc) │
                    └──────────────────┘
```

### 2.2 Data Flow

```
User Action (e.g., toggle breakpoint)
        │
        ▼
Vim Command (e.g., :Dap breakpoint toggle)
        │
        ▼
Entity Method (e.g., Debugger:toggleBreakpoint)
        │
        ▼
Graph Mutation (entity creation/update)
        │
        ├──────────────────────────────────┐
        ▼                                  ▼
DAP Request (setBreakpoints)         Reactive Signal
        │                                  │
        ▼                                  ▼
Debug Adapter                        UI Update (signs, tree)
        │
        ▼
DAP Event (breakpoint verified)
        │
        ▼
Entity Update (BreakpointBinding.verified = true)
        │
        ▼
Reactive Signal Propagation
        │
        ▼
UI Update (sign changes from ● to ◉)
```

### 2.3 Directory Structure

```
neodap/
├── lua/
│   ├── neodap/                      # Main SDK
│   │   ├── init.lua                 # Entry point: setup(), use(), createDebugger()
│   │   ├── schema.lua               # neograph schema definition (JSON)
│   │   ├── entity.lua               # Entity class factory
│   │   ├── uri.lua                  # URI builders and parsers
│   │   ├── async.lua                # Coroutine-based async system
│   │   ├── scoped.lua               # Scoped reactivity wrapper
│   │   ├── derive.lua               # Derived signals
│   │   ├── ctx.lua                  # Focus/context management
│   │   ├── location.lua             # Location value object (path:line:column)
│   │   ├── entities/                # Entity class definitions
│   │   │   ├── init.lua             # Entity class instantiation
│   │   │   ├── debugger.lua         # Debugger methods
│   │   │   ├── session.lua          # Session methods
│   │   │   ├── thread.lua           # Thread methods
│   │   │   ├── frame.lua            # Frame methods
│   │   │   ├── scope.lua            # Scope methods
│   │   │   ├── variable.lua         # Variable methods
│   │   │   ├── source.lua           # Source methods
│   │   │   ├── breakpoint.lua       # Breakpoint methods
│   │   │   └── ...                  # Other entity definitions
│   │   ├── identity/                # URI/URL query system
│   │   │   ├── init.lua             # Identity installation
│   │   │   ├── url.lua              # URL parsing and resolution
│   │   │   ├── wrappers.lua         # Signal wrappers for URLs
│   │   │   └── filter.lua           # URL query filtering
│   │   └── plugins/                 # Feature plugins
│   │       ├── dap/                 # Core DAP integration
│   │       │   ├── init.lua         # Session management, event wiring
│   │       │   ├── thread.lua       # Thread DAP methods
│   │       │   ├── frame.lua        # Frame DAP methods
│   │       │   ├── scope.lua        # Scope DAP methods
│   │       │   ├── variable.lua     # Variable DAP methods
│   │       │   ├── breakpoint.lua   # Breakpoint sync logic
│   │       │   ├── session.lua      # Session DAP methods
│   │       │   ├── source.lua       # Source DAP methods
│   │       │   ├── context.lua      # Shared plugin state
│   │       │   └── utils.lua        # Utility functions
│   │       ├── tree_buffer/         # Tree view UI
│   │       ├── utils/               # Shared plugin utilities
│   │       ├── bulk_cmd.lua         # Enable/disable/remove
│   │       ├── step_cmd.lua         # Step over/in/out
│   │       ├── control_cmd.lua      # Continue/pause/terminate
│   │       ├── breakpoint_cmd.lua   # Breakpoint management
│   │       ├── breakpoint_signs.lua # Breakpoint visual indicators
│   │       ├── frame_highlights.lua # Active frame highlighting
│   │       ├── inline_values.lua    # Variable values in editor
│   │       └── ...                  # Other plugins
│   ├── dap-lua/                     # Standalone DAP transport
│   │   ├── init.lua                 # Client creation, adapters
│   │   ├── protocol.lua             # DAP type definitions
│   │   └── session.lua              # DapSession lifecycle
│   ├── neoword/                     # CVCVC word generator
│   │   └── init.lua                 # Deterministic session ID generation
│   ├── code-workspace/              # VS Code workspace parser
│   │   ├── init.lua
│   │   ├── parser.lua
│   │   └── interpolate.lua
│   └── neograph/                    # Reactive graph database (vendored)
│       ├── init.lua                 # Graph creation and API
│       ├── compliance.lua           # Compliance test suite
│       ├── SPEC.md                  # API specification
│       └── COMPLIANCE.md            # Compliance documentation
└── tests/                           # Test suite
    ├── init.lua                     # Test bootstrap
    ├── parallel.lua                 # Parallel test runner
    ├── helpers/                     # Test utilities
    └── ...                          # Test files
```

---

## 3. Core Concepts

### 3.1 The Debugger Singleton

The debugger is the root entity that owns all debug state. It is created during `neodap.setup()`:

```lua
local neodap = require("neodap")

-- Setup returns the debugger instance
local debugger = neodap.setup({
  adapters = {
    python = { type = "server", command = "python", args = { "-m", "debugpy.adapter" } },
    ["pwa-node"] = { type = "server", command = "js-debug-adapter" },
  },
})

-- Or access via neodap.debugger
local debugger = neodap.debugger

-- Or create an isolated debugger (for testing)
local isolated = neodap.createDebugger({})
```

### 3.2 Entity Graph Model

Debug state is modeled as a graph of entities connected by edges:

```
Debugger (singleton root)
├── sessions → Session
│   ├── threads → Thread
│   │   └── stacks → Stack
│   │       └── frames → Frame
│   │           ├── scopes → Scope
│   │           │   └── variables → Variable
│   │           └── source → Source (reference)
│   ├── sourceBindings → SourceBinding
│   ├── outputs → Output
│   ├── exceptionFilters → ExceptionFilter
│   └── children/parent → Session (hierarchical)
├── sources → Source
│   └── breakpoints → Breakpoint
│       └── bindings → BreakpointBinding
├── breakpoints → Breakpoint (all breakpoints)
├── sessionsGroup → Sessions (UI grouping)
├── breakpointsGroup → Breakpoints (UI grouping)
└── targets → Targets (leaf sessions UI grouping)
```

### 3.3 Signals and Reactivity

Every entity property is a reactive signal:

```lua
-- Get current value
local name = session.name:get()

-- Set value
session.name:set("New Name")

-- Subscribe to changes (runs immediately, then on each change)
session.name:use(function(value)
  print("Session name changed to:", value)
  -- Return cleanup function (optional)
  return function()
    print("Cleanup called")
  end
end)

-- Update multiple properties atomically
session:update({
  name = "New Name",
  state = "running",
})
```

### 3.4 Edges and Collections

Edges connect entities and provide iteration:

```lua
-- Iterate over all threads in a session
for thread in session.threads:iter() do
  print(thread.name:get())
end

-- Subscribe to edge changes (runs for each item, cleanup when removed)
session.threads:each(function(thread)
  print("Thread added:", thread.name:get())
  return function()
    print("Thread removed")
  end
end)

-- Link entities
session.threads:link(new_thread)

-- Unlink entities
session.threads:unlink(old_thread)
```

### 3.5 Rollups

Rollups are computed properties derived from edges:

```lua
-- Reference rollup (single entity)
local first_thread = session.firstThread:get()
local stopped_thread = session.firstStoppedThread:get()

-- Property rollup (computed value)
local thread_count = session.threadCount:get()
local has_stopped = session.hasStoppedThread:get()

-- Collection rollup (filtered iteration)
for thread in session.stoppedThreads:iter() do
  print(thread.name:get())
end
```

---

## 4. Entity System

### 4.1 Schema Definition

The entity schema is defined in `lua/neodap/schema.lua` using neograph's JSON schema format:

```lua
M.schema = {
  types = {
    {
      name = "Session",
      properties = {
        { name = "uri", type = "string" },
        { name = "sessionId", type = "string" },
        { name = "name", type = "string" },
        { name = "state", type = "string" },
        { name = "leaf", type = "bool" },
      },
      edges = {
        { name = "threads", target = "Thread", reverse = "sessions",
          indexes = {
            { name = "by_threadId", fields = {{ name = "threadId" }} },
            { name = "by_state", fields = {{ name = "state" }} },
          }},
        -- ... more edges
      },
      indexes = {
        { name = "default", fields = {{ name = "uri" }} },
        { name = "by_sessionId", fields = {{ name = "sessionId" }} },
      },
      rollups = {
        { kind = "reference", name = "firstThread", edge = "threads" },
        { kind = "reference", name = "firstStoppedThread", edge = "threads",
          filters = {{ field = "state", value = "stopped" }} },
        { kind = "property", name = "threadCount", edge = "threads", compute = "count" },
        { kind = "collection", name = "stoppedThreads", edge = "threads",
          filters = {{ field = "state", value = "stopped" }} },
      },
    },
    -- ... more entity types
  },
}
```

### 4.2 Entity Types

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| **Debugger** | Root singleton | `focusedUrl` |
| **Session** | Debug session | `sessionId`, `name`, `state`, `leaf` |
| **Thread** | Execution thread | `threadId`, `name`, `state`, `focused`, `stops` |
| **Stack** | Stack snapshot at stop | `index`, `seq` |
| **Frame** | Stack frame | `frameId`, `index`, `name`, `line`, `column`, `active` |
| **Scope** | Variable scope | `name`, `presentationHint`, `variablesReference` |
| **Variable** | Variable | `name`, `value`, `varType`, `variablesReference` |
| **Source** | Source file | `key`, `path`, `name`, `content` |
| **SourceBinding** | Source per session | `sourceReference` |
| **Breakpoint** | Breakpoint definition | `line`, `column`, `condition`, `enabled` |
| **BreakpointBinding** | Breakpoint per session | `breakpointId`, `verified`, `hit`, `actualLine` |
| **Output** | Debug output | `text`, `category`, `seq` |
| **ExceptionFilter** | Exception configuration | `filterId`, `label`, `enabled` |

### 4.3 Entity Creation

Entities are created via their class constructors:

```lua
local entities = require("neodap.entities")
local uri = require("neodap.uri")

-- Create a session
local session = entities.Session.new(graph, {
  uri = uri.session("xotat"),
  sessionId = "xotat",
  name = "Python Debug",
  state = "starting",
  leaf = true,
})

-- Link to debugger
debugger.sessions:link(session)
```

### 4.4 Entity Methods

Each entity class has methods defined in separate files:

```lua
-- Session methods (lua/neodap/entities/session.lua)
function Session:isRunning()
  return self.state:get() == "running"
end

function Session:isStopped()
  return self.state:get() == "stopped"
end

function Session:findThreadById(threadId)
  for thread in self.threads:iter() do
    if thread.threadId:get() == threadId then
      return thread
    end
  end
end
```

### 4.5 Common Entity Methods

All entities share common methods from `entity.lua`:

```lua
entity:id()        -- Returns internal entity ID
entity:type()      -- Returns entity type name (e.g., "Session")
entity:graph()     -- Returns the graph instance
entity:isDeleted() -- Check if entity has been deleted
entity:update(props) -- Update multiple properties
entity:delete()    -- Delete the entity
```

---

## 5. Reactivity System

### 5.1 Scoped Reactivity

The scoped reactivity system (`lua/neodap/scoped.lua`) provides automatic subscription cleanup:

```lua
local scoped = require("neodap.scoped")

-- Create a new scope
local scope = scoped.push()

-- Subscriptions within this scope auto-register for cleanup
session.name:use(function(name)
  print("Name:", name)
end)

-- Cancel scope - all subscriptions are cleaned up
scope:cancel()
```

### 5.2 Scope Hierarchy

Scopes form a hierarchy. Canceling a parent cancels all children:

```lua
local parent = scoped.push()
  local child1 = scoped.push()
    -- subscriptions in child1
  scoped.pop()
  local child2 = scoped.push()
    -- subscriptions in child2
  scoped.pop()
scoped.pop()

-- Canceling parent cancels child1 and child2
parent:cancel()
```

### 5.3 Plugin Scope

Plugins run within a dedicated scope attached to the debugger:

```lua
function debugger:use(plugin, config)
  local result
  scoped.withScope(debugger._scope, function()
    result = plugin(debugger, config)
  end)
  return result
end
```

### 5.4 Derived Signals

Create computed values that update when dependencies change:

```lua
local derive = require("neodap.derive")

-- Derive from explicit dependencies
local fullName = derive.from(
  { session.name, session.sessionId },
  function()
    return session.name:get() .. " (" .. session.sessionId:get() .. ")"
  end
)

fullName:use(function(value)
  print("Full name:", value)
end)
```

### 5.5 flatMap for Dynamic Signals

Switch between signals based on another signal's value:

```lua
local scoped = require("neodap.scoped")

-- Watch the focused thread's state (changes when focus changes)
local threadState = scoped.flatMap(
  debugger.focusedUrl,
  function(url)
    local thread = debugger.ctx.thread:get()
    return thread and thread.state
  end
)
```

---

## 6. Plugin System

### 6.1 Design Philosophy

Plugins expose functionality through **Neovim-native mechanisms** (vim commands), not Lua APIs. The primary user interface is:

```vim
:Dap <subcommand> [args]
```

The `command_router` plugin provides unified command routing with auto-discovery and completion. Each plugin registers `Dap<Name>` commands that are automatically available via `:Dap <name>`.

### 6.2 Primary Interface: Vim Commands

```vim
" Execution control
:Dap continue                         " Continue focused thread
:Dap continue @session/threads        " Continue all threads in session
:Dap pause                            " Pause focused thread
:Dap step over                        " Step over
:Dap step into                        " Step into
:Dap step out                         " Step out
:Dap step over line                   " Step with line granularity
:Dap terminate                        " Terminate focused session

" Breakpoints
:Dap breakpoint                       " Toggle at cursor
:Dap breakpoint toggle                " Toggle at cursor
:Dap breakpoint toggle 42             " Toggle at line 42
:Dap breakpoint condition 42 x > 5    " Set conditional breakpoint
:Dap breakpoint log 42 Value: {x}     " Set logpoint
:Dap breakpoint enable                " Enable at cursor
:Dap breakpoint disable               " Disable at cursor
:Dap breakpoint clear                 " Clear all breakpoints

" Focus navigation
:Dap focus frame up                   " Move focus up stack
:Dap focus frame down                 " Move focus down stack
:Dap focus thread next                " Next thread
:Dap focus session next               " Next session

" Other
:Dap jump                             " Jump to cursor location
:Dap run-to-cursor                    " Run to cursor
:Dap list breakpoints                 " List breakpoints in quickfix
:Dap list sessions                    " List sessions in quickfix
```

Commands support **URL targeting** for batch operations:

```vim
:Dap continue @session/threads              " All threads in focused session
:Dap continue sessions/threads              " All threads in all sessions
:Dap pause @session/threads(state=running)  " Only running threads
:Dap step over @session/threads(state=stopped)
```

### 6.3 Command Routing Architecture

The `command_router` plugin creates a unified `:Dap` command that:

1. **Discovers** available commands by scanning for `Dap*` user commands
2. **Routes** subcommands by converting to PascalCase: `step` → `DapStep`
3. **Provides completion** by listing discovered subcommands

```
:Dap step into
     │    │
     │    └─► Arguments passed to DapStep
     │
     └─► Routes to :DapStep (discovered via nvim_get_commands)
```

Plugins register their own commands:

```lua
-- In step_cmd plugin
vim.api.nvim_create_user_command("DapStep", function(opts)
  -- Handle :DapStep over/into/out
end, { nargs = "*", desc = "Step debugger" })
```

### 6.4 Loading Plugins

Plugins are loaded with `debugger:use()`. The `neodap.plugins.*` table provides lazy-loaded access to built-in plugins:

```lua
local neodap = require("neodap")
local debugger = neodap.setup({
  adapters = {
    python = { type = "server", command = "python", args = { "-m", "debugpy.adapter" } },
  },
})

-- Load plugins (registers their vim commands)
debugger:use(neodap.plugins.dap)           -- Core DAP
debugger:use(neodap.plugins.command_router)       -- :Dap router
debugger:use(neodap.plugins.control_cmd)  -- :DapContinue, :DapPause
debugger:use(neodap.plugins.step_cmd)      -- :DapStep
debugger:use(neodap.plugins.breakpoint_cmd) -- :DapBreakpoint

-- UI plugins (no commands, just reactive behavior)
debugger:use(neodap.plugins.breakpoint_signs)
debugger:use(neodap.plugins.frame_highlights)
debugger:use(neodap.plugins.inline_values)

-- With configuration
debugger:use(neodap.plugins.tree_buffer, {
  icons = { expanded = "▼", collapsed = "▶" },
})
```

### 6.5 Lua API (Advanced)

Plugins may return a Lua API for cases requiring **non-serializable parameters** (callbacks, entities). This is not the primary interface:

```lua
-- Only use Lua API when you need callbacks or programmatic control
local bp_api = neodap.use(require("neodap.plugins.breakpoint_cmd"), {
  -- Custom disambiguator needs callback
  disambiguate = function(candidates, location, action, callback)
    -- Show picker UI, call callback with selected breakpoint
    show_picker(candidates, function(selected)
      callback(nil, selected)
    end)
  end,
})
```

The Lua API is for:
- Passing callbacks (disambiguation, custom handlers)
- Programmatic integration from other plugins
- Testing

For normal usage, prefer vim commands.

### 6.6 Plugin Contract

Plugins that provide user-facing functionality must:

1. **Register** `Dap<Name>` vim commands
2. **Support** URL arguments where applicable (for batch operations)
3. **Provide** completion for their arguments

Plugins may optionally:
- Return a Lua API for advanced use cases
- Accept configuration via the second argument to `neodap.use()`
- Register autocommands for reactive behavior

### 6.7 Built-in Plugins Reference

| Plugin | Commands | Purpose |
|--------|----------|---------|
| `dap` | *(entity methods)* | Core DAP integration |
| `command_router` | `:Dap` | Unified command router |
| `control_cmd` | `:DapContinue`, `:DapPause`, `:DapTerminate` | Execution control |
| `step_cmd` | `:DapStep` | Step over/into/out |
| `breakpoint_cmd` | `:DapBreakpoint` | Breakpoint management |
| `bulk_cmd` | `:DapToggle` | Start/stop debugging |
| `focus_cmd` | `:DapFocus` | Focus navigation |
| `jump_cmd` | `:DapJump` | Jump to location |
| `run_to_cursor_cmd` | `:DapRunToCursor` | Run to cursor |
| `exception_cmd` | `:DapException` | Exception breakpoints |
| `list_cmd` | `:DapList` | List entities to quickfix |
| `tree_buffer` | *(buffer scheme)* | Tree view UI (`dap://tree/`) |
| `source_buffer` | *(buffer scheme)* | Source viewing (`dap://source/`) |
| `url_buffer` | *(buffer scheme)* | URL-based buffers |
| `breakpoint_signs` | *(reactive)* | Breakpoint visual indicators |
| `frame_highlights` | *(reactive)* | Active frame highlighting |
| `inline_values` | *(reactive)* | Variable values in editor |
| `replline` | *(buffer)* | REPL input buffer |
| `jump_stop` | *(reactive)* | Jump to location on stop |
| `auto_context` | *(reactive)* | Automatic focus management |
| `stack_nav` | `:DapStackNav` | Stack navigation |
| `variable_edit` | *(interactive)* | Variable modification |
| `completion` | *(completion source)* | REPL completions |
| `leaf_session` | *(reactive)* | Leaf session tracking |
| `code_workspace` | *(integration)* | VS Code workspace support |
| `uri_picker` | *(picker)* | URI selection UI |
| `hit_polyfill` | *(polyfill)* | Hit breakpoint compatibility |

---

## 7. DAP Integration

### 7.1 dap-lua Transport Layer

The `dap-lua` module provides standalone DAP transport with no neodap dependencies:

```lua
local dap = require("dap-lua")

-- Create adapter
local adapter = dap.adapter({
  type = "stdio",
  command = "python",
  args = { "-m", "debugpy.adapter" },
})

-- Alternative: TCP adapter
local tcp_adapter = dap.adapter({
  type = "tcp",
  host = "127.0.0.1",
  port = 5678,
})

-- Alternative: Server adapter (launches server, connects via TCP)
local server_adapter = dap.adapter({
  type = "server",
  command = "js-debug-adapter",
  args = {},
  connect_condition = function(chunk)
    local port = chunk:match("Listening on port (%d+)")
    return port and tonumber(port)
  end,
})
```

### 7.2 DapClient

The `DapClient` provides type-safe DAP communication:

```lua
---@class DapClient
---@field request fun(command, arguments, callback)
---@field on fun(event, handler)
---@field on_request fun(command, handler)
---@field close fun()

-- Example: Send a request
client:request("setBreakpoints", {
  source = { path = "/path/to/file.py" },
  breakpoints = { { line = 10 } },
}, function(err, body)
  if err then
    print("Error:", err)
  else
    print("Breakpoints set:", vim.inspect(body.breakpoints))
  end
end)

-- Example: Subscribe to event
client:on("stopped", function(body)
  print("Stopped:", body.reason)
end)

-- Example: Handle reverse request
client:on_request("runInTerminal", function(args, respond)
  -- Launch terminal...
  respond({ processId = pid }, nil)
end)
```

### 7.3 DapSession

The `DapSession` wraps client lifecycle:

```lua
local DapSession = require("dap-lua.session")

DapSession.create({
  adapter = adapter,
  config = {
    type = "python",
    request = "launch",
    program = "main.py",
  },
  handlers = {
    onSessionCreated = function(session)
      -- Called before initialization
    end,
    beforeConfigurationDone = function(session, done)
      -- Set breakpoints here
      done()
    end,
    runInTerminal = function(args, callback)
      -- Custom terminal handler
    end,
  },
}, function(err, session)
  if err then
    print("Session failed:", err)
  else
    print("Session ready")
  end
end)
```

### 7.4 Session Lifecycle

```
┌─────────────────┐
│ adapter:connect │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ onSessionCreated│ ← Entity creation happens here
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   initialize    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  launch/attach  │ ← Sent in parallel with waiting for initialized
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   initialized   │ ← Event from adapter
└────────┬────────┘
         │
         ▼
┌───────────────────────┐
│ beforeConfigurationDone│ ← Breakpoint sync happens here
└────────┬──────────────┘
         │
         ▼
┌─────────────────────┐
│ configurationDone   │
└────────┬────────────┘
         │
         ▼
┌─────────────────┐
│  Session Ready  │
└────────┬────────┘
         │
         ▼
    [Debugging]
         │
         ▼
┌─────────────────┐
│ terminate/      │
│ disconnect      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Session Closed  │
└─────────────────┘
```

### 7.5 Child Sessions

Some adapters (like js-debug) spawn child sessions:

```lua
-- Parent session receives "child" event
session:on("child", function(child_session)
  -- child_session has its own client, events, etc.
end)

-- Session hierarchy is maintained
session.parent   -- nil for root sessions
session.children -- array of child sessions
session.depth    -- 0 for root, increments for children
```

### 7.6 Entity Event Wiring

The DAP plugin wires DAP events to entity state updates:

```lua
-- In neodap.plugins.dap.init.lua
dap_session:on("stopped", function(body)
  session:update({ state = "stopped" })

  -- Update thread state
  if body.threadId then
    local thread = session:findThreadById(body.threadId)
    if thread then
      thread:update({ state = "stopped", stops = thread.stops:get() + 1 })
      thread:fetchStackTrace()
    end
  end

  -- Mark hit breakpoints
  if body.hitBreakpointIds then
    -- ... update breakpoint bindings
  end
end)

dap_session:on("continued", function(body)
  session:update({ state = "running" })
  -- Clear hit states
end)

dap_session:on("terminated", function(body)
  session:update({ state = "terminated" })
  -- Cleanup bindings
end)
```

---

## 8. Async System

### 8.1 Overview

The async system (`lua/neodap/async.lua`) provides coroutine-based async/await:

```lua
local a = require("neodap.async")

-- Run async function
a.run(function()
  local result = a.wait(function(cb)
    some_async_operation(cb)
  end)
  print("Result:", result)
end)
```

### 8.2 Core Functions

#### a.run(fn, callback, parent_ctx)

Start a new async context:

```lua
local task = a.run(function()
  return "result"
end, function(err, result)
  if err then
    print("Error:", err)
  else
    print("Success:", result)
  end
end)

-- Task can be cancelled
task:cancel()

-- Task is also awaitable
local result = a.wait(task)
```

#### a.wait(fn, label)

Wait for a callback-based operation:

```lua
local body = a.wait(function(cb)
  client:request("threads", {}, cb)
end, "fetchThreads")
```

#### a.wait_all(fns, label)

Wait for multiple operations in parallel:

```lua
local results = a.wait_all({
  a.run(function() return fetch_a() end),
  a.run(function() return fetch_b() end),
  a.run(function() return fetch_c() end),
}, "fetchAll")
-- results = { result_a, result_b, result_c }
```

### 8.3 Context and Cancellation

Each async chain has a context that supports cancellation:

```lua
local task = a.run(function()
  while true do
    -- Check for cancellation
    local ctx = a.context()
    if ctx and ctx:done() then
      break
    end

    a.wait(some_operation)
  end
end)

-- Cancel the task
task:cancel()
```

### 8.4 Cleanup Functions

Register cleanup handlers that run on cancellation:

```lua
local ctx = a.context()
ctx:onCleanup(function()
  -- Cleanup resources
end)
```

### 8.5 Method Wrappers

#### a.fn(fn)

Wrap function to run inline if in async context, or spawn context if sync:

```lua
Thread.continue = a.fn(function(self)
  a.wait(function(cb)
    client:request("continue", { threadId = self.threadId:get() }, cb)
  end)
end)

-- Can be called from sync or async context
thread:continue()
```

#### a.memoize(fn)

Coalesce concurrent calls to the same method:

```lua
Thread.fetchStackTrace = a.memoize(function(self)
  -- Expensive operation
end)

-- Concurrent calls to same thread coalesce to single operation
thread:fetchStackTrace()
thread:fetchStackTrace() -- Waits for first call
```

### 8.6 Synchronization Primitives

#### Event

One-shot event for coordination:

```lua
local event = a.event()

-- In one coroutine
a.wait(event.wait)

-- In another coroutine
event:set(value)
```

#### Mutex

Serialize access to shared resources:

```lua
local mutex = a.mutex()

a.wait(mutex.lock)
-- Critical section
mutex:unlock()
```

#### Timeout

Wrap operation with timeout:

```lua
local result = a.timeout(5000, function(cb)
  slow_operation(cb)
end)
```

---

## 9. Identity System

### 9.1 URI vs URL

neodap uses two complementary identity systems:

| Aspect | URI | URL |
|--------|-----|-----|
| **Purpose** | Stable entity identity | Navigation path |
| **Format** | `type:components` | `/path/segments` |
| **Resolution** | Always one result | Zero, one, or many |
| **Example** | `thread:xotat:1` | `/sessions/threads(state=stopped)` |

### 9.2 URI Format

URIs uniquely identify entities:

```lua
local uri = require("neodap.uri")

uri.debugger()                              -- "debugger"
uri.session("xotat")                        -- "session:xotat"
uri.thread("xotat", 1)                      -- "thread:xotat:1"
uri.stack("xotat", 1, 0)                    -- "stack:xotat:1:0"
uri.frame("xotat", 42, 100)                 -- "frame:xotat:42:100"
uri.scope("xotat", 42, 100, "Locals")       -- "scope:xotat:42:100:Locals"
uri.variable("xotat", 500, "myVar")         -- "variable:xotat:500:myVar"
uri.source("path/to/file.py")               -- "source:path/to/file.py"
uri.breakpoint("/path/file.py", 10, 5)      -- "breakpoint:/path/file.py:10:5"
uri.breakpointBinding("xotat", "/f.py", 10) -- "bpbinding:xotat:/f.py:10:0"
```

### 9.3 URI Resolution

```lua
local entity = uri.resolve(debugger, "thread:xotat:1")
-- Returns Thread entity or nil
```

### 9.4 URL Format

URLs navigate through the entity graph:

```lua
-- Absolute paths
"/sessions"                          -- All sessions
"/sessions:xotat"                    -- Session by key
"/sessions:xotat/threads"            -- Threads of session
"/sessions/threads(state=stopped)"   -- Stopped threads across sessions
"/sessions[0]/threads[0]"            -- First thread of first session

-- Contextual paths (relative to focused entity)
"@session/threads"                   -- Threads of focused session
"@thread/stacks"                     -- Stacks of focused thread
"@frame/scopes"                      -- Scopes of focused frame
"@frame+1"                           -- Frame below current
"@frame-1"                           -- Frame above current

-- Hybrid (URI + path)
"session:xotat/threads"              -- Threads via URI
"frame:xotat:42:100/scopes"          -- Scopes via URI
```

### 9.5 URL Query and Watch

```lua
-- Immediate query
local threads = debugger:query("/sessions:xotat/threads")

-- Always returns array
local threads = debugger:queryAll("/sessions/threads(state=stopped)")

-- Reactive watch (returns signal)
local signal = debugger:watch("/sessions:xotat/threads")
signal:use(function(threads)
  print("Thread count:", #threads)
end)

-- Unified resolve (auto-detects URI vs URL)
local entity = debugger:resolve("thread:xotat:1")  -- URI
local entities = debugger:resolve("/sessions/threads") -- URL
```

### 9.6 URL Parsing

```lua
local url = require("neodap.identity.url")

local parsed = url.parse("/sessions:xotat/threads(state=stopped)[0]")
-- {
--   segments = {
--     { edge = "sessions", key = "xotat" },
--     { edge = "threads", filter = { state = "stopped" }, index = 0 },
--   }
-- }
```

---

## 10. Context API

### 10.1 Overview

The Context API (`debugger.ctx`) manages debug focus:

```lua
-- Focus management
debugger.ctx:focus("/sessions:xotat/threads:1/stacks[0]/frames[0]")
debugger.ctx:focus("")  -- Clear focus

-- Accessors (resolve to specific entity type)
debugger.ctx.frame:get()   -- Get focused Frame
debugger.ctx.thread:get()  -- Get focused Thread
debugger.ctx.session:get() -- Get focused Session

-- Reactive subscriptions
debugger.ctx.frame:use(function(frame)
  -- Called when focus changes
end)
```

### 10.2 Focus Resolution

The context navigates from any focused entity to the requested type:

```lua
-- If focused on a Frame:
ctx.frame:get()   -- Returns the Frame
ctx.thread:get()  -- Returns Frame's Stack's Thread
ctx.session:get() -- Returns Frame's Stack's Thread's Session

-- If focused on a Thread:
ctx.frame:get()   -- Returns Thread's Stack's topFrame
ctx.thread:get()  -- Returns the Thread
ctx.session:get() -- Returns Thread's Session
```

### 10.3 URL Expansion

Expand contextual markers to concrete URIs:

```lua
local signal = debugger.ctx:expand("@session/threads")
signal:use(function(expanded)
  print(expanded)  -- e.g., "session:xotat/threads"
end)

-- Supported markers:
-- @debugger - Root debugger
-- @session  - Focused session
-- @thread   - Focused thread
-- @frame    - Focused frame
-- @frame+N  - Frame N positions below
-- @frame-N  - Frame N positions above
```

---

## 11. API Reference

### 11.1 neodap Module

```lua
local neodap = require("neodap")

neodap.setup(opts)                    -- Initialize with config, returns debugger
neodap.createDebugger(opts)           -- Create isolated debugger
neodap.use(plugin, config)            -- Use plugin with main debugger (shorthand for neodap.debugger:use())
neodap.dispose()                      -- Cleanup everything
neodap.debugger                       -- Main debugger instance
neodap.graph                          -- Graph instance
neodap.plugins                        -- Lazy-loaded built-in plugins (e.g., neodap.plugins.dap)
neodap.config                         -- Current config (includes adapters)

-- Re-exported entity classes
neodap.Debugger
neodap.Session
neodap.Thread
neodap.Stack
neodap.Frame
neodap.Scope
neodap.Variable
neodap.Source
neodap.SourceBinding
neodap.Breakpoint
neodap.BreakpointBinding
```

### 11.2 Debugger Entity

```lua
-- Properties
debugger.focusedUrl:get()             -- Current focus URL

-- Edges
debugger.sessions:iter()              -- All sessions
debugger.rootSessions:iter()          -- Root sessions only
debugger.sources:iter()               -- All sources
debugger.breakpoints:iter()           -- All breakpoints

-- Rollups
debugger.sessionCount:get()           -- Number of sessions
debugger.breakpointCount:get()        -- Number of breakpoints

-- Methods
debugger:use(plugin, config)          -- Use plugin
debugger:dispose()                    -- Cleanup
debugger:debug(opts)                  -- Start debug session (via DAP plugin)
debugger:focus(url)                   -- Set focus
debugger:query(url)                   -- Query URL
debugger:queryAll(url)                -- Query URL (always array)
debugger:watch(url)                   -- Watch URL reactively
debugger:resolve(str)                 -- Resolve URI or URL
debugger:toggleBreakpoint(location)   -- Toggle breakpoint (via entity method)
debugger:breakpointsAt(location)      -- Get breakpoints at location

-- Context API
debugger.ctx:focus(url)               -- Set focus
debugger.ctx:expand(url)              -- Expand @markers
debugger.ctx.frame:get()              -- Get focused frame
debugger.ctx.thread:get()             -- Get focused thread
debugger.ctx.session:get()            -- Get focused session
debugger.ctx.frame:use(fn)            -- Subscribe to frame changes
debugger.ctx.thread:use(fn)           -- Subscribe to thread changes
debugger.ctx.session:use(fn)          -- Subscribe to session changes
```

### 11.3 Session Entity

```lua
-- Properties
session.uri:get()
session.sessionId:get()
session.name:get()
session.state:get()                   -- "starting", "running", "stopped", "terminated"
session.leaf:get()                    -- true if no children

-- Edges
session.threads:iter()
session.sourceBindings:iter()
session.outputs:iter()
session.exceptionFilters:iter()
session.children:iter()               -- Child sessions

-- Rollups
session.debugger:get()
session.parent:get()                  -- Parent session or nil
session.firstThread:get()
session.firstStoppedThread:get()
session.focusedThread:get()
session.threadCount:get()
session.stoppedThreadCount:get()
session.hasStoppedThread:get()
session.stoppedThreads:iter()
session.runningThreads:iter()
session.stdio:get()                   -- Stdio node

-- Methods
session:isRunning()
session:isStopped()
session:isTerminated()
session:findThreadById(threadId)
session:fetchThreads()                -- DAP method
session:disconnect()                  -- DAP method
session:terminate()                   -- DAP method
session:restart()                     -- DAP method
```

### 11.4 Thread Entity

```lua
-- Properties
thread.uri:get()
thread.threadId:get()
thread.name:get()
thread.state:get()                    -- "running", "stopped", "exited"
thread.focused:get()
thread.stops:get()                  -- Increments each stop

-- Edges
thread.stacks:iter()                  -- All stacks (historical)
thread.currentStacks:iter()           -- Current stack only

-- Rollups
thread.session:get()
thread.stack:get()                    -- Current stack
thread.currentStack:get()             -- Same as stack
thread.stackCount:get()

-- Methods
thread:continue()                     -- DAP method
thread:pause()                        -- DAP method
thread:stepOver(opts)                 -- DAP method
thread:stepIn(opts)                   -- DAP method
thread:stepOut(opts)                  -- DAP method
thread:fetchStackTrace()              -- DAP method
```

### 11.5 Frame Entity

```lua
-- Properties
frame.uri:get()
frame.frameId:get()
frame.index:get()
frame.name:get()
frame.line:get()
frame.column:get()
frame.focused:get()
frame.active:get()

-- Edges
frame.scopes:iter()

-- Rollups
frame.stack:get()
frame.source:get()
frame.localsScope:get()
frame.scopeCount:get()

-- Methods
frame:fetchScopes()                   -- DAP method
frame:evaluate(expression, context)   -- DAP method
frame:restartFrame()                  -- DAP method
```

### 11.6 Scope Entity

```lua
-- Properties
scope.uri:get()
scope.name:get()
scope.presentationHint:get()          -- "locals", "arguments", "globals", etc.
scope.expensive:get()
scope.variablesReference:get()

-- Edges
scope.variables:iter()

-- Rollups
scope.frame:get()
scope.variableCount:get()

-- Methods
scope:fetchVariables()                -- DAP method
```

### 11.7 Variable Entity

```lua
-- Properties
variable.uri:get()
variable.name:get()
variable.value:get()
variable.varType:get()
variable.variablesReference:get()
variable.evaluateName:get()

-- Edges
variable.children:iter()

-- Rollups
variable.scope:get()
variable.parent:get()                 -- Parent variable (for nested)
variable.childCount:get()
variable.hasChildren:get()

-- Methods
variable:fetchChildren()              -- DAP method
variable:setValue(value)              -- DAP method
```

### 11.8 Breakpoint Entity

```lua
-- Properties
breakpoint.uri:get()
breakpoint.line:get()
breakpoint.column:get()
breakpoint.condition:get()
breakpoint.hitCondition:get()
breakpoint.logMessage:get()
breakpoint.enabled:get()

-- Edges
breakpoint.bindings:iter()            -- Per-session bindings

-- Rollups
breakpoint.debugger:get()
breakpoint.source:get()
breakpoint.hitBinding:get()           -- First hit binding
breakpoint.verifiedBinding:get()      -- First verified binding
breakpoint.bindingCount:get()
breakpoint.hasHitBinding:get()
breakpoint.hasVerifiedBinding:get()

-- Methods
breakpoint:remove()                   -- Delete and cleanup
breakpoint:getMark()                  -- Get visual state
breakpoint:setEnabled(enabled)
breakpoint:setCondition(condition)
breakpoint:setLogMessage(message)
```

### 11.9 Source Entity

```lua
-- Properties
source.uri:get()
source.key:get()                      -- Unique key (path-based)
source.path:get()
source.name:get()
source.content:get()                  -- For sourceReference sources

-- Edges
source.bindings:iter()                -- Per-session bindings
source.breakpoints:iter()
source.frames:iter()                  -- Frames at this source
source.outputs:iter()                 -- Output linked to this source

-- Rollups
source.debugger:get()
source.breakpointCount:get()
source.bindingCount:get()
source.breakpointsByLine:iter()
source.enabledBreakpoints:iter()
source.activeFrames:iter()

-- Methods
source:syncBreakpoints()              -- Sync to all sessions
source:fetchContent(session)          -- DAP method
```

---

## 12. Extension Guide

### 12.1 Creating a Plugin

Plugins expose user-facing functionality via **vim commands**, not Lua APIs:

```lua
-- lua/my_plugin/init.lua

---@param debugger neodap.entities.Debugger
---@param config? { option1: boolean, option2: string }
return function(debugger, config)
  config = vim.tbl_extend("force", {
    option1 = true,
    option2 = "default",
  }, config or {})

  -- Internal implementation
  local function do_something(url)
    local entities = url and debugger:queryAll(url) or { debugger.ctx.session:get() }
    for _, entity in ipairs(entities) do
      -- ... implementation
    end
  end

  -- PRIMARY: Register vim command (discoverable via :Dap)
  vim.api.nvim_create_user_command("DapMyCommand", function(opts)
    local url = opts.args ~= "" and opts.args or nil
    do_something(url)
  end, {
    nargs = "?",
    desc = "Description for :Dap mycommand",
    complete = function(arglead)
      -- Provide completions
      return vim.tbl_filter(function(c)
        return c:match("^" .. vim.pesc(arglead))
      end, { "@session", "sessions" })
    end,
  })

  -- Cleanup function (called when debugger is disposed)
  local function cleanup()
    pcall(vim.api.nvim_del_user_command, "DapMyCommand")
  end

  -- OPTIONAL: Return Lua API only if callers need non-serializable params
  return {
    cleanup = cleanup,
    -- Only expose methods that need callbacks or return values
    do_something_with_callback = function(url, callback)
      -- For cases where vim commands can't work
      callback(do_something(url))
    end,
  }
end
```

The command `DapMyCommand` is automatically available as `:Dap mycommand` via the `command_router` router.

### 12.2 Adding Entity Methods

```lua
-- lua/my_plugin/session_methods.lua
local entities = require("neodap.entities")
local a = require("neodap.async")

function entities.Session:myCustomMethod()
  -- Method implementation
end

-- For async methods
function entities.Session:myAsyncMethod()
  a.wait(function(cb)
    -- Async operation
    cb(nil, result)
  end)
end
entities.Session.myAsyncMethod = a.fn(entities.Session.myAsyncMethod)
```

### 12.3 Creating Custom Buffers

Use the entity_buffer utility for URL-based buffers:

```lua
local entity_buffer = require("neodap.plugins.utils.entity_buffer")

entity_buffer.register("dap://myscheme", nil, "one", {
  render = function(bufnr, entity)
    return "Content for " .. (entity and entity.uri:get() or "nil")
  end,

  setup = function(bufnr, entity, options)
    vim.bo[bufnr].filetype = "my-filetype"
  end,

  cleanup = function(bufnr)
    -- Cleanup resources
  end,

  on_change = function(bufnr, old_entity, new_entity, is_dirty)
    -- Handle entity changes
    return true  -- Let entity_buffer update state
  end,
})

-- Usage: :edit dap://myscheme/@session
```

### 12.4 Subscribing to Entity Changes

```lua
-- Subscribe to edge (per-item callbacks)
debugger.breakpoints:each(function(breakpoint)
  -- Called for each breakpoint
  -- Return cleanup function
  return function()
    -- Called when breakpoint removed
  end
end)

-- Subscribe to property
session.state:use(function(state)
  -- Called with initial value, then on changes
  return function()
    -- Cleanup (optional)
  end
end)

-- Subscribe to rollup
session.firstStoppedThread:use(function(thread)
  if thread then
    print("Stopped at:", thread.name:get())
  end
end)
```

### 12.5 Working with Async

```lua
local a = require("neodap.async")

-- Async function that can be called from sync or async context
local function myAsyncFunction()
  -- Wait for callback-based operation
  local result = a.wait(function(cb)
    vim.defer_fn(function()
      cb(nil, "result")
    end, 100)
  end, "myOperation")

  return result
end

-- Wrap for dual-context use
myAsyncFunction = a.fn(myAsyncFunction)

-- Use it
myAsyncFunction()  -- Works from sync context
a.run(function()
  local result = myAsyncFunction()  -- Works from async context
end)
```

### 12.6 Creating Derived State

```lua
local derive = require("neodap.derive")

-- Derive from multiple sources
local debugState = derive.from(
  { debugger.sessionCount, debugger.breakpointCount },
  function()
    return {
      sessions = debugger.sessionCount:get(),
      breakpoints = debugger.breakpointCount:get(),
    }
  end
)

debugState:use(function(state)
  print("Sessions:", state.sessions, "Breakpoints:", state.breakpoints)
end)
```

---

## 13. Testing

### 13.1 Test Infrastructure

Tests use MiniTest with parallel execution:

```bash
# Run all tests
make test

# Run single file
make test-file FILE=tree_buffer_output

# Run with type checking
make check

# Clean artifacts
make clean
```

### 13.2 Test Structure

```lua
-- tests/my_feature_spec.lua
local MiniTest = require("mini.test")
local T = MiniTest.new_set()

T["my_feature"] = MiniTest.new_set()

T["my_feature"]["does something"] = function()
  local neodap = require("neodap")
  local debugger = neodap.createDebugger({})

  -- Test implementation
  MiniTest.expect.equality(actual, expected)
end

return T
```

### 13.3 Test Harness

The test harness provides high-level testing API:

```lua
local harness = require("tests.helpers.test_harness")

T["integration"]["launches and stops"] = function()
  local h = harness.new()

  -- Launch debug session
  h:launch({
    adapter = { type = "stdio", command = "debugpy" },
    config = { type = "python", request = "launch", program = "test.py" },
  })

  -- Wait for condition
  h:wait(function()
    return h:query("/sessions[0]").state:get() == "stopped"
  end)

  -- Execute vim command
  h:cmd("DapContinue")

  -- Cleanup
  h:cleanup()
end
```

### 13.4 DAP Fixtures

Pre-defined test programs:

```lua
local fixtures = require("tests.helpers.dap.fixtures")

-- Python fixture
local python = fixtures.python({
  breakpoint_line = 5,
  code = [[
def main():
    x = 1
    y = 2
    z = x + y  # Line 5
    return z
main()
]],
})

-- JavaScript fixture
local js = fixtures.javascript({
  breakpoint_line = 3,
  code = [[
function main() {
  const x = 1;
  const y = 2;  // Line 3
  return x + y;
}
main();
]],
})
```

### 13.5 URL-Based Testing

Tests use URL queries for assertions:

```lua
-- Wait for specific state via URL
h:wait_url("/sessions:xotat/threads(state=stopped)")

-- Query and assert
local threads = h:query("/sessions[0]/threads")
MiniTest.expect.equality(#threads, 2)

-- Watch for changes
local signal = h:watch("/sessions[0]/threads[0]/state")
signal:use(function(state)
  -- Assert state changes
end)
```

---

## 14. Configuration

### 14.1 Setup Options

```lua
local neodap = require("neodap")

local debugger = neodap.setup({
  -- Map DAP type names to adapter configurations
  adapters = {
    -- Python (debugpy)
    python = {
      type = "server",
      command = "python",
      args = { "-m", "debugpy.adapter" },
    },
    -- JavaScript/TypeScript (js-debug)
    ["pwa-node"] = {
      type = "server",
      command = "js-debug-adapter",
      args = {},
    },
    -- Go (delve)
    go = {
      type = "stdio",
      command = "dlv",
      args = { "dap" },
    },
  },
})
```

### 14.2 Plugin Configuration

Each plugin accepts its own configuration:

```lua
-- Tree buffer
neodap.use(require("neodap.plugins.tree_buffer"), {
  icons = {
    expanded = "▼",
    collapsed = "▶",
    session = "▶",
    thread = "◆",
    frame = "→",
    scope = "◇",
    variable = "•",
  },
  guide_highlights = {
    vertical = "Comment",
    branch = "Comment",
    last_branch = "Comment",
  },
})

-- Breakpoint signs
neodap.use(require("neodap.plugins.breakpoint_signs"), {
  icons = {
    unbound = "●",
    bound = "◉",
    adjusted = "◐",
    hit = "◆",
    disabled = "○",
  },
  colors = {
    unbound = "DiagnosticInfo",
    bound = "DiagnosticInfo",
    adjusted = "DiagnosticInfo",
    hit = "DiagnosticWarn",
    disabled = "Comment",
  },
  priority = 20,
  namespace = "neobreakpoint_cmd_signs",
})

-- Frame highlights
neodap.use(require("neodap.plugins.frame_highlights"), {
  highlight = "CursorLine",
  priority = 10,
})

-- Inline values
neodap.use(require("neodap.plugins.inline_values"), {
  max_length = 50,
  highlight = "Comment",
})
```

### 14.3 Global Variables

Some behaviors can be controlled via global variables:

```lua
-- Disable auto-fetch of stack traces
vim.g.neodap__autofetch_stack = false
```

### 14.4 Example Full Configuration

```lua
local neodap = require("neodap")

-- Initialize SDK with adapter configurations
local debugger = neodap.setup({
  adapters = {
    python = { type = "server", command = "python", args = { "-m", "debugpy.adapter" } },
    ["pwa-node"] = { type = "server", command = "js-debug-adapter" },
    go = { type = "stdio", command = "dlv", args = { "dap" } },
  },
})

-- Core plugins (using neodap.plugins.* lazy-loaded re-exports)
debugger:use(neodap.plugins.dap)            -- Core DAP integration
debugger:use(neodap.plugins.command_router)        -- :Dap command router

-- Control plugins (register vim commands)
debugger:use(neodap.plugins.bulk_cmd)     -- :DapToggle
debugger:use(neodap.plugins.step_cmd)       -- :DapStep
debugger:use(neodap.plugins.control_cmd)   -- :DapContinue, :DapPause, :DapTerminate
debugger:use(neodap.plugins.breakpoint_cmd) -- :DapBreakpoint
debugger:use(neodap.plugins.focus_cmd)      -- :DapFocus
debugger:use(neodap.plugins.jump_cmd)       -- :DapJump
debugger:use(neodap.plugins.list_cmd)       -- :DapList

-- UI plugins (reactive behavior, no commands)
debugger:use(neodap.plugins.tree_buffer)
debugger:use(neodap.plugins.breakpoint_signs)
debugger:use(neodap.plugins.frame_highlights)
debugger:use(neodap.plugins.inline_values)
debugger:use(neodap.plugins.jump_stop)

-- Keymaps using vim commands
vim.keymap.set("n", "<F5>", "<cmd>Dap toggle<cr>")
vim.keymap.set("n", "<F10>", "<cmd>Dap step over<cr>")
vim.keymap.set("n", "<F11>", "<cmd>Dap step into<cr>")
vim.keymap.set("n", "<S-F11>", "<cmd>Dap step out<cr>")
vim.keymap.set("n", "<F9>", "<cmd>Dap breakpoint<cr>")
vim.keymap.set("n", "<Leader>dc", "<cmd>Dap continue<cr>")
vim.keymap.set("n", "<Leader>dp", "<cmd>Dap pause<cr>")
vim.keymap.set("n", "<Leader>dt", "<cmd>Dap terminate<cr>")
vim.keymap.set("n", "<Leader>db", "<cmd>Dap list breakpoints<cr>")
vim.keymap.set("n", "<Leader>do", "<cmd>edit dap://tree/@debugger<cr>")
```

### 14.5 Picker Shortcut Commands

`DapFocus` and `DapJump` accept URL patterns and show a picker when multiple entities match. You can define shortcut commands for common picker operations:

```lua
-- Shortcut commands for common picker operations
vim.api.nvim_create_user_command("DapSessions", function()
  vim.cmd("DapFocus /sessions")
end, { desc = "Pick and focus a session" })

vim.api.nvim_create_user_command("DapThreads", function()
  vim.cmd("DapFocus @session/threads")
end, { desc = "Pick and focus a thread in current session" })

vim.api.nvim_create_user_command("DapFrames", function()
  vim.cmd("DapJump @thread/stacks[0]/frames")
end, { desc = "Pick and jump to a frame in current thread" })

-- All threads across all sessions
vim.api.nvim_create_user_command("DapAllThreads", function()
  vim.cmd("DapFocus /sessions/threads")
end, { desc = "Pick and focus any thread" })

-- Only stopped threads
vim.api.nvim_create_user_command("DapStoppedThreads", function()
  vim.cmd("DapFocus /sessions/threads(state=stopped)")
end, { desc = "Pick and focus a stopped thread" })
```

These shortcut commands leverage the URL system:

| Command | URL | Behavior |
|---------|-----|----------|
| `:DapSessions` | `/sessions` | Pick from all sessions |
| `:DapThreads` | `@session/threads` | Pick from focused session's threads |
| `:DapFrames` | `@thread/stacks[0]/frames` | Pick from focused thread's frames |
| `:DapAllThreads` | `/sessions/threads` | Pick from all threads |
| `:DapStoppedThreads` | `/sessions/threads(state=stopped)` | Pick from stopped threads only |

When only one entity matches, no picker is shown - the action happens immediately.

### 14.6 Lualine Status Component

The `lualine.lua` plugin provides a configurable status component for [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim):

```lua
local neodap = require("neodap")

-- Load lualine plugin and get component function
local lualine_component = neodap.use(require("neodap.plugins.lualine"), {
  session = true,    -- Show session name (adapter type)
  thread = true,     -- Show thread state
  frame = true,      -- Show frame function:line
  separator = " > ", -- Separator between parts
  empty = "",        -- Text when no debug session
})

-- Add to lualine configuration
require("lualine").setup({
  sections = {
    lualine_x = { lualine_component },  -- or any section you prefer
  },
})
```

Example output: `python > stopped > main:42`

**Configuration Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `session` | boolean | `true` | Show session name (adapter type like "python", "node") |
| `thread` | boolean | `true` | Show thread state ("running", "stopped") |
| `frame` | boolean | `true` | Show frame function:line |
| `separator` | string | `" > "` | Separator between parts |
| `empty` | string | `""` | Text shown when no debug session |
| `format` | function | `nil` | Custom format function (overrides defaults) |

**Custom Format Function:**

```lua
local lualine_component = neodap.use(require("neodap.plugins.lualine"), {
  format = function(ctx)
    -- ctx.session, ctx.thread, ctx.frame are entity objects or nil
    if not ctx.session then return "" end
    if not ctx.frame then return "debugging" end
    local name = ctx.frame.name:get()
    local line = ctx.frame.line:get()
    return string.format("@ %s:%d", name, line)
  end
})
```

### 14.7 Preview Handler

The `preview_handler.lua` plugin routes entity URIs to appropriate display renderers via inline rendering:

```lua
local neodap = require("neodap")

-- Load preview handler with custom type mappings
local preview_api = neodap.use(require("neodap.plugins.preview_handler"), {
  handlers = {
    -- Simple: direct scheme mapping
    Source = { scheme = "dap://source/" },
    Variable = { scheme = "dap://var/" },

    -- Function: transform entity before rendering
    Frame = function(entity)
      local source = entity.source:get()
      if source then
        return {
          scheme = "dap://source/",
          entity = source,
          options = { line = entity.line:get() }
        }
      end
      return { scheme = "dap://url/" }
    end,

    -- Default for unmapped types
    default = { scheme = "dap://url/" }
  }
})

-- Open preview for an entity URI
preview_api.open("frame:session:42:0", { split = "vertical" })

-- Refresh preview with new entity
preview_api.refresh(bufnr, "variable:session:123")

-- Get currently previewed entity
local entity = preview_api.get_entity()
```

The preview buffer uses the scheme `dap://preview/{entity_uri}` and delegates rendering to the appropriate registered scheme's render function.

### 14.8 Tree Preview

The `tree_preview.lua` plugin follows tree buffer selection and syncs a preview pane:

```lua
local neodap = require("neodap")

-- Load tree_preview with configuration
local tree_preview = neodap.use(require("neodap.plugins.tree_preview"), {
  position = "right",   -- "right", "below", "left", "above"
  size = 40,            -- width or height depending on position
})

-- Also load preview_handler (tree_preview uses it)
neodap.use(require("neodap.plugins.preview_handler"))
```

**Commands:**

| Command | Description |
|---------|-------------|
| `:DapTreePreview` | Toggle preview split for current tree buffer |
| `:DapTreePreview right` | Open preview in vertical split (right) |
| `:DapTreePreview below` | Open preview in horizontal split (below) |

**API:**

```lua
-- Open/close/toggle preview
tree_preview.open(tree_bufnr, "right")
tree_preview.close(tree_bufnr)
tree_preview.toggle(tree_bufnr, "below")

-- Check status
tree_preview.is_active(tree_bufnr)
tree_preview.get_preview_window(tree_bufnr)
```

**Workflow:**

1. Open tree: `:edit dap://tree/@debugger`
2. Open preview split: `:DapTreePreview`
3. Navigate tree with `j`/`k`
4. Preview pane updates automatically showing entity details

---

## 15. Appendices

### 15.1 Glossary

| Term | Definition |
|------|------------|
| **DAP** | Debug Adapter Protocol - standardized protocol for debugger communication |
| **Entity** | A node in the debug state graph (Session, Thread, Frame, etc.) |
| **Edge** | A relationship between entities in the graph |
| **Signal** | A reactive property that notifies subscribers on change |
| **Rollup** | A computed property derived from an edge (reference, collection, or aggregate) |
| **URI** | Stable entity identity string (e.g., `thread:xotat:1`) |
| **URL** | Navigation path through the graph (e.g., `/sessions/threads`) |
| **Scope** | A cleanup boundary for reactive subscriptions |
| **Plugin** | A function that extends debugger functionality |
| **Adapter** | A component that connects to a debug adapter via stdio, TCP, or server mode |

### 15.2 Entity State Diagram

```
Session States:
  starting → running ⟷ stopped → terminated
                ↑___________↓

Thread States:
  running ⟷ stopped → exited

Breakpoint Binding States:
  unverified → verified
       ↓          ↓
       └── hit ←──┘
```

### 15.3 neoword Algorithm

Session IDs are generated using a CVCVC (consonant-vowel-consonant-vowel-consonant) pattern:

```lua
-- 20 consonants × 5 vowels × 20 consonants × 5 vowels × 20 consonants
-- = 200,000 unique 5-letter words

-- Examples: xotat, bilum, cavod, deter, fogun
```

The algorithm uses DJB2 hashing for deterministic generation from input strings.

### 15.4 Schema Reference

Complete entity types defined in the schema:

1. **Debugger** - Root singleton
2. **Session** - Debug session
3. **Thread** - Execution thread
4. **Stack** - Stack snapshot
5. **Frame** - Stack frame
6. **Scope** - Variable scope
7. **Variable** - Variable/value
8. **Source** - Source file
9. **SourceBinding** - Source per session
10. **Breakpoint** - Breakpoint definition
11. **BreakpointBinding** - Breakpoint per session
12. **Output** - Debug output
13. **ExceptionFilter** - Exception configuration
14. **Stdio** - Output grouping node
15. **Sessions** - Session grouping node
16. **Breakpoints** - Breakpoint grouping node
17. **Targets** - Leaf session grouping node
18. **Threads** - Thread grouping node

### 15.5 DAP Event Mapping

| DAP Event | Entity Update |
|-----------|---------------|
| `initialized` | Session capabilities stored |
| `stopped` | Session/Thread state → "stopped", Stack fetched |
| `continued` | Session/Thread state → "running" |
| `terminated` | Session state → "terminated" |
| `exited` | Session state → "terminated" |
| `thread` | Thread created/updated |
| `output` | Output entity created |
| `breakpoint` | BreakpointBinding updated |
| `loadedSource` | Source/SourceBinding created |
| `module` | (Not currently mapped) |
| `process` | (Not currently mapped) |

### 15.6 Error Handling

neodap uses pcall-wrapped operations with graceful degradation:

```lua
-- Async errors are wrapped with stack traces
local AsyncError = require("neodap.async").AsyncError

-- Errors include trace frames
-- AsyncError: Request timeout
--   at fetchStackTrace (thread.lua:98)
--   at fetchThreads (session.lua:42)
```

### 15.7 Performance Considerations

1. **Lazy Loading**: Fetch data only when needed (stack traces, variables)
2. **Memoization**: Concurrent calls to the same method are coalesced
3. **Scoped Cleanup**: Subscriptions are automatically cleaned up
4. **View Limits**: Tree views use viewport limiting for large datasets
5. **Indexed Queries**: Schema indexes enable O(1) entity lookups

---

## Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026 | Initial documentation |

---

*This documentation was generated from the neodap source code without reference to existing markdown files.*
