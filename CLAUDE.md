## Neodap Codebase Guide

- [nui source](./.cache/tests/data/nvim/lazy/nui.nvim/lua/nui/tree)

### 1. Overarching Purpose & Core Philosophy

`neodap` is a **Neovim Debug Adapter Protocol (DAP) client SDK**. Its fundamental purpose is to provide a flexible and extensible foundation for building custom debugging experiences within Neovim. Unlike monolithic DAP clients, `neodap` is designed as a library that other plugins use to interact with debuggers.

**Core Philosophy: Integrate, Don't Re-implement.** The codebase favors deep integration with existing UI libraries over building new management layers. When developing, your goal should be to write the *minimum* code necessary to bridge `neodap`'s functionality with other tools, delegating tasks like UI management, state, and caching whenever possible.

**Example:** The Variables plugin demonstrates this philosophy perfectly:
- ✅ Uses NUI components for tree widgets instead of building custom UI
- ✅ Leverages existing expand/collapse functionality from UI libraries
- ✅ Benefits from established keybinding and interaction patterns
- ✅ Only implements the DAP-specific logic for fetching variables
- ❌ Avoids duplicating tree navigation, rendering, or state management code

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

-   **`PascalCase` methods are automatically asynchronous with context-aware behavior:**
    - **From sync context (keymaps, commands):** Fire-and-forget execution. Returns a poison value that warns if used. Cannot get return values.
    - **From async context (inside other PascalCase methods):** Normal execution with proper return values and error propagation.
    - **CRITICAL WARNING:** Errors in PascalCase methods are logged but swallowed by default - execution continues! Your code may fail silently.
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

#### 4.4. Error Handling Philosophy

**Automatic Error Recovery**: The framework handles all errors in PascalCase methods automatically. This is a core feature - you should NOT add manual error handling.

**What the framework does for you:**
- Catches all errors in async operations automatically
- Logs them with full stack traces
- Continues execution gracefully
- Prevents cascade failures across plugins

**What you SHOULD do:**
```lua
function MyPlugin:ProcessData()  -- PascalCase method
  -- Only check for optional/expected nil values
  if not self.current_frame then
    return  -- This is expected when not debugging
  end
  
  -- Write simple, direct code - let errors bubble up
  local data = self.current_frame.value
  self:updateUI(data)
end
```

**What you should NOT do:**
```lua
-- ❌ DON'T use pcall - the framework already catches errors
local ok, result = pcall(function() 
  return self.session:evaluate(expr)
end)

-- ❌ DON'T add try/catch patterns - that's redundant
if not ok then
  self.logger:error("Failed to evaluate")  -- Framework already logs!
  return
end

-- ✅ DO write straightforward code
local result = self.session:evaluate(expr)  -- If this errors, framework handles it
```

**Debugging When Things Go Wrong:**
1. Set `NEODAP_PANIC=true` environment variable to make errors fatal (for debugging only)
2. Check log files in `~/.local/state/nvim/neodap/` to see caught errors
3. The framework logs full stack traces - use them to find the issue

**Philosophy:** Write code as if errors don't exist. The framework ensures your plugin won't crash Neovim, while still logging all issues for debugging.

#### 4.5. API Layer Discipline

**NEVER bypass the API layer.** Direct access to internal structures is fragile and will break:

❌ **WRONG - Accessing internals:**
```lua
-- This reaches through multiple internal layers
self.current_frame.stack.thread.session.ref.calls:variables(...)
```

✅ **CORRECT - Using API methods:**
```lua
-- Use the provided API methods that handle edge cases
self.session:variables(...)  -- or appropriate API method
```

