# Neodap

> **Warning**
> This project is in **alpha (v0.0.1)**. APIs may change without notice. Use at your own risk.
>
> While the technical choices and architecture have been designed by the author, **most of the code and documentation is AI-generated**. This implies a mandatory stabilization period during which breaking changes are expected.
>
> This project was created as an experiment to learn how to use AI agents in coding tasks (spoiler: for now, don't). It will be maintained and stabilized by the author going forward.

A reactive debugging SDK for Neovim built on the Debug Adapter Protocol (DAP).

Neodap provides a high-level, reactive API for building debugging experiences in Neovim. It abstracts away DAP protocol complexity while giving developers full control through a composable plugin system.

## Features

- **Reactive Architecture**: Built on [neostate](#neostate), a fine-grained reactivity system. UI updates automatically when debug state changes.
- **Plugin System**: Extend functionality through composable plugins. Use the built-in plugins or write your own.
- **Multi-Session Support**: Debug multiple processes simultaneously with automatic breakpoint synchronization.
- **VSCode Compatibility**: Works with `launch.json` configurations and VSCode debug adapters.
- **Type-Safe DAP Client**: Full type annotations for all DAP protocol messages.
- **Automatic Lifecycle Management**: Resources clean up automatically when sessions end.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "aetherall/neodap",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  config = function()
    local debugger = require("neodap")

    -- Register your debug adapters
    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" },
    })

    -- Load plugins
    require("neodap.plugins.auto_context")(debugger)
    require("neodap.plugins.auto_stack")(debugger)
    require("neodap.plugins.breakpoint_signs")(debugger)
    require("neodap.plugins.frame_highlights")(debugger)
    require("neodap.plugins.exception_highlight")(debugger)
    require("neodap.plugins.dap_breakpoint")(debugger)
    require("neodap.plugins.dap_step")(debugger)
    require("neodap.plugins.dap_continue")(debugger)
    require("neodap.plugins.dap_jump")(debugger)
    require("neodap.plugins.jump_stop")(debugger)
    require("neodap.plugins.code_workspace")(debugger)
  end,
}
```

## Quick Start

### 1. Register Debug Adapters

```lua
local debugger = require("neodap")

-- Python (debugpy)
debugger:register_adapter("python", {
  type = "stdio",
  command = "python3",
  args = { "-m", "debugpy.adapter" },
})

-- Node.js (js-debug)
debugger:register_adapter("pwa-node", {
  type = "server",
  command = "js-debug-adapter",
  args = { "${port}" },
  connect_condition = function(output)
    local port = output:match("Debug server listening at.*:(%d+)")
    return tonumber(port)
  end,
})
```

### 2. Set Breakpoints

```vim
:DapBreakpoint              " Toggle breakpoint at cursor
:DapBreakpoint condition x>5  " Conditional breakpoint
:DapBreakpoint log {x}      " Log point
```

### 3. Start Debugging

```vim
:DapLaunch                  " Pick from launch.json configurations
:DapLaunch "Debug Python"   " Launch specific configuration
```

### 4. Control Execution

```vim
:DapStep over              " Step over
:DapStep into              " Step into
:DapStep out               " Step out
:DapContinue               " Continue execution
```

## Plugins

Neodap ships with plugins that provide common debugging functionality:

| Plugin | Description |
|--------|-------------|
| `auto_context` | Automatically track debug context as you navigate files |
| `auto_stack` | Fetch stack trace when threads stop |
| `breakpoint_signs` | Display breakpoint icons with state indicators |
| `frame_highlights` | Highlight stack frames in source buffers |
| `exception_highlight` | Highlight exception locations with error messages |
| `dap_breakpoint` | `:DapBreakpoint` command for breakpoint management |
| `dap_step` | `:DapStep` command for stepping through code |
| `dap_continue` | `:DapContinue` command to resume execution |
| `dap_jump` | `:DapJump` command to jump to frame locations |
| `jump_stop` | Auto-jump to source when threads stop |
| `code_workspace` | `:DapLaunch` command with VSCode launch.json support |
| `tree_buffer` | Interactive tree view for debugging state |
| `eval_buffer` | REPL-style expression evaluation |
| `variable_edit` | Edit variable values in buffers |
| `variable_completion` | DAP-powered completions in edit buffers |

See [docs/plugins.md](docs/plugins.md) for detailed plugin documentation.

## For Plugin Developers

Neodap exposes a reactive SDK for building custom debugging experiences:

```lua
local debugger = require("neodap")

-- React to new sessions
debugger:onSession(function(session)
  print("New session:", session.name:get())

  -- React to session state changes
  session.state:use(function(state)
    if state == "stopped" then
      print("Session stopped!")
    end
  end)
end)

-- React to threads
debugger:onThread(function(thread)
  -- React to thread state
  thread.state:use(function(state)
    if state == "stopped" then
      local stack = thread:stack()
      local frame = stack:top()
      print("Stopped at:", frame.source:uri(), "line", frame.line)
    end
  end)
end)

-- React to frames
debugger:onFrame(function(frame)
  -- Access frame data reactively
  frame.source -- Source entity
  frame.line   -- Line number
  frame.name   -- Function name
end)
```

See [docs/sdk.md](docs/sdk.md) for the full SDK reference.

## Architecture

Neodap is built in layers:

```
┌─────────────────────────────────────────────┐
│              User Plugins                   │  ← Your plugins
├─────────────────────────────────────────────┤
│           Built-in Plugins                  │  ← neodap.plugins.*
├─────────────────────────────────────────────┤
│              Neodap SDK                     │  ← Reactive debugging API
├─────────────────────────────────────────────┤
│              DAP Client                     │  ← Protocol implementation
├─────────────────────────────────────────────┤
│              Neostate                       │  ← Reactive primitives
└─────────────────────────────────────────────┘
```

### Neostate

The reactive foundation. Provides:
- **Signal**: Reactive single values
- **List/Collection**: Reactive collections with indexing
- **Disposable**: Automatic lifecycle management
- **computed**: Derived reactive values

See [docs/neostate.md](docs/neostate.md) for details.

### DAP Client

Low-level Debug Adapter Protocol implementation:
- Full DAP protocol support with type annotations
- Transport adapters: stdio, TCP, server
- Automatic timeouts and connection management

See [docs/dap-client.md](docs/dap-client.md) for details.

### Neodap SDK

High-level reactive API built on DAP Client:
- **Debugger**: Root object managing sessions and breakpoints
- **Session**: Individual debug session with state tracking
- **Thread**: Debug thread with stack traces
- **Frame**: Stack frame with variables and scopes
- **Breakpoint**: Global breakpoints with per-session bindings

## URI System

Neodap uses URIs to identify debug entities:

```
dap:session:<id>/thread:<id>/stack[0]/frame[0]
```

Contextual URIs resolve relative to the current context:

```
@frame           → Current context frame
@session/thread  → Threads in context session
@stack/frame[0]  → Top frame of context stack
```

## Development

```bash
# Enter development shell (provides Neovim, debuggers, test framework)
nix develop

# Run all tests
make test

# Run specific test module
make test neostate
make test dap-client
make test sdk-session
make test plugins
```

## Requirements

- Neovim 0.9+
- LuaJIT

## License

MIT

## Credits

Built with:
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) - Test framework
- Debug Adapter Protocol adapters from the VSCode ecosystem
