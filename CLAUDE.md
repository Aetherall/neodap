# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@MCP.md

## Project Overview

Neostate is a reactive state management library for Neovim written in Lua. It provides a fine-grained reactivity system with automatic lifecycle management through disposable objects. The project also includes a DAP (Debug Adapter Protocol) client implementation.

## Commands

### Testing
```bash
# Run all tests
make test

# Run tests for a specific module
make test neostate        # tests/neostate/
make test dap-client      # tests/dap-client/
make test sdk-uri         # tests/neodap/sdk-uri/
make test sdk-session     # tests/neodap/sdk-session/
make test sdk-thread      # tests/neodap/sdk-thread/
make test sdk-breakpoint  # tests/neodap/sdk-breakpoint/
make test sdk-source      # tests/neodap/sdk-source/
make test sdk-collection  # tests/neodap/sdk-collection/
make test plugins         # tests/neodap/plugins/
make test integration     # tests/neodap/integration/
```

### Development Environment
```bash
# Enter development shell (provides Neovim with plenary, debuggers, etc.)
nix develop

# Or use direnv if configured
direnv allow
```

### Searching the Codebase

Use ripgrep (rg) for fast, powerful code search:

```bash
# Search for API usage
rg "vim\.api\.nvim_" lua/

# Find function definitions
rg "^function M\." lua/

# Search for specific patterns in tests
rg "describe\(" tests/

# Find all uses of a specific function
rg "Disposable\(" --type lua

# Search with context (2 lines before/after)
rg -C 2 "on_dispose"

# Search for word boundaries only
rg -w "dispose"

# Case-insensitive search
rg -i "signal"

# Search and show only file names
rg -l "vim.schedule"

# Search in Neovim documentation
rg "nvim_buf_" docs/neovim/

# Search for Lua API patterns in docs
rg "vim\.api\." docs/neovim/lua.txt

# Find all functions with specific signature
rg "function.*\(.*callback" lua/

# Search excluding certain directories
rg "pattern" --glob '!tests/'

# Multiline search (find function with specific body)
rg -U "function.*\n.*dispose"
```

Common search patterns for this codebase:
```bash
# Find all reactive primitives usage
rg "(Signal|List|Set|Disposable)\(" lua/

# Find lifecycle methods
rg "(on_dispose|dispose|set_parent)" lua/

# Find DAP protocol messages
rg "(request|response|event)" lua/dap-client/

# Search test assertions
rg "assert\." tests/
```

## Architecture

### Core Reactive System (`lua/neostate/init.lua`)

The library implements a hierarchical reactivity system with automatic cleanup:

1. **Disposable Trait**: Base lifecycle management. All reactive objects inherit this trait.
   - Provides `on_dispose()`, `dispose()`, `run()`, `bind()`, and `set_parent()`
   - Implements automatic parent-child relationship: children are disposed when parent dies
   - Uses a context stack to implicitly track parent-child relationships during creation
   - LIFO cleanup order ensures proper teardown

2. **Signal**: Reactive single-value container (like a ref or state)
   - Holds one value that can change over time
   - `.set(val)` updates the value and triggers subscribers
   - `.get()` retrieves current value
   - `.use(fn)` runs fn with current value, then on each change
   - `.watch(fn)` runs fn only on future changes (not current)
   - Old value is disposed before new value is set (triggers cleanup of dependent effects)

3. **Source**: Abstract base class for reactive collections
   - Provides `.subscribe(fn)` for future items only
   - Provides `.each(fn)` for existing + future items
   - Handles automatic cleanup registration per item
   - Subclasses must implement `.iter()` method

4. **List**: Observable array implementation (extends Source)
   - `.add(item)` appends a disposable item
   - `.delete(predicate)` removes and disposes item matching predicate
   - `.extract(predicate)` removes item without disposing (for moving between lists)
   - `.adopt(item)` adds pre-existing disposable with reparenting
   - `.on_added(fn)` subscribes to additions
   - `.on_removed(fn)` subscribes to removals

5. **Set**: Observable set implementation (extends Source)
   - Similar to List but uses table keys for O(1) lookup
   - `.add(item)`, `.remove(item)` for set operations

### Context Engine

The context engine uses coroutine-local storage to track the "current" disposable context:
- When creating a Disposable, it implicitly becomes a child of the current context
- `.run(fn)` executes fn with a new context (making the caller the parent)
- `.bind(fn)` creates a callback that preserves context across async boundaries
- This allows effects and child objects to automatically inherit lifecycle

### DAP Client (`lua/dap-client/init.lua`)

A complete Debug Adapter Protocol client implementation with **concise API**, **internal error handling**, and **full type annotations**.

1. **Transport Layer**: Abstracts communication (stdio, TCP)
   - Handles Content-Length header protocol
   - Uses `vim.lsp.rpc.create_read_loop` for parsing
   - Automatic timeouts (30s for requests, 5s for TCP connections)
   - Internal error logging (no callbacks exposed)

2. **Message Types**: Supports all DAP message types
   - Requests (client → server with callback)
   - Responses (server → client, matched by seq)
   - Events (server → client, fire-and-forget)
   - Reverse requests (server → client with response)

3. **Adapters**: Three connection modes
   - `stdio`: Launch debugger as subprocess, communicate via stdin/stdout
   - `tcp`: Connect to existing TCP server
   - `server`: Launch server, parse stdout for port, then connect via TCP
     - **Auto-shutdown**: Server terminates when last client closes
     - Uses `connect_condition` function to extract port from server output
     - Tracks active connections automatically

4. **API** (minimal surface):
   - `client:request(command, args, callback)` - send DAP request (with auto-timeout)
   - `client:on(event, handler)` - listen for DAP events
   - `client:on_request(command, handler)` - handle reverse requests
   - `client:close()` - shutdown connection (triggers server auto-shutdown if last connection)
   - `client:is_closing()` - check connection state

5. **Error Handling** (internal only):
   - Decode errors → logged at WARN level
   - Connection failures → logged at ERROR level
   - Process crashes → logged at WARN level
   - Server output → logged at DEBUG level
   - All errors handled internally, no callbacks exposed

6. **Type System** (overload-based, zero boilerplate):
   - **40+ `@overload` annotations** for `request()` method
   - **17 `@overload` annotations** for `on()` event listener
   - Full DAP protocol types in `lua/dap-client/protocol.lua` (1663 lines)
   - **No manual `@type` or `@cast` needed** - LSP infers everything automatically
   - Example: `client:request("stepIn", { threadId = 1 }, function(err, result) ...`
     - Arguments are type-checked: `{ threadId: number, granularity?: string }`
     - Result is automatically typed as response body for that command
   - See `examples/dap-client-example.lua` and `docs/dap-types.md`

### SDK Layer (`lua/neodap/sdk/`)

High-level reactive debugging API built on top of the DAP client. Provides automatic lifecycle management, breakpoint binding, and state tracking.

1. **Debugger**: Root object managing all debug sessions
   - `debugger:start(config)` - **Recommended**: Start session with VSCode-style launch config
   - `debugger:add_breakpoint(source, line, opts)` - Create global breakpoint
   - `debugger:register_adapter(type, config)` - Register adapter for logical type
   - `debugger:create_session(adapter_config)` - Low-level session creation (prefer `start()`)
   - Maintains global breakpoint registry
   - Automatically binds breakpoints to relevant sessions
   - **Lifecycle hooks**:
     - `debugger:onSession(fn)` - Called when new session is created
     - `debugger:onBreakpoint(fn)` - Called when breakpoint is added

2. **Session**: Individual debug session with reactive state
   - `session:initialize(args?)` - Initialize with sensible defaults (optional args)
   - `session:launch(launch_args)` - Launch program (async, non-blocking)
   - `session:disconnect(terminate?)` - End session
   - `session:get_or_create_source(data)` - Get/create Source entity (deduplicates)
   - **Automatic breakpoint management**:
     - Registers source files from `adapter_config.program`
     - Creates bindings for relevant global breakpoints
     - Syncs breakpoints to DAP during "initialized" event
     - Waits for all `setBreakpoints` before sending `configurationDone`
   - **Reactive state**: `session.state` Signal ("initializing" | "running" | "stopped" | "terminated")
   - **Reactive collections**: `session.threads`, `session.bindings`, `session.outputs`, `session.sources`
   - **Lifecycle hooks**:
     - `session:onThread(fn)` - Called when new thread appears
     - `session:onBinding(fn)` - Called when breakpoint binding created
     - `session:onOutput(fn)` - Called for debug output
     - `session:onChild(fn)` - Called when child session spawned
     - `session:onSource(fn)` - Called when Source entity created

3. **Thread**: Debug thread with stack traces
   - `thread:stack()` - Get current stack trace (lazy fetch)
   - `thread:step_over()`, `thread:step_into()`, `thread:step_out()` - Stepping
   - **Reactive state**: `thread.state` Signal ("running" | "stopped")
   - Automatic stack trace updates on stopped events
   - **Lifecycle hooks**:
     - `thread:onStopped(fn)` - Called when thread stops (receives reason)
     - `thread:onResumed(fn)` - Called when thread resumes after being stopped
     - `thread:onStack(fn)` - Called when new stack trace is fetched

4. **Stack & Frame**: Call stack with Collection-based indexing
   - `stack.frames` - Collection with reactive indexes (`by_id`, `by_index`)
   - `stack:top()` - Get topmost frame
   - `stack:is_current()` - Check if current or stale
   - `frame.source` - Source entity (local file or virtual source)
   - `frame:scopes()` - Lazy load variable scopes
   - `frame:evaluate(expression, context)` - Evaluate expressions
   - **Lifecycle hooks**:
     - `stack:onExpired(fn)` - Called when stack becomes stale

5. **Source**: Represents source code location (local or virtual)
   - `source:is_virtual()` - Check if virtual source (no local file path)
   - `source:uri()` - Get URI (`file://` for local, `dap://` for virtual)
   - `source:fetch_content(callback?)` - Fetch virtual source content from debugger
   - **URI Handler**: Automatic `dap://session:<id>/source:<ref>/<name>` support
   - Opens virtual sources in Neovim buffers with syntax highlighting
   - **Managed lifecycle**: Sources stored in `session.sources` Collection, deduplicated

**Example Usage (Recommended - VSCode-style)**:
```lua
local debugger = Debugger:new()

-- Register adapter once
debugger:register_adapter("python", {
  type = "stdio",
  command = "python3",
  args = { "-m", "debugpy.adapter" }
})

-- Add global breakpoint
local bp = debugger:add_breakpoint({ path = "/path/to/file.py" }, 10)

-- Start debugging with a VSCode-style launch configuration
-- SDK handles everything: session creation, initialization, and launch
local session = debugger:start({
  type = "python",
  request = "launch",
  program = "/path/to/file.py",
  console = "internalConsole",
})

-- Wait for stopped state reactively
vim.wait(10000, function()
  return session.state:get() == "stopped"
end)

-- Access stack trace
local thread = session.threads._items[1]
local stack = thread:stack()
local top_frame = stack:top()
```

**Advanced Usage (Manual Control)**:
```lua
-- For fine-grained control, you can manually create and initialize sessions:
local session = debugger:create_session({ type = "python", program = "/path/to/file.py" })
session:initialize({ clientID = "custom-client" })  -- Optional custom args
session:launch({ request = "launch", program = "/path/to/file.py" })
```

### Testing Strategy

Tests use plenary.nvim's busted-style test framework, organized to mirror source structure:

```
tests/
├── helpers/              # Test utilities (minimal_init, test_helpers, mock_server)
├── debug/                # Manual debug scripts (not run by CI)
├── fixtures/             # Test data files (Python, JS programs)
├── neostate/             # Core reactivity tests
├── dap-client/           # DAP protocol tests
└── neodap/
    ├── sdk-uri/          # URI parsing/resolution tests
    ├── sdk-context/      # Debug context tests
    ├── sdk-session/      # Session lifecycle tests
    ├── sdk-thread/       # Thread/stack/frame tests
    ├── sdk-breakpoint/   # Breakpoint binding tests
    ├── sdk-source/       # Source entity tests
    ├── sdk-evaluation/   # Expression evaluation tests
    ├── sdk-collection/   # Collection index tests
    ├── plugins/          # Plugin tests (auto_context, dap_jump, variable_edit, etc.)
    └── integration/      # End-to-end tests with real debuggers
```

- **All SDK tests use real debuggers** - no mocks!
- Test helpers in `tests/helpers/minimal_init.lua`

### Configuration

The reactor can be configured via `neostate.setup()`:
- `trace: boolean` - Enable detailed logging of reactive operations
- `debug_context: boolean` - Add file:line introspection (expensive, uses debug.getinfo)
- `log_fn: function` - Custom logging function (default: print)

### Key Patterns

1. **Reactive Objects**: Combine Disposable + Signal/List properties
   ```lua
   local room = neostate.Disposable({}, nil, "Room")
   room.name = neostate.Signal("Lobby")
   room.name:set_parent(room)  -- Bind lifecycle
   ```

2. **Effect Cleanup**: Return cleanup function from effects
   ```lua
   signal.use(function(value)
     -- effect code
     return function() -- cleanup runs before next update
       -- teardown code
     end
   end)
   ```

3. **Async Safety**: Use `.bind()` to preserve context
   ```lua
   vim.schedule(disposable:bind(function()
     -- children created here inherit disposable's lifecycle
   end))
   ```

4. **Moving Items**: Use `.extract()` + `.adopt()` to transfer between collections
   ```lua
   local item = list1.extract(function(x) return x.id == 5 end)
   list2.adopt(item)  -- Reparents without disposal
   ```

## Development Notes

- Written for Neovim (uses `vim.*` APIs extensively)
- Requires LuaJIT (configured in .emmyrc.json)
- Uses vim.iter for functional iteration patterns
- Nix flake provides reproducible dev environment with all debuggers
- EmmyLua annotations for LSP support