**Why this matters:**
- Internal structures change between versions
- The API provides stability and proper error handling
- Direct access bypasses important state management



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

   1. Create a `.spec.lua` file in a `specs/` subdirectory next to the plugin (e.g., `lua/neodap/plugins/YourPlugin/specs/`).
   2. Define a `T.Scenario`. This is the container for your test case.
   3. Set up the initial state. Use T.cmd("edit ...") to open a fixture file and
      T.cmd("normal! ...") to position the cursor.
   4. Launch the debug session if needed, using T.cmd("NeodapLaunchClosest ...").
      - IMPORTANT: The configuration name must match exactly what's in launch.json.
      - For example: "Stack [stack]" not "Stack [deep]" if launch.json has "Stack".
   5. Wait for async operations ONLY when necessary:
      - T.sleep(1000-2000) after launching to wait for debugger to start/hit breakpoints
      - T.sleep(500-1100) after breakpoint operations that trigger stops
      - NO sleep needed between PascalCase navigation commands (they're auto-async)
   6. Capture snapshots at meaningful points:
      - Multiple synchronous commands can be executed before a snapshot
      - Each snapshot should demonstrate a distinct visual state
   7. Run the test file to generate snapshots and get feedback on the visual output.
   8. Review the generated snapshots to ensure they represent the expected visual states. If they don't, interpret the reason for the difference and think about why the expected outcome was not reached. 

  3. Strict Prohibitions

   - You WILL NOT use assert.is_true, assert.spy, or any other assertion function.
   - You WILL NOT check return values or programmatically verify application state.
   - Your ONLY output is the terminal snapshot generated by T.TerminalSnapshot.
   - You WILL NOT consider the test passed or failed based on the test command result code. Only the visual snapshots matter.

  4. Boilerplate Example (With Debug Session)

  Use this exact structure for your tests.
```lua
-- 1. Require the testing helper
local T = require("testing.testing")(describe, it)

-- 2. Define the scenario
T.Scenario(function(api)
  -- 3. Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))

  -- 4. Set up initial state and launch session
  T.cmd("edit lua/testing/fixtures/loop/loop.js")
  T.cmd("NeodapLaunchClosest Loop [loop]")  -- Must match launch.json name exactly
  
  -- 5. Wait for session to start
  T.sleep(1100)
  
  -- 6. Position cursor and capture initial state
  T.cmd("normal! 2j") -- Move to line 3
  T.TerminalSnapshot('before_toggle')

  -- 7. Execute action and wait for async result
  T.cmd("NeodapToggleBreakpoint")
  T.sleep(1100) -- Wait for breakpoint to be set and hit

  -- 8. Capture final state
  T.TerminalSnapshot('hit')
end)
```

  5. Testing Complex UI Plugins

  Visual verification extends beyond single buffers. When testing plugins that create windows or sidebars:

  5.1. NUI Tree Integration Testing

  ```lua
  T.Scenario(function(api)
    -- Load the UI plugin
    api:getPluginInstance(require('neodap.plugins.Variables4'))
    
    -- Launch and hit breakpoint first
    T.cmd("edit lua/testing/fixtures/variables/complex.js")
    T.cmd("NeodapLaunchClosest Variables [variables]")
    T.sleep(1500)
    
    -- Open the UI popup
    T.cmd("Variables4TreeDemo")
    T.sleep(300)  -- Let UI render
    T.TerminalSnapshot('variables_popup_open')
    
    -- Interact with tree nodes using Enter/Space
    T.cmd("execute \"normal \\<CR>\"")  -- Expand first scope
    T.sleep(200)  -- Let lazy loading complete
    T.TerminalSnapshot('scope_expanded')
    
    -- Navigate and expand variables
    T.cmd("normal! j")  -- Move to next item
    T.cmd("execute \"normal \\<CR>\"")  -- Expand variable
    T.sleep(200)
    T.TerminalSnapshot('variable_expanded')
  end)
  ```

  5.2. Multi-Window Snapshot Guidelines

  - Capture the entire terminal screen, not just current buffer
  - Test popup interactions with proper keysend commands
  - Verify popup content renders correctly
  - Allow time for lazy-loaded content
  - Use appropriate fixtures with complex data

  5.3. Common UI Testing Patterns

  ```lua
  -- Opening popups
  T.cmd("Variables4TreeDemo")  -- Open variables popup
  
  -- Tree interaction (NUI Tree)
  T.cmd("execute \"normal \\<CR>\"")  -- Toggle node expand/collapse
  T.cmd("execute \"normal \\<Space>\"")  -- Alternative toggle
  T.cmd("normal! j")  -- Navigate down
  T.cmd("normal! k")  -- Navigate up
  T.cmd("normal! q")  -- Close popup
  ```

  5.4. NUI Tree Integration Specifics

  **Critical Discovery:** NUI Tree popups require proper keypress handling in tests.

  **Problem:** Direct normal commands may not work in popup contexts:
  ```lua
  -- ❌ May not work reliably in popup buffers  
  T.cmd("normal! o")
  ```

  **Solution:** Use execute to send keystrokes properly:
  ```lua
  -- ✅ WORKS - NUI popup receives the keypress correctly
  T.cmd("execute \"normal \\<CR>\"")  -- Send Enter key
  T.cmd("execute \"normal \\<Space>\"")  -- Send Space key
  ```

  **Key Insights:**
  - NUI Tree uses buffer mappings for interaction
  - Keys are mapped to functions (e.g., Enter → expand/collapse)
  - The plugin defines custom keymaps in popup:map() calls
  - Async data loading requires appropriate sleep times after expansion

  **Example: Variables Plugin Integration**
  ```lua
  -- In the plugin's popup setup
  popup:map("n", "<CR>", function()
    local node = tree:get_node()
    if node and node.type == "scope" and not node._variables_loaded then
      -- Async loading with proper NUI Tree API
      NvimAsync.defer(function()
        local variables = node._scope:variables()
        tree:set_nodes(var_children, node:get_id())
        tree:render()
      end)()
    end
    node:expand()
    tree:render()
  end)
  ```

  6. Common Pitfalls and Solutions

  6.1. Silent Test Passes
  **Problem:** Test passes but feature is broken due to swallowed errors.
  **Solution:** 
  - Set `NEODAP_PANIC=true` during test development
  - Check logs in `~/.local/state/nvim/neodap/` after test runs
  - Verify snapshots show expected content, not empty UI

  6.2. Wrong Test Fixtures
  **Problem:** Reusing unrelated fixtures misses edge cases.
  **Solution:** Use dedicated fixtures that match your feature:
  ```
  lua/testing/fixtures/
  ├── variables/     # Complex objects, arrays, nested data
  ├── stack/         # Deep call stacks
  ├── breakpoints/   # Various breakpoint scenarios
  └── loop/          # Simple continuous execution
  ```

  6.3. Incomplete Visual Verification
  **Problem:** Testing breakpoint hit instead of actual feature UI.
  **Solution:** Always capture the feature's output:
  - Open the window/sidebar being tested
  - Interact with UI elements
  - Capture multiple states showing progression
  - Verify content appears, not just that commands exist

  6.4. Missing Error Context
  **Problem:** Errors occur but tests don't show them.
  **Solution:** During test development:
  ```lua
  -- At the start of your test file
  vim.env.NEODAP_PANIC = "true"  -- Make errors fatal
  
  -- Or check logs after suspicious behavior
  T.cmd("!tail -20 ~/.local/state/nvim/neodap/*.log")
  T.TerminalSnapshot('error_logs')
  ```