# Entity Presentation Design

Companion to [entity-presentation.md](./entity-presentation.md), which documents the current fragmentation. This document describes three enablers that address the root causes of that duplication while preserving consumer flexibility, and the implementation tactic chosen to deliver them.

## The Three Enablers

1. **Useful Entity Methods** — entities expose semantically meaningful derived state
2. **Composable Entity UI Components** — shared display building blocks that consumers arrange freely
3. **Abstract Entity Actions** — named action recipes that encapsulate multi-step operations

These three layers compose: entity methods feed components, components feed UI surfaces, and actions provide a shared vocabulary for entity operations across all surfaces.

## Implementation Tactic: Two-Key Registry on Debugger

Both components and actions use the same pattern: a **two-key registry** on the debugger instance, keyed by `(name, entity_type)`.

```lua
debugger:register_component(name, entity_type, fn)
debugger:register_action(name, entity_type, fn)
```

This is a double-dispatch: the first key is the **concept** (`"icon"`, `"title"`, `"toggle"`, `"focus"`), the second key is the **entity type** (`"Session"`, `"Frame"`, `"Breakpoint"`). The same concept can have different implementations per entity type.

### Why Two Keys

A single-key-by-type registration (`register_components("Session", { icon = fn, title = fn })`) bundles all components for a type together. This makes it easy to get everything for a Session, but makes it impossible to ask "give me the title for any entity" without knowing all types up front.

Two-key registration gives both axes:

- **By type**: `debugger:components(entity)` → `{ icon = segment, title = segment, ... }` — all components for this entity
- **By name**: `debugger:component("title", entity)` → `segment` — one concept, dispatched by entity type
- **Extension on either axis**: a community plugin can register a new component name for existing types, or register existing component names for new types

### Why On Debugger

`debugger:query()` and `debugger:queryAll()` are core infrastructure added by `identity/init.lua` — they bridge the entity graph to consumers. Components and actions serve the same role: they bridge entity semantics to UI surfaces. They belong at the same level, as core infrastructure on the debugger instance.

### Why Components Return Plain Tables

Components return `{ text = string, hl? = string }` or `nil`. Plain tables, not signals.

neodap's reactivity model has a clear split between two consumption patterns:

1. **Synchronous snapshot**: renderers call `:get()` on entity signals during a render pass. The tree buffer's View watches the graph for structural changes and debounces re-renders at 16ms. Each render pass calls `:get()` to snapshot current values.

2. **Reactive subscription**: plugins like `breakpoint_signs` call `signal:use(fn)` to watch individual signals and update incrementally.

Components fit pattern #1. Existing entity methods that produce display data — `getMark()`, `location()`, `chainName()` — all return plain tables. They call `:get()` internally and return a snapshot. Consumers handle reactivity at a higher level:

- **Tree buffer**: View watches the graph, fires change events, triggers debounced re-render. Each render calls component functions for fresh snapshots.
- **Quickfix**: rebuilt wholesale when the user runs `:DapList`.
- **Telescope**: rebuilt on `picker:refresh()`.

No consumer needs per-component reactivity. neograph has no `computed()` primitive for derived signals, and no consumer would use one if it existed — they all re-render from snapshots.

---

## 1. Useful Entity Methods

### The Problem

UI surfaces re-derive entity state from raw signals. To display a breakpoint's visual state, `render.lua` reads five separate signals (`verified`, `enabledState`, `adjustedLine`, `requestedLine`, `condition`), applies conditional logic, and produces an icon. `format.lua` reads the same signals, applies similar but slightly different logic, and produces a text label. Every consumer independently re-interprets the same raw signals.

### The Principle

An entity knows its own semantics. "Is this breakpoint adjusted?" is a question the Breakpoint entity should answer — not something each consumer should re-derive from `adjustedLine ~= nil and adjustedLine ~= requestedLine`.

### What This Means

Entities expose methods that return semantically meaningful values. These methods do not return visual data (no icons, no highlights, no format strings). They return semantic values that any presentation layer can map to its own visual vocabulary.

