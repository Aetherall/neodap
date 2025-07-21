## Neodap Codebase Guide

### 1. Overarching Purpose

`neodap` is a **Neovim Debug Adapter Protocol (DAP) client SDK**. Its fundamental purpose is to provide a flexible and extensible foundation for building custom debugging experiences within Neovim. Unlike monolithic DAP clients, `neodap` is designed as a library or framework that other Neovim plugins can use to interact with DAP-compliant debuggers.

The core philosophy is to expose the DAP features through a clean, hierarchical, and event-driven Lua API, allowing developers to create sophisticated and customized debugging workflows that are not easily achievable with existing tools. It supports multiple concurrent DAP sessions, session hierarchies (for multi-process debugging), and a rich event model for reacting to debugger state changes.

### 2. Directory Structure

The project is structured as follows:

-   **`lua/neodap/`**: The main source code for the `neodap` library.
    -   **`api/`**: The public-facing API that developers will use to interact with the debugger. This is the primary entry point for plugin developers.
    -   **`adapter/`**: Handles the connection to the debug adapter. It abstracts the communication layer (e.g., TCP, stdio) between Neovim and the debug adapter.
    -   **`session/`**: Manages the state of a debugging session, including its lifecycle, child sessions, and communication with the adapter.
    -   **`transport/`**: Implements the low-level DAP message passing, including requests, responses, and events.
    -   **`tools/`**: Utility modules for common tasks like class creation, logging, and asynchronous operations.
    -   **`plugins/`**: A collection of pre-built functionalities that can be loaded into the API, such as breakpoint management and UI components.
-   **`spec/`**: Contains the test suite for the project, written in `busted`.
-   **`examples/`**: Example code demonstrating how to use the `neodap` SDK.

### 3. Key Files and Call Chains

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

This function creates a `session.manager` and an `api.Api` instance. The `session.manager` is responsible for creating, tracking, and destroying debug sessions. The `api.Api` is the main object that developers will interact with.

#### 3.2. The API Layer (`lua/neodap/api/`)

The `api` directory contains the high-level abstractions that wrap the core DAP functionality.

**`lua/neodap/api/Api.lua`**:

This is the central hub for the entire SDK. It manages all active sessions and provides an event-driven interface for plugins to hook into the debugging lifecycle.

-   **`Api:onSession(listener)`**: A key function that allows plugins to register a callback that will be executed for each new debugging session. This is the primary way to attach functionality to a session.
-   **`Api:loadPlugin(plugin_module)`**: A mechanism to load and instantiate plugins, ensuring that each plugin is a singleton within the API instance.

**`lua/neodap/api/Session/Session.lua`**:

This module wraps a `session.session` object and exposes a more user-friendly API. It provides methods for interacting with a specific debugging session, such as setting breakpoints, controlling execution (e.g., `continue`, `pause`), and querying the debugger's state.

#### 3.3. Session Management (`lua/neodap/session/`)

**`lua/neodap/session/session.lua`**:

This is the heart of a debugging session. It manages the connection to the debug adapter and orchestrates the flow of DAP messages.

-   **`Session:start(opts)`**: Initiates the debugging session by launching or attaching to the debug adapter. It sets up the message handlers for events, requests, and responses.
-   **`Session:close()`**: Terminates the debugging session.

#### 3.4. Transport Layer (`lua/neodap/transport/`)

This layer is responsible for the raw DAP message handling.

-   **`lua/neodap/transport/calls.lua`**: A class that abstracts the process of making a DAP request and waiting for the corresponding response. It dynamically generates methods for each DAP request (e.g., `initialize`, `launch`, `setBreakpoints`).
-   **`lua/neodap/transport/events.lua`**: A class that handles incoming DAP events (e.g., `stopped`, `terminated`, `breakpoint`). It uses a `hookable` system to allow different parts of the codebase to listen for specific events.
-   **`lua/neodap/transport/handlers.lua`**: A class that manages reverse requests from the debug adapter to the client (e.g., `runInTerminal`).

#### 3.5. Adapter Layer (`lua/neodap/adapter/`)

**`lua/neodap/adapter/executable_tcp.lua`**:

This is a concrete implementation of a debug adapter that is launched as an executable and communicates over a TCP socket.

-   **`ExecutableTCPAdapter.create(opts)`**: Creates a new adapter instance, configuring the executable command and connection details.
-   **`ExecutableTCPAdapter:start(opts)`**: Spawns the executable (if not already running) and establishes a TCP connection.

### 4. Important Concepts and Quirks

#### 4.1. Class System and Asynchronous Operations

`neodap` uses a custom class system defined in `lua/neodap/tools/class.lua`. A notable feature of this class system is its automatic wrapping of methods with uppercase first letters in an asynchronous context using `nio`. This is a significant quirk to be aware of, as it means that any method call like `session:Continue()` will be executed asynchronously and will not block.

#### 4.2. Event-Driven Architecture

The entire SDK is heavily event-driven. The `Api:onSession`, `Session:onThread`, and `Thread:onStopped` pattern is a clear example of this. This allows for a very decoupled and extensible architecture, but it also means that the control flow can be less linear and harder to follow. When writing code that interacts with `neodap`, it's crucial to think in terms of events and callbacks rather than sequential execution.

#### 4.3. Hierarchical Sessions

`neodap` supports hierarchical debugging sessions, where one session can spawn child sessions. This is managed in `lua/neodap/session/session.lua` through the `parent` and `children` properties of the `Session` class. This is a powerful feature for debugging complex applications, but it adds a layer of complexity to session management.

#### 4.4. Virtual Buffers

The `lua/neodap/api/VirtualBuffer/` directory introduces the concept of "virtual buffers". These are used to display content that doesn't correspond to a file on disk, such as the output of a debugger command or the content of a source file from a remote machine. This is a key feature for providing a rich debugging experience in Neovim.

### 5. Conclusion

`neodap` is a well-structured and powerful SDK for building DAP clients in Neovim. Its modular design, event-driven architecture, and clean API make it a flexible tool for creating custom debugging workflows. When working with the codebase, it is essential to understand the asynchronous nature of many of its components, the event-driven control flow, and the hierarchical session management. The `api` layer is the intended entry point for most developers, and the `plugins` system provides a convenient way to extend the core functionality.