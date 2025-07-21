## Neodap Codebase Guide

### 1. Overarching Purpose & Core Philosophy

`neodap` is a **Neovim Debug Adapter Protocol (DAP) client SDK**. Its fundamental purpose is to provide a flexible and extensible foundation for building custom debugging experiences within Neovim. Unlike monolithic DAP clients, `neodap` is designed as a library that other plugins use to interact with debuggers.

**Core Philosophy: Integrate, Don't Re-implement.** The codebase favors deep integration with existing tools (like `neo-tree`) over building new management layers. When developing, your goal should be to write the *minimum* code necessary to bridge `neodap`'s functionality with other tools, delegating tasks like UI management, state, and caching whenever possible.

### 2. Directory Structure

The project is structured as follows:

-   **`lua/neodap/`**: The main source code for the `neodap` library.
    -   **`api/`**: The public-facing API that developers use. This is the primary entry point for plugin developers.
    -   **`adapter/`**: Handles the connection to the debug adapter (e.g., TCP, stdio).
    -   **`session/`**: Manages the state of a debugging session, its lifecycle, and communication.
    -   **`transport/`**: Implements the low-level DAP message passing (requests, responses, events).
    -   **`tools/`**: Utility modules. `class.lua` and `logger.lua` are critical.
    -   **`plugins/`**: Pre-built functionalities (breakpoint management, UI components) that serve as great examples.
-   **`spec/`**: The test suite (`busted`), an excellent source for usage examples.
-   **`examples/`**: Example code demonstrating how to use the SDK.

### 3. Key Files, Call Chains, and Architectural Concepts

#### 3.1. Initialization and Setup

The entry point for using `neodap` is the `neodap.setup()` function.

**`lua/neodap.lua`**:
```lua
local M = {}

function M.setup()
  local Manager = require("neodap.session.manager")
  local Api = require("neodap.api.Api")

  local manager = Manager.create()
  local api = Api.register(manager)

  return manager, api
end

return M
```
This creates the `session.manager` (for tracking sessions) and the `api.Api` (the main object developers interact with).

#### 3.2. The API Layer (`lua/neodap/api/`)

This is the high-level, user-friendly wrapper around the core logic.

**`lua/neodap/api/Api.lua`**:
This is the central hub. It manages all active sessions and provides an event-driven interface.
-   **`Api:onSession(listener)`**: The primary way to attach functionality. It registers a callback that executes for each new debug session.
-   **`Api:loadPlugin(plugin_module)`**: Loads and instantiates plugins, ensuring singletons.

**`lua/neodap/api/Session/Session.lua`**:
This wraps a core `session.session` object, exposing a cleaner API for controlling execution (`continue`, `pause`), setting breakpoints, and querying state.

#### 3.3. Session Management (`lua/neodap/session/`)

**`lua/neodap/session/session.lua`**:
This is the heart of a debugging session. It manages the DAP connection and message flow.
-   **`Session:start(opts)`**: Initiates the session by launching or attaching to the debug adapter and setting up message handlers.
-   **`Session:close()`**: Terminates the session.

#### 3.4. Transport Layer (`lua/neodap/transport/`)

This layer handles raw DAP message passing.
-   **`calls.lua`**: Abstracts DAP requests and waits for responses. It dynamically generates methods for each DAP request (`initialize`, `launch`, etc.).
-   **`events.lua`**: Handles incoming DAP events (`stopped`, `terminated`) using a `hookable` system.
-   **`handlers.lua`**: Manages reverse requests from the adapter to the client (`runInTerminal`).

#### 3.5. Adapter Layer (`lua/neodap/adapter/`)

**`lua/neodap/adapter/executable_tcp.lua`**:
A concrete implementation for a debug adapter launched as an executable communicating over TCP.

### 4. Critical Concepts and Quirks for Developers

#### 4.1. The Auto-Async Naming Convention

`neodap` uses a critical, non-obvious convention for handling asynchronicity, defined in **`lua/neodap/tools/class.lua`**. You must follow it.

-   **`PascalCase` methods are automatically asynchronous.** The class helper wraps any method defined with a `PascalCase` name (e.g., `MyMethod`) in an async handler. Call these directly from synchronous contexts like keymaps or user commands without blocking the UI. **Do not wrap them again.**
-   **`camelCase` methods are synchronous.** They execute immediately. Use them for logic that does not involve I/O or DAP calls.