**Session**
- `session:chainName()` — display name reflecting hierarchy (already exists)
- `session:isTerminated()` — (already exists)
- `session:displayState()` — semantic state: `"running"`, `"stopped"`, `"terminated"`, etc.

**Thread**
- `thread:displayState()` — semantic state: `"running"`, `"stopped"`, `"exited"`, etc.
- `thread:isStopped()` — predicate for common "is it stopped" check

**Frame**
- `frame:location()` — source location (already exists)
- `frame:isSubtle(hints)` — should this frame be visually de-emphasized?
- `frame:isSkippable(hints)` — should this frame be hidden from navigation?

**Breakpoint**
- `breakpoint:displayState()` — semantic state: `"verified"`, `"hit"`, `"adjusted"`, `"unverified"`, `"disabled"`
- `breakpoint:isAdjusted()` — adapter moved it from the requested line
- `breakpoint:isHit()` — currently stopped on this breakpoint

**Variable**
- `variable:displayValue()` — formatted value (truncated if necessary)
- `variable:displayType()` — type name if available
- `variable:hasChildren()` — can this variable be expanded?

**ExceptionFilterBinding**
- `binding:getEffectiveEnabled()` — (already exists)
- `binding:hasOverride()` — (already exists)
- `binding:canHaveCondition()` — (already exists)
- `binding:displayLabel()` — label from the underlying filter

### Relationship to Signals

These methods read signals internally. They don't replace signals — they complement them. A consumer that needs fine-grained reactivity still watches signals directly. A consumer that needs a point-in-time semantic snapshot calls these methods.

---

## 2. Composable Entity UI Components

### The Problem

Four independent formatting paths (`render.lua`, `format.lua`, `uri_picker.lua`, `telescope.lua`) each produce display output for the same entity types. They read the same entity properties but produce incompatible outputs in incompatible formats. There is no shared vocabulary for "how a Session looks."

### The Key Insight

A shared display layer should not produce finished output. It should produce **composable building blocks** that each consumer arranges for its own context.

A `format(entity)` function that returns a string is rigid — the consumer either takes it or leaves it. A set of components that each return a piece is flexible — the consumer selects what it needs and composes freely.

### Registration

Components are registered with two keys — a **component name** and an **entity type**:

```lua
debugger:register_component("icon", "Session", function(session)
  local state = session.state:get()
  if state == "stopped" then return { text = "⏸", hl = "DapStopped" } end
  if state == "running" then return { text = "▶", hl = "DapRunning" } end
  return { text = "⏹", hl = "DapTerminated" }
end)

debugger:register_component("title", "Session", function(session)
  return { text = session:chainName() or session.name:get() or "?" }
end)

debugger:register_component("title", "Frame", function(frame)
  return { text = frame.name:get() or "?" }
end)
```

The component name is a **cross-type concept**. `"title"` means the same thing for Session, Frame, Variable — the primary display label for an entity. `"icon"` means the same thing — a small visual state indicator. Each entity type provides its own implementation.

### What a Component Returns

A component function receives an entity and returns a display segment:

```lua
{ text = "⏸", hl = "DapPaused" }
```

Or `nil` if the component doesn't apply (e.g., a `condition` component for a breakpoint without a condition).

The return is a **plain table** — a snapshot of the entity's current display state. Not a signal. Components call `:get()` on entity signals internally, just like `getMark()` and `chainName()` do.

### Component Vocabulary

**Session**:

| Component | Example Output |
|---|---|
| `icon` | `{ text = "⏸", hl = "DapPaused" }` |
| `title` | `{ text = "Debug › child", hl = "DapSession" }` |
| `state` | `{ text = "stopped", hl = "DapStopped" }` |

**Thread**:

| Component | Example Output |
|---|---|
| `icon` | `{ text = "⏸", hl = "DapStopped" }` |
| `title` | `{ text = "MainThread", hl = "DapThread" }` |
| `state` | `{ text = "stopped", hl = "DapStopped" }` |
| `detail` | `{ text = "id=1", hl = "Comment" }` |

**Frame**:

| Component | Example Output |
|---|---|
| `index` | `{ text = "#0", hl = "DapFrameIndex" }` |
| `title` | `{ text = "main", hl = "DapFrame0" }` |
| `location` | `{ text = "app.py:42", hl = "DapSource" }` |

**Breakpoint**:

| Component | Example Output |
|---|---|
| `icon` | `{ text = "●", hl = "DapBreakpoint" }` (state-aware) |
| `title` | `{ text = "app.py:10", hl = "DapSource" }` |
| `state` | `{ text = "enabled", hl = "DapEnabled" }` |
| `condition` | `{ text = "if x > 5", hl = "DapCondition" }` or `nil` |

**Variable**:

| Component | Example Output |
|---|---|
| `title` | `{ text = "x", hl = "DapVarName" }` |
| `type` | `{ text = "int", hl = "DapVarType" }` or `nil` |
| `value` | `{ text = "42", hl = "DapVarValue" }` |

**ExceptionFilterBinding**:

| Component | Example Output |
|---|---|
| `icon` | `{ text = "◉", hl = "DapEnabled" }` (override-aware) |
| `title` | `{ text = "TypeError", hl = "DapFilter" }` |
| `condition` | `{ text = "if msg ~= ''", hl = "DapCondition" }` or `nil` |

### Consumption API

```lua
-- Single component by name, dispatched by entity type:
local icon = debugger:component("icon", entity)
-- → { text = "⏸", hl = "DapStopped" } or nil

-- All components for an entity:
local all = debugger:components(entity)
-- → { icon = { text = "⏸", ... }, title = { text = "Debug › child" }, state = { ... } }
```

### How Consumers Compose

Each UI surface selects components and arranges them. Given a Session entity:

- **Tree buffer**: `{ icon, " ", title, " ", state }` — rendered as rich `{text, hl}` segments, with tree guides, expand/collapse icons, and group labels added by the tree's own rendering layer.
- **Quickfix**: `title.text .. ": " .. state.text` — flattened to plain text, with location data added for quickfix navigation.
- **Telescope**: `"[" .. state.text .. "] " .. title.text` — with ordinal derived from `title.text`.
- **URI picker**: `title.text .. " (" .. state.text .. ")"` — a single string for `vim.ui.select`.

A community plugin might compose differently: `{ title, " — ", state, " — ", detail }`. It draws from the same building blocks without forking or duplicating any display logic.

### Layouts as Configuration

Because components are named and registered independently from surfaces, a UI plugin can accept **a list of component names per entity type** as configuration. This turns rendering into data — the user declares *which* components to show and in *what order*, and the surface handles arrangement.

```lua
-- Tree buffer with default layouts
debugger:use(require("neodap.plugins.tree_buffer"), {
  layouts = {
    Session  = { "icon", "title", "state" },
    Frame    = { "index", "title", "location" },
    Variable = { "title", "type", "value" },
  },
})

-- User customizes: drop type from variables, add detail to threads
debugger:use(require("neodap.plugins.tree_buffer"), {
  layouts = {
    Variable = { "title", "value" },
    Thread   = { "icon", "title", "state", "detail" },
  },
})
```

The surface iterates the layout, calls `debugger:component(name, entity)` for each entry, skips `nil` results (component doesn't apply to this entity), and renders the resulting segments using its own arrangement logic (tree guides and separators for tree buffer, column alignment for telescope, plain text concatenation for quickfix).

```lua
-- Inside a UI plugin's render loop
local layout = config.layouts[entity:type()] or default_layouts[entity:type()]
local segments = {}
for _, name in ipairs(layout) do
  local segment = debugger:component(name, entity)
  if segment then
    segments[#segments + 1] = segment
  end
end
-- surface-specific arrangement of segments
```

Each UI plugin provides sensible default layouts. Users override per entity type in their config. The same component registry serves all surfaces — only the layout and arrangement differ.

This means a telescope picker, a quickfix list, and a tree buffer can all accept the same shape of configuration:

```lua
-- Telescope frames picker: user wants index and title only
telescope.frames({ layout = { "index", "title" } })

-- Quickfix list: user wants icon and title
list_cmd({ layouts = { Breakpoint = { "icon", "title", "condition" } } })
```

The layout is the contract between user configuration and UI plugin rendering. Components are the contract between the layout and entity semantics.

### What Components Call

Components call entity methods (from enabler #1). The `icon` component for Breakpoint calls `breakpoint:displayState()` and maps the semantic state to a visual icon + highlight. Components are the bridge between entity semantics and visual representation.

### What Stays Surface-Specific

Components describe **entity display**. Each surface adds its own **structural concerns** around them:

- Tree buffer: tree guides, depth indicators, expand/collapse icons, group labels with entity counts
- Quickfix: location metadata (file, line, column) in the quickfix format
- Telescope: entry structure (ordinal, filename, lnum), display function wrapper
- URI picker: single string adaptation for `vim.ui.select`

---

## 3. Abstract Entity Actions

### The Problem

The same action recipe is implemented independently per UI surface. "Toggle an exception filter binding" requires calling `binding:toggle()`, then navigating to the session, then calling `session:syncExceptionFilters()`. This three-step recipe appears in `keybinds.lua`, `telescope.lua`, and `exception_cmd.lua`. If the sync step changes, three locations need updating.

Similarly, "focus frame and jump to source" is a two-step recipe (`ctx:focus()` + `navigate.goto_frame()`) that appears in `keybinds.lua`, `telescope.lua`, `focus_cmd.lua` + `jump_cmd.lua`, and `stack_nav.lua`.

### Registration

Actions use the same two-key pattern as components — an **action name** and an **entity type**:

```lua
debugger:register_action("toggle", "Breakpoint", function(breakpoint, ctx)
  breakpoint:toggle()
  breakpoint:sync()
end)

debugger:register_action("toggle", "ExceptionFilterBinding", function(binding, ctx)
  binding:toggle()
  local session = binding.session:get()
  if session then session:syncExceptionFilters() end
end)

debugger:register_action("focus_and_jump", "Frame", function(frame, ctx)
  ctx.debugger.ctx:focus(frame.uri:get())
  navigate.goto_frame(frame, ctx.opts)
end)
```

The action name is a **cross-type concept**. `"toggle"` means the same thing for Breakpoint and ExceptionFilterBinding — flip the enabled state and sync. Each entity type provides its own recipe.

### Invocation

```lua
-- Invoke by name, dispatched by entity type:
debugger:action("toggle", entity)

-- Query available actions for an entity:
debugger:actions_for(entity)
-- → { "toggle", "enable", "disable", "edit_condition", ... }
```

### Action Vocabulary

**Current duplicated recipes and their action names**:

| Action | Entity Types | Recipe |
|---|---|---|
| `toggle` | Breakpoint, BreakpointBinding, ExceptionFilterBinding, ExceptionFilter | Toggle entity state, sync with adapter if needed |
| `enable` | Breakpoint, ExceptionFilterBinding | Enable entity, sync |
| `disable` | Breakpoint, ExceptionFilterBinding | Disable entity, sync |
| `remove` | Breakpoint | Remove the breakpoint |
| `focus` | Frame, Session, Thread | Set debugger focus to this entity |
| `focus_and_jump` | Frame, Session | Set focus, navigate to source location |
| `edit_condition` | Breakpoint, BreakpointBinding, ExceptionFilterBinding | Prompt for input, update condition, sync |
| `edit_hit_condition` | Breakpoint, BreakpointBinding | Prompt for input, update hit condition |
| `edit_log_message` | Breakpoint, BreakpointBinding | Prompt for input, update log message |
| `clear_override` | BreakpointBinding, ExceptionFilterBinding | Revert to default, sync |
| `yank_value` | Variable | Copy value to register |
| `yank_name` | Variable | Copy name to register |

### How Surfaces Use Actions

Each surface maps its own input mechanism to action names:

- **Tree buffer**: key `t` → `debugger:action("toggle", entity)`
- **Telescope**: `<CR>` → `debugger:action("toggle", entity)` (exception filters picker)
- **Command**: `:DapEnable <url>` → `debugger:action("enable", entity)`
- **Quickfix**: bulk action → `debugger:action("toggle", entity)` from `user_data`

The mapping from input to action name is inherently surface-specific. The action handler is shared.

### Discoverability

`debugger:actions_for(entity)` returns available action names for an entity instance. This enables: dynamic context menus, keybind help generation, command completion. A surface doesn't need to hardcode which actions exist — it can discover them from the registry.

### What Stays Surface-Specific

- **Input mapping**: which key, gesture, or command triggers which action name
- **Surface lifecycle**: telescope's "stay open and refresh after action" vs tree buffer's "update in place" vs command's "fire and forget"
- **Surface-only actions**: tree buffer's scope refresh and variable edit buffer — actions that only make sense in the context of a specific UI surface

---

## How The Three Layers Compose

```
┌─────────────────────────────┐
│        UI Surfaces          │  Tree, Quickfix, Telescope, Picker, Commands
│  (compose + map inputs)     │
└──────────┬──────────────────┘
           │ compose                    │ invoke
           ▼                            ▼
┌──────────────────┐         ┌──────────────────────┐
│    Components    │         │   Abstract Actions   │
│  (visual blocks) │         │  (named recipes)     │
└──────────┬───────┘         └──────────┬───────────┘
           │ call                       │ call
           ▼                            ▼
┌─────────────────────────────────────────────────────┐
│                  Entity Methods                      │
│              (semantic derived state)                 │
└──────────────────────────────────────────────────────┘
```

Entity methods provide the semantic foundation. Components and actions are two independent consumers of that foundation, both using the same two-key `(name, entity_type)` registry on the debugger. UI surfaces sit on top, composing components for display and invoking actions for interaction.

### Example: Displaying a Session

1. **Entity method**: `session:displayState()` → `"stopped"`
2. **Component registration**: `debugger:register_component("icon", "Session", fn)` maps `"stopped"` → `{ text = "⏸", hl = "DapStopped" }`
3. **Consumption**: surface calls `debugger:component("icon", session)` → `{ text = "⏸", hl = "DapStopped" }`
4. **Tree buffer**: renders `⏸ Debug › child stopped` with tree guides and highlight groups
5. **Quickfix**: renders `Debug › child: stopped` as plain text
6. **Telescope**: renders `[stopped] Debug › child` with ordinal for fuzzy matching

Same registry, same components, different composition per surface.

### Example: Toggling an Exception Filter

1. **Surface input**: user presses `t` in tree buffer, or `<CR>` in telescope picker, or runs `:DapEnable`
2. **Action dispatch**: surface calls `debugger:action("toggle", entity)`
3. **Action handler**: calls `entity:toggle()`, resolves parent session, calls `session:syncExceptionFilters()`
4. **Reactive update**: entity state changes propagate through the reactive graph. View fires change events. Tree buffer debounces and re-renders, calling component functions for fresh snapshots.

Same action handler regardless of which surface triggered it.

---

## Impact Per Surface

| Surface | Before | After |
|---|---|---|
| **Tree buffer** | Owns renderers, keybinds, edges, preview routing | Composes shared components with tree-specific structure (guides, groups, depth). Maps keys to `debugger:action()`. Keeps tree-specific concerns: edge traversal, expand/collapse, group labels. |
| **Quickfix** | Owns `format.lua` dispatcher | Calls `debugger:components(entity)`, flattens to plain text. Invokes `debugger:action()` from bulk commands. |
| **URI picker** | Patches `:format()` onto entity classes | Calls `debugger:component("title", entity)`, composes into picker string. |
| **Telescope** | Owns inline `entry_maker`, `attach_mappings`, `define_preview` per picker | Calls `debugger:components(entity)` for entries. Maps picker input to `debugger:action()`. Can delegate preview to shared preview system. |
| **Commands** | Each `*_cmd.lua` owns its action logic | Resolve entity via URL, invoke `debugger:action()` by name. |

---

## What This Enables For The Community

With these three enablers in place, a community plugin author can:

- **Build new UI surfaces** (e.g., a floating window picker, a status line widget, a notification popup) by calling `debugger:components(entity)` — without duplicating any entity display logic. Accept a `layouts` config table for user-customizable rendering.
- **Add new actions** (e.g., `debugger:register_action("restart", "Session", fn)`) that are immediately available to all existing surfaces via `debugger:actions_for(entity)`.
- **Extend entity display** (e.g., `debugger:register_component("memory_address", "Variable", fn)`) — once registered, the new component can be added to any surface's layout by name. Users add `"memory_address"` to their tree buffer or telescope layout config and it works.
- **Create new entity types** (e.g., a custom adapter's proprietary entity) with components and actions that integrate naturally into existing UI surfaces through the same two-key registry.
- **Override defaults** — re-registering a `(name, entity_type)` pair replaces the previous handler, allowing full customization without forking.
- **Customize rendering without code** — users configure which components appear and in what order per entity type, per UI surface. No Lua formatting functions needed — just a list of component names in their config.

The shared layers provide a stable interface between entity semantics and UI rendering, allowing both sides to evolve independently.

---

## Testing Kit

Components and actions are testable against real debug sessions using the existing test harness. The testing kit extends the harness with methods for querying components and invoking actions, following the same patterns as `query_field`, `query_type`, and `wait_field`.

### Harness Methods

**Component queries** — resolve an entity by URL, call the component registry, return the result:

```lua
h:query_component(name, url)       -- → { text = "⏸", hl = "DapStopped" } or nil
h:query_components(url)            -- → { icon = { text, hl }, title = { text, hl }, ... }
h:query_component_text(name, url)  -- → "⏸" (shorthand for .text)
```

**Action invocation** — resolve an entity by URL, dispatch the named action:

```lua
h:run_action(name, url)            -- invoke action, return nil
h:query_actions_for(url)           -- → { "toggle", "enable", "disable", ... }
```

These follow the harness convention: URL-in, value-out. The harness resolves the entity in the child Neovim via `debugger:query(url)`, calls the component/action API, and returns the result.

### Testing a Component

A component test launches a real session, waits for the entity to reach a known state, then asserts on the component output:

```lua
T["Session icon reflects stopped state"] = function()
  local h = ctx.create()
  h:fixture("simple-vars")
  h:cmd("DapLaunch Debug stop")
  h:wait_field("@session", "state", "stopped")

  local icon = h:query_component("icon", "@session")
  MiniTest.expect.equality(icon.text, "⏸")
  MiniTest.expect.equality(icon.hl, "DapStopped")

  local title = h:query_component("title", "@session")
  MiniTest.expect.equality(title.text, "Debug")
end
```

Components that return `nil` when they don't apply:

```lua
T["Breakpoint condition component is nil when no condition set"] = function()
  local h = ctx.create()
  h:fixture("simple-vars")
  h:edit_main()
  h:cmd("DapBreakpoint 2")
  h:wait_url("/breakpoints(line=2)")

  MiniTest.expect.equality(h:query_component("condition", "/breakpoints(line=2)"), vim.NIL)
end
```

### Testing an Action

An action test asserts on the state change produced by the action:

```lua
T["toggle disables an enabled breakpoint"] = function()
  local h = ctx.create()
  h:fixture("simple-vars")
  h:edit_main()
  h:cmd("DapBreakpoint 2")
  h:wait_url("/breakpoints(line=2)")
  h:wait_field("/breakpoints(line=2)", "enabled", true)

  h:run_action("toggle", "/breakpoints(line=2)")
  h:wait_field("/breakpoints(line=2)", "enabled", false)
end

T["toggle re-enables a disabled breakpoint"] = function()
  local h = ctx.create()
  h:fixture("simple-vars")
  h:edit_main()
  h:cmd("DapBreakpoint 2")
  h:wait_url("/breakpoints(line=2)")

  h:run_action("toggle", "/breakpoints(line=2)")
  h:wait_field("/breakpoints(line=2)", "enabled", false)

  h:run_action("toggle", "/breakpoints(line=2)")
  h:wait_field("/breakpoints(line=2)", "enabled", true)
end
```

Actions with observable side effects beyond the entity itself:

```lua
T["focus_and_jump opens source file at frame location"] = function()
  local h = ctx.create()
  h:fixture("simple-vars")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("@frame")

  h:run_action("focus_and_jump", "@frame")

  -- Verify focus changed
  MiniTest.expect.equality(h:query_field("@frame", "name"), "module")

  -- Verify source file opened
  MiniTest.expect.equality(h:buffer_contains("x = 1"), true)
end
```

### Testing Across Session States

The existing multi-adapter integration framework (`harness.integration`) runs component and action tests against every enabled adapter automatically. A single test definition produces test cases for Python, JavaScript, and any future adapters:

```lua
local harness = require("helpers.test_harness")

return harness.integration("components", function(T, ctx)

  T["icon"] = MiniTest.new_set()

  T["icon"]["Session shows running state"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug")
    h:wait_field("@session", "state", "running")

    MiniTest.expect.equality(h:query_component_text("icon", "@session"), "▶")
  end

  T["icon"]["Session shows stopped state"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:cmd("DapLaunch Debug stop")
    h:wait_field("@session", "state", "stopped")

    MiniTest.expect.equality(h:query_component_text("icon", "@session"), "⏸")
  end

  T["icon"]["Breakpoint reflects verified state after launch"] = function()
    local h = ctx.create()
    h:fixture("simple-vars")
    h:edit_main()
    h:cmd("DapBreakpoint 2")
    h:cmd("DapLaunch Debug stop")
    h:wait_url("@frame")

    local icon = h:query_component("icon", "/breakpoints(line=2)")
    MiniTest.expect.equality(icon.hl, "DapBreakpointVerified")
  end

end)
```

This generates test paths like `T["python"]["components"]["icon"]["Session shows running state"]` and `T["javascript"]["components"]["icon"]["Session shows running state"]`, verifying that components produce correct output regardless of the underlying debug adapter.

### Testing Custom Components and Actions

A community plugin author tests their custom registrations using the same harness. Register the component or action in the child Neovim, then query/invoke it:

```lua
T["custom memory_address component"] = function()
  local h = ctx.create()
  h:fixture("simple-vars")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("@frame")

  -- Register custom component in the child
  h:get([[
    debugger:register_component("memory_address", "Variable", function(var)
      local ref = var.memoryReference:get()
      if not ref then return nil end
      return { text = ref, hl = "DapMemory" }
    end)
  ]])

  -- Query it through the standard harness method
  local comp = h:query_component("memory_address", "@frame/scopes[0]/variables[0]")
  -- Assert based on adapter behavior
end

T["custom restart action"] = function()
  local h = ctx.create()
  h:fixture("simple-vars")
  h:cmd("DapLaunch Debug stop")
  h:wait_url("@session")

  -- Register custom action in the child
  h:get([[
    debugger:register_action("restart", "Session", function(session, ctx)
      session:restart()
    end)
  ]])

  h:run_action("restart", "@session")
  -- Assert session restarted
  h:wait_field("@session", "state", "stopped")
end
```

### What The Kit Provides

The testing kit is not a separate framework — it is a small set of harness methods that expose the component/action registry through the same URL-based query interface the harness already uses for everything else. This means:

- **No new test patterns to learn** — `query_component` works like `query_field`, `run_action` works like `cmd`
- **Real sessions, real entities** — components and actions are tested against actual debug adapter state, not mocks
- **Multi-adapter coverage for free** — wrap tests in `harness.integration()` and they run against all adapters
- **Custom registration testable** — community authors use `h:get()` to register, standard harness methods to assert
