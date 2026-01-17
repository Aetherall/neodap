# neodap

neodap is a Debug Adapter Protocol (DAP) client for Neovim. It exposes debug state as composable primitives. The built-in plugins are examples of what you can build with them.

## Table of Contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Quick Start](#quick-start)
4. [The Primitives](#the-primitives)
5. [How They Compose](#how-they-compose)
6. [The Built-in Plugins](#the-built-in-plugins)
7. [Building Your Own](#building-your-own)
8. [Reference](#reference)

---

## Requirements

- Neovim 0.10+
- A debug adapter for your language (e.g., debugpy for Python, js-debug for JavaScript, delve for Go)

---

## Installation

**lazy.nvim**:
```lua
{
  "aetherall/neodap",
  config = function()
    require("neodap.boost").setup({
      adapters = { ... },
      keys = true,
    })
  end,
}
```

**packer.nvim**:
```lua
use {
  "aetherall/neodap",
  config = function()
    require("neodap.boost").setup({
      adapters = { ... },
      keys = true,
    })
  end,
}
```

---

## Quick Start

```lua
require("neodap.boost").setup({
  adapters = {
    python = {
      type = "server",
      command = "python",
      args = { "-m", "debugpy.adapter" },
    },
  },
  keys = true,
})
```

This loads all plugins with default keymaps:

| Key | Action |
|-----|--------|
| `<F5>` | Continue |
| `<S-F5>` | Terminate |
| `<F6>` | Pause |
| `<F9>` | Toggle breakpoint |
| `<F10>` | Step over |
| `<F11>` | Step into |
| `<S-F11>` | Step out |
| `<leader>do` | Open debug tree |

### Starting a Debug Session

```vim
:DapLaunch
```

This opens a picker with configurations from `.vscode/launch.json`. Select one to start debugging.

To launch a specific configuration by name:

```vim
:DapLaunch Debug Python
```

For manual plugin control, see [Configuration](#configuration).

---

## The Primitives

### Entities

Debug state is stored as typed objects called entities.

| Entity | What It Is |
|--------|------------|
| Debugger | The root. One per neodap instance. |
| Session | A connection to a debug adapter. |
| Thread | An execution thread. |
| Stack | A snapshot of the call stack when stopped. |
| Frame | A single stack frame. |
| Scope | A group of variables (locals, arguments, etc.). |
| Variable | A variable with name, value, and optional children. |
| Source | A source file. |
| Breakpoint | A breakpoint definition. |
| BreakpointBinding | A breakpoint's state in a specific session. |

Entities have **properties** and **methods**:

```lua
-- Properties (reactive signals)
local name = thread.name:get()
local state = thread.state:get()

-- Methods (actions)
thread:continue()
thread:stepOver()
frame:evaluate("x + y")
variable:setValue("42")
```

Entities connect via **edges**:

```lua
-- Traverse edges
for thread in session.threads:iter() do
  print(thread.name:get())
end

-- Edges are reactive too
session.threads:each(function(thread)
  print("Thread added:", thread.uri:get())
  return function()
    print("Thread removed")
  end
end)
```

### URLs

URLs are a query language for the entity graph.

**Paths** traverse edges:
```
/sessions                         -- all sessions
/sessions/threads                 -- all threads in all sessions
/sessions/threads/stacks/frames   -- all frames
```

**Keys** select specific entities:
```
/sessions:abc                     -- session with key "abc"
/sessions:abc/threads:1           -- thread 1 in session abc
```

**Filters** narrow results:
```
/sessions/threads(state=stopped)  -- only stopped threads
/breakpoints(enabled=true)        -- only enabled breakpoints
```

**Indexes** select by position:
```
/sessions[0]                      -- first session
/sessions[0]/threads[0]           -- first thread of first session
```

**Context markers** reference focused entities:
```
@session                          -- the focused session
@thread                           -- the focused thread
@frame                            -- the focused frame
@frame/scopes                     -- scopes of focused frame
@frame+1                          -- caller frame (one up the stack)
@frame-1                          -- callee frame (one down)
```

**Using URLs**:
```lua
-- Query (returns array)
local threads = debugger:queryAll("/sessions/threads(state=stopped)")

-- Query (returns first match or nil)
local thread = debugger:query("@thread")

-- Watch (returns reactive signal)
debugger:watch("@frame"):use(function(frame)
  print("Frame changed:", frame and frame.name:get())
end)
```

### Signals

Every entity property is a reactive signal.

```lua
-- Read current value
local state = session.state:get()

-- Subscribe to changes
session.state:use(function(state)
  print("Session state:", state)
  return function()
    -- cleanup when subscription ends
  end
end)
```

Edges are also reactive:

```lua
-- React to items added/removed
debugger.breakpoints:each(function(breakpoint)
  print("Breakpoint added")
  return function()
    print("Breakpoint removed")
  end
end)
```

### entity_buffer

`entity_buffer` binds URLs to Neovim buffers. You register a scheme and define how to render/submit:

```lua
local entity_buffer = require("neodap.plugins.utils.entity_buffer")

entity_buffer.register("dap://myscheme", "Variable", "one", {
  render = function(bufnr, variable)
    return variable.value:get()
  end,

  submit = function(bufnr, variable, content)
    variable:setValue(content)
  end,

  setup = function(bufnr, variable, options)
    -- keymaps, autocmds
  end,
})
```

Parameters:
- **scheme**: The buffer URI prefix (e.g., `dap://myscheme`)
- **entity type**: The expected entity type (`"Variable"`, `"Frame"`, etc.)
- **cardinality**: `"one"` expects a single entity, `"many"` expects multiple

Then `:edit dap://myscheme/@frame/scopes[0]/variables:x` opens a buffer bound to that variable. The URL is resolved, the entity is fetched, and your render/submit/setup functions are called.

---

## How They Compose

The primitives layer on each other. Here's how the built-in plugins actually work.

### Variable Editing

The `variable_edit` plugin lets you edit variable values. Here's the core:

```lua
entity_buffer.register("dap://var", "Variable", "one", {
  render = function(bufnr, variable)
    return variable.value:get()
  end,

  submit = function(bufnr, variable, content)
    variable:setValue(content)
  end,

  setup = function(bufnr, variable, options)
    vim.keymap.set("n", "<CR>", function()
      entity_buffer.submit(bufnr)
    end, { buffer = bufnr })
  end,
})
```

That's it. The rest is UI polish (indicators, error handling). The actual feature is:
- **render**: `variable.value:get()`
- **submit**: `variable:setValue(content)`

### Expression Evaluation

The `input_buffer` plugin evaluates expressions. Core:

```lua
entity_buffer.register("dap://input", "Frame", "one", {
  render = function(bufnr, frame)
    return ""  -- empty input
  end,

  submit = function(bufnr, frame, content)
    frame:evaluate(content)
  end,

  setup = function(bufnr, frame, options)
    vim.keymap.set("i", "<CR>", function()
      entity_buffer.submit(bufnr)
    end, { buffer = bufnr })
  end,
})
```

The feature is one line: `frame:evaluate(content)`.

### Floating REPL

The `replline` plugin provides a floating REPL. It doesn't implement evaluation - it just opens `input_buffer` in a floating window:

```lua
local function open()
  -- Create floating window
  local win = vim.api.nvim_open_win(scratch, true, {
    relative = "win",
    row = row,
    col = col,
    width = width,
    height = 1,
  })

  -- Load the input buffer - that's it
  vim.cmd.edit("dap://input/@frame")
end
```

The URL `dap://input/@frame` *is* the feature. The plugin just puts it in a floating window.

### Breakpoint Signs

The `breakpoint_signs` plugin shows signs in the gutter. Core pattern:

```lua
debugger.breakpoints:each(function(breakpoint)
  -- React to each breakpoint
  breakpoint.bindings:each(function(binding)
    -- React to each binding
    local function update()
      local state = get_binding_state(binding)
      place_sign(breakpoint, state)
    end

    -- Update when binding state changes
    binding.verified:use(update)
    binding.hit:use(update)

    return function()
      remove_sign(breakpoint)
    end
  end)

  return function()
    remove_sign(breakpoint)
  end
end)
```

Pattern: subscribe to edges, subscribe to properties, update UI.

### Frame Highlights

The `frame_highlights` plugin highlights the current line. Core:

```lua
debugger:watch("@frame"):use(function(frame)
  clear_highlights()
  if frame then
    local source = frame.source:get()
    local line = frame.line:get()
    if source and line then
      highlight_line(source.path:get(), line)
    end
  end
end)
```

Pattern: watch a URL, update UI when it changes.

### Control Commands

The `control_cmd` plugin provides `:Dap continue`, etc. Core:

```lua
vim.api.nvim_create_user_command("DapContinue", function(opts)
  local url = opts.args ~= "" and opts.args or "@thread"
  local threads = debugger:queryAll(url)
  for _, thread in ipairs(threads) do
    thread:continue()
  end
end, { nargs = "?" })
```

Pattern: query URL, call methods on results.

---

## The Built-in Plugins

All plugins use the same primitives. Here's what each one does:

### Core

| Plugin | What It Does |
|--------|--------------|
| `dap` | Connects to adapters, wires DAP events to entity state. Required. |
| `command_router` | Routes `:Dap foo` to `:DapFoo`. |

### Commands (query URL → call methods)

| Plugin | Commands |
|--------|----------|
| `control_cmd` | `continue`, `pause`, `terminate` |
| `step_cmd` | `step over/into/out` |
| `breakpoint_cmd` | `breakpoint toggle/condition/hit/log/enable/disable/clear` |
| `exception_cmd` | `exception toggle/enable/disable/list` |
| `focus_cmd` | `focus` |
| `jump_cmd` | `jump` |
| `list_cmd` | `list` |
| `run_to_cursor_cmd` | `run-to-cursor` |
| `bulk_cmd` | `enable`, `disable`, `remove` |

### Buffers (entity_buffer schemes)

| Plugin | Scheme | Entity |
|--------|--------|--------|
| `tree_buffer` | `dap://tree/` | Any (tree view) |
| `input_buffer` | `dap://input/` | Frame (expression eval) |
| `variable_edit` | `dap://var/` | Variable (edit value) |
| `source_buffer` | `dap://source/` | Source (file content) |
| `url_buffer` | `dap://url/` | Any (generic view) |
| `stdio_buffers` | `dap://stdout/`, etc. | Session (output) |
| `replline` | — | Opens `dap://input/` in float |

### Reactive UI (subscribe → update)

| Plugin | Subscribes To | Updates |
|--------|---------------|---------|
| `breakpoint_signs` | `breakpoints:each`, binding state | Gutter signs |
| `frame_highlights` | `@frame` | Line highlight |
| `inline_values` | `@frame` | Virtual text with values |
| `jump_stop` | Thread stopped event | Jumps to location |
| `cursor_focus` | Cursor position | Debug focus |

### Integrations

| Plugin | Integrates With |
|--------|-----------------|
| `completion` | nvim-cmp |
| `lualine` | lualine.nvim |
| `neotest_strategy` | neotest |
| `code_workspace` | VS Code launch.json |

### Infrastructure

| Plugin | What It Does |
|--------|--------------|
| `uri_picker` | Shows picker when URL matches multiple entities |
| `stack_nav` | Enables `@frame+1`, `@frame-1` |
| `leaf_session` | Tracks leaf sessions for multi-target debugging |
| `hit_polyfill` | Determines hit breakpoint for adapters that don't report it |

---

## Building Your Own

### Pattern: React to changes

Subscribe to signals or edges, update something:

```lua
-- React to frame changes
debugger:watch("@frame"):use(function(frame)
  -- update your UI
end)

-- React to breakpoints added/removed
debugger.breakpoints:each(function(bp)
  -- breakpoint added
  return function()
    -- breakpoint removed
  end
end)

-- React to property changes
session.state:use(function(state)
  -- state changed
end)
```

### Pattern: Buffer for an entity

Register a scheme with entity_buffer:

```lua
entity_buffer.register("dap://myscheme", "Frame", "one", {
  render = function(bufnr, frame)
    -- return string to display
    return "Frame: " .. frame.name:get()
  end,

  submit = function(bufnr, frame, content)
    -- handle user input (optional)
  end,

  setup = function(bufnr, frame, options)
    -- keymaps, autocmds (optional)
  end,

  on_change = "always", -- or "skip_if_dirty"
})

-- Open with :edit dap://myscheme/@frame
```

### Pattern: Command that operates on entities

Query a URL, call methods:

```lua
vim.api.nvim_create_user_command("DapMyCommand", function(opts)
  local url = opts.args ~= "" and opts.args or "@session"
  local sessions = debugger:queryAll(url)

  for _, session in ipairs(sessions) do
    session:terminate()
  end
end, { nargs = "?" })
```

### Pattern: Compose existing plugins

Use URLs to leverage other plugins:

```lua
-- Open input_buffer in a split
vim.cmd("split")
vim.cmd.edit("dap://input/@frame")

-- Open tree for specific session
vim.cmd.edit("dap://tree/session:abc")

-- Open variable editor
vim.cmd.edit("dap://var/@frame/scopes[0]/variables:myVar")
```

---

## Reference

### Commands

| Command | Arguments | What It Does |
|---------|-----------|--------------|
| `:Dap continue [url]` | URL (default: `@thread`) | Continue execution |
| `:Dap pause [url]` | URL (default: `@thread`) | Pause execution |
| `:Dap terminate [url]` | URL (default: `@session`) | Terminate session |
| `:Dap step over [granularity] [url]` | `statement`/`line`/`instruction`, URL | Step over |
| `:Dap step into [granularity] [url]` | Same | Step into |
| `:Dap step out [granularity] [url]` | Same | Step out |
| `:Dap breakpoint` | — | Toggle at cursor |
| `:Dap breakpoint toggle [line]` | Line number | Toggle at line |
| `:Dap breakpoint condition [line] <expr>` | Line, expression | Set condition |
| `:Dap breakpoint hit [line] <count>` | Line, count | Set hit condition |
| `:Dap breakpoint log [line] <msg>` | Line, message | Set logpoint |
| `:Dap breakpoint enable [line]` | Line | Enable |
| `:Dap breakpoint disable [line]` | Line | Disable |
| `:Dap breakpoint clear` | — | Remove all |
| `:Dap exception toggle <filter>` | Filter ID | Toggle exception filter |
| `:Dap exception enable <filter> [cond]` | Filter ID, condition | Enable filter |
| `:Dap exception disable <filter>` | Filter ID | Disable filter |
| `:Dap exception list` | — | List filters |
| `:Dap focus <url>` | URL | Focus entity |
| `:Dap jump [url]` | URL (default: `@frame`) | Jump to source |
| `:Dap list <url>` | URL | List to quickfix |
| `:Dap run-to-cursor` | — | Run to cursor line |
| `:Dap enable [url]` | URL | Enable entities |
| `:Dap disable [url]` | URL | Disable entities |
| `:Dap remove [url]` | URL | Remove entities |

### Entity Properties and Methods

**Session**
```lua
session.sessionId:get()       -- string
session.name:get()            -- string
session.state:get()           -- "starting" | "running" | "stopped" | "terminated"
session.threads               -- edge to Thread
session.outputs               -- edge to Output
session:terminate()
session:disconnect()
```

**Thread**
```lua
thread.threadId:get()         -- number
thread.name:get()             -- string
thread.state:get()            -- "running" | "stopped" | "exited"
thread.stacks                 -- edge to Stack
thread:continue()
thread:pause()
thread:stepOver(opts)
thread:stepIn(opts)
thread:stepOut(opts)
```

**Frame**
```lua
frame.frameId:get()           -- number
frame.name:get()              -- string (function name)
frame.line:get()              -- number
frame.column:get()            -- number
frame.source:get()            -- Source entity
frame.scopes                  -- edge to Scope
frame:evaluate(expr, context) -- evaluate expression
frame:fetchScopes()
```

**Scope**
```lua
scope.name:get()              -- string ("Locals", "Globals", etc.)
scope.variablesReference:get() -- number
scope.variables               -- edge to Variable
scope:fetchVariables()
```

**Variable**
```lua
variable.name:get()           -- string
variable.value:get()          -- string
variable.varType:get()        -- string
variable.children             -- edge to Variable
variable:fetchChildren()
variable:setValue(value)
```

**Breakpoint**
```lua
breakpoint.line:get()         -- number
breakpoint.column:get()       -- number
breakpoint.condition:get()    -- string or nil
breakpoint.hitCondition:get() -- string or nil
breakpoint.logMessage:get()   -- string or nil
breakpoint.enabled:get()      -- boolean
breakpoint.bindings           -- edge to BreakpointBinding
breakpoint:remove()
breakpoint:setEnabled(bool)
breakpoint:setCondition(expr)
```

**Source**
```lua
source.path:get()             -- string
source.name:get()             -- string
source.breakpoints            -- edge to Breakpoint
source.frames                 -- edge to Frame
```

### URL Syntax

```
/edge                         -- all entities via edge
/edge:key                     -- entity by key
/edge[index]                  -- entity by index
/edge(prop=value)             -- filter by property
/edge/edge/edge               -- chain traversals
@context                      -- focused entity (@session, @thread, @frame)
@frame+N                      -- N frames up the stack
@frame-N                      -- N frames down the stack
```

### Configuration

**With boost (recommended)**:
```lua
require("neodap.boost").setup({
  adapters = { ... },
  keys = true,
  icons = { ... },
  plugins = {
    plugin_name = { ... },
  },
})
```

**Manual setup**:
```lua
local neodap = require("neodap")
local debugger = neodap.setup({ adapters = { ... } })

debugger:use(neodap.plugins.dap)
debugger:use(neodap.plugins.command_router)
debugger:use(neodap.plugins.control_cmd)
-- ... load plugins individually
```

**Adapter types**:
```lua
-- stdio: communicate via stdin/stdout
{ type = "stdio", command = "dlv", args = { "dap" } }

-- tcp: connect to running adapter
{ type = "tcp", host = "127.0.0.1", port = 5678 }

-- server: launch process, wait for port, connect
{ type = "server", command = "js-debug-adapter", args = {} }
```