**Correct Usage:**
```lua
-- In a plugin file:
-- This method makes a DAP call, so it's PascalCase.
function MyPlugin:StepOver()
  self.session:stepOver() -- This is an async DAP call
end

-- At a vim context boundary (e.g., init.lua)
-- The call is clean. The async handling is automatic.
vim.keymap.set('n', '<F10>', function() plugin:StepOver() end)
```

#### 4.2. Breakpoint Architecture: Lazy Binding

The system makes a hard distinction between user intent and verified reality.

-   **`Breakpoint`**: Represents **user intent**. It's a simple object that says "I want to pause at `file.lua:42`". It is stateless regarding debug sessions.
-   **`Binding`**: Represents a **DAP-verified breakpoint** in a specific `Session`. A `Binding` is only created *after* the debug adapter confirms that it could set the breakpoint. It contains the DAP-assigned ID and the actual location.

**Implication:** Do not assume a `Breakpoint` object means an active breakpoint in a running session. The `Binding` is the source of truth. This "lazy" creation of bindings prevents a whole class of state-management bugs.

#### 4.3. Event-Driven and Hierarchical by Default

The entire SDK is heavily event-driven. The `Api:onSession`, `Session:onThread`, and `Thread:onStopped` pattern is the standard way to interact with the system. This allows for a decoupled architecture. When you hook into an object, its parent manages its lifecycle, so you rarely need to handle cleanup manually.



# Guideline for Writing neodap Visual Verification Tests

  1. Critical Philosophy: Your Job is to Generate Snapshots, Not to Assert

  You are not writing traditional tests. The test runner will always pass. Your sole
  function is to generate terminal snapshots for human review.

   - DO NOT write any code to check for correctness.
   - DO NOT use any assertion libraries (assert, spy, etc.).
   - A "passing" test in the console means only that the code ran without errors. It DOES 
     NOT mean the feature works.
   - The actual "test" is a human looking at the diff of the snapshots you generate. Your
     goal is to produce a correct visual artifact for this review.

  2. The Mandatory Testing Workflow

  You MUST follow this exact sequence.

   1. Create a `.spec.lua` file next to the plugin you are testing.
   2. Define a `T.Scenario`. This is the container for your test case.
   3. Set up the initial state. Use T.cmd("edit ...") to open a fixture file and
      T.cmd("normal! ...") to position the cursor.
   4. Launch the debug session if needed, using T.cmd("NeodapLaunchClosest ...").
   5. Capture the "before" state. Call T.TerminalSnapshot('before').
   6. Execute the user action. Use T.cmd("Neodap...") to call the command being tested.
   7. Wait for async UI updates. If the action is asynchronous, you MUST use T.sleep() to
      wait for the UI to settle. A common value is T.sleep(1100).
   8. Capture the "after" state. Call T.TerminalSnapshot('after') or a more descriptive name
      like 'hit'.

  3. Strict Prohibitions

   - You WILL NOT use assert.is_true, assert.spy, or any other assertion function.
   - You WILL NOT check return values or programmatically verify application state.
   - Your ONLY output is the terminal snapshot generated by T.TerminalSnapshot.

  4. Boilerplate Example (With Debug Session)

  Use this exact structure for your tests.
```lua
-- 1. Require the testing helper
local T = require("testing.testing")(describe, it)

-- 2. Define the scenario
T.Scenario(function(api)
  -- 3. Load necessary plugins, including for launch support
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))

  -- 4. Set up the initial state and launch a session
  T.cmd("edit lua/testing/fixtures/loop/loop.js")
  T.cmd("NeodapLaunchClosest Loop [loop]")
  T.cmd("normal! 2j") -- Move to line 3

  -- 5. Capture the 'before' snapshot (session is running)
  T.TerminalSnapshot('before_toggle')

  -- 6. Execute the action
  T.cmd("NeodapToggleBreakpoint")
  T.sleep(1100) -- Wait for breakpoint to be set and hit

  -- 7. Capture the 'after' snapshot
  T.TerminalSnapshot('hit')
end)
```