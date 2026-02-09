# Entity Presentation in neodap

## Overview

neodap presents debug entities (sessions, threads, frames, breakpoints, variables, etc.) through multiple UI surfaces. This document describes the current state of how entities are displayed and interacted with, and identifies where the architecture fragments across those surfaces.

## The Two Structures

All entity presentation in neodap reduces to two structures, both produced from URL resolution:

- **List**: A URL that resolves to multiple entities produces a flat sequence. Example: `@session/threads` yields a list of Thread entities.
- **Tree**: A URL that resolves to a single entity produces a root from which edges are traversed recursively. Example: `@session` yields a Session entity with threads, stacks, frames, scopes, variables as children.

Both structures ultimately present entities to the user. Both require the same fundamental operations: display an entity, act on an entity, preview an entity, navigate to an entity's source location.

## Current UI Surfaces

### Tree Buffer (`tree_buffer/`)

The primary deep-interaction surface. Renders a reactive tree of entities in a Neovim buffer.

- **Root resolution**: Opens via `dap://tree/<url>` (e.g., `dap://tree/@debugger`, `dap://tree/@session`). The URL resolves to a single entity used as tree root.
- **Edge traversal**: Defined in `tree_buffer/edges.lua` — a `by_type` dispatch table mapping entity types to their child edges, with eager/lazy loading flags and `on_expand` fetch callbacks.
- **Rendering**: Defined in `tree_buffer/render.lua` — a `renderers` dispatch table mapping entity types to display functions that produce segments of `{text, highlight}` pairs with tree guides.
- **Actions**: Defined in `tree_buffer/keybinds.lua` — a dispatch table mapping keys to entity-type-specific handlers. 30+ keybinds covering toggle, delete, edit condition, focus, jump to source, step, continue, terminate, yank, etc.
- **Preview**: `tree_preview.lua` watches the tree's cursor position and delegates to `preview_handler.lua`, which routes entity types to registered buffer schemes (`dap://source/`, `dap://var/`, etc.).

### Quickfix List (`list_cmd.lua`)

Flat entity listing via Neovim's quickfix window.

- **Resolution**: `:DapList <url>` calls `debugger:query(url)`, normalizes to an array.
- **Rendering**: Each entity passes through `quickfix.lua` → `format.lua`. The `format.entity()` dispatcher routes by entity type to produce a plain text string. Location-bearing entities (Frame, Breakpoint, Source) also provide file/line/column for quickfix navigation.
- **Actions**: Entities in quickfix can be acted on via `bulk_cmd.lua` (`:DapEnable`, `:DapDisable`, `:DapRemove`), which reads the entity URI from quickfix `user_data` and calls entity methods.

### URI Picker (`uri_picker.lua`)

Generic single-selection via `vim.ui.select`. Used when a URL resolves to multiple entities and a plugin needs exactly one.

- **Resolution**: `picker:resolve(url, callback)` calls `debugger:query(url)`. Single result → immediate callback. Multiple results → `vim.ui.select`.
- **Rendering**: Calls `:format()` instance methods patched onto entity classes directly inside `uri_picker.lua` (Session, Thread, Frame, Scope, Variable).
- **Actions**: None. The picker returns the selected entity to the caller, which decides what to do.

### Telescope Pickers (`telescope.lua`)

Rich pickers with preview, custom actions, and multi-select. External dependency (telescope.nvim).

- **Resolution**: Each picker calls `debugger:queryAll(url)` with a hardcoded URL per picker type.
- **Rendering**: Inline `entry_maker` functions per picker, each reading entity properties and formatting display strings independently.
- **Actions**: Inline `attach_mappings` per picker — focus+jump for sessions/frames, toggle+refresh for exception filters, condition editing via `vim.ui.input`.
- **Preview**: Inline `define_preview` per picker — session info as text, source file with highlight for frames.

### Commands (various `*_cmd.lua`)

CLI-style interaction via `:Dap <subcommand>`.

- `focus_cmd.lua`: `:DapFocus <url>` — resolves URL via URI picker, calls `debugger.ctx:focus()`.
- `jump_cmd.lua`: `:DapJump <url>` — resolves URL via URI picker, opens source file at frame location.
- `exception_cmd.lua`: `:DapException toggle <id>` — CLI for toggling, enabling, conditioning exception filters.
- `bulk_cmd.lua`: `:DapEnable <url>`, `:DapDisable <url>`, `:DapRemove <url>` — bulk entity operations.

## Entity Display

How entities become visible text. The same entity types are formatted independently in multiple locations.

### `format.lua` — Plain text dispatcher

Used by quickfix. Routes `entity:type()` to type-specific functions:

| Entity Type | Format | Example |
|---|---|---|
| Breakpoint | `[enabled] if: <cond> log: <msg>` | `[enabled] if: x > 5` |
| Frame | `#<index> <name>` | `#0 main` |
| Thread | `<name> (id=<id>): <state>` | `MainThread (id=1): stopped` |
| Session | `<name>: <state>` | `Debug: running` |
| Variable | `<name>: <type> = <value>` | `x: int = 42` |
| Scope | `Scope: <name>` | `Scope: Local` |
| Source | `<name>` or `<path>` | `main.py` |
| Other | `<Type>: <uri>` | `Stack: stack:abc:1:0` |

### `render.lua` — Rich tree rendering

Used by tree buffer. `renderers[entityType]` dispatch table producing `{text, highlight}` segment arrays. Features not present in `format.lua`:

- State icons (`⏸`, `▶`, `⏹`) with highlight groups for sessions and threads
- Breakpoint state icons (`●`, `○`, `◉`, `◆`, `◐`) reflecting verified/hit/adjusted/disabled
- Exception filter icons (`●`/`○`/`◉`/`◎`) reflecting enabled/disabled/overridden
- Frame depth-based coloring (`DapTreeFrame0`–`DapTreeFrame4`) and presentation hint awareness (`label`, `subtle`, `focused`)
- Source file coloring based on `Source.presentationHint` (`emphasize`, `normal`, `deemphasize`)
- Session hierarchy display (root >> leaf format)
- Variable type annotations with truncation
- Output category coloring (stderr/stdout/console)
- Group labels with entity counts (e.g., "Breakpoints (3)", "Threads", "Exception Filters (2/4)")
- Tree guide characters (╰, ├, │) with depth-aware rendering

### `uri_picker.lua` — Picker format methods

Patched directly onto entity classes as `:format()` instance methods. A third, independent formatting path:

| Entity Type | Format | Example |
|---|---|---|
| Session | `<root> › <name> (<state>)` | `Debug › child (stopped)` |
| Thread | `Thread <id>: <name> (<state>)` | `Thread 1: MainThread (stopped)` |
| Frame | `<name> @ <file>:<line>` | `main @ app.py:42` |
| Scope | `<name>` | `Local` |
| Variable | `<name> = <value>` | `x = 42` |

### `telescope.lua` — Inline entry makers

A fourth formatting path, defined inline in each picker:

- Sessions: `[<state>] <chainName>` — e.g., `[stopped] Debug > child`
- Frames: `<index>: <name> (<file>:<line>)` with dim highlights for subtle frames
- Exception filters: `<icon> <label> if <condition>` with override-aware icons

### Observations

Every UI surface re-derives display information from raw entity signals. The same entity properties (name, state, presentationHint, enabled, condition, etc.) are read and formatted independently in each location. There is no shared vocabulary for "how a Session should look" that all surfaces consume.

## Entity Actions

Operations available on entities. The same actions are implemented independently per UI surface.

### `keybinds.lua` — Tree buffer actions

Type-dispatched via `handler[entityType]`:

| Key | Entity Types | Action |
|---|---|---|
| `t` | Breakpoint, BreakpointBinding, ExceptionFilterBinding, ExceptionFilter | Toggle enabled state + sync |
| `dd` | Breakpoint | Remove breakpoint |
| `x` | BreakpointBinding, ExceptionFilterBinding | Clear override (revert to default) |
| `C` | Breakpoint, BreakpointBinding, ExceptionFilterBinding | Edit condition via `vim.ui.input` |
| `H` | Breakpoint, BreakpointBinding | Edit hit condition |
| `L` | Breakpoint, BreakpointBinding | Edit log message |
| `gd`/`gf` | Frame, Breakpoint | Jump to source location |
| `<Space>` | Frame, Session | Set focus |
| `e` | Variable | Open edit buffer |
| `c`/`p`/`n`/`s`/`S` | Thread | Continue/pause/step over/step in/step out |
| `X`/`D` | Session | Terminate/disconnect |
| `y`/`Y` | Variable | Yank value/name |
| `r` | Scope | Refresh variables |

### `bulk_cmd.lua` — Quickfix actions

Operates on entity from URL or current quickfix position:

| Command | Action |
|---|---|
| `:DapEnable <url>` | Enable entity |
| `:DapDisable <url>` | Disable entity |
| `:DapRemove <url>` | Remove entity |

### `telescope.lua` — Picker actions

Defined inline per picker in `attach_mappings`:

- **Sessions picker**: `<CR>` = focus session + jump to stopped frame
- **Frames picker**: `<CR>` = focus frame + jump to source
- **Exception filters picker**: `<CR>` = toggle + refresh (stays open), `c` = edit condition via `vim.ui.input`

### `exception_cmd.lua` — CLI actions

`:DapException` subcommands: `toggle`, `enable`, `disable`, `clear`, `condition`. Exposes a programmatic API (`api.toggle(id)`, `api.list()`, etc.).

### Observations

The toggle action for an ExceptionFilterBinding, for example, is implemented three times: in `keybinds.lua` (tree buffer `t` key), in `telescope.lua` (exception_filters picker `<CR>`), and in `exception_cmd.lua` (`:DapException toggle`). Each implementation reads the entity, calls `binding:toggle()`, navigates to the session, and calls `session:syncExceptionFilters()`. The entity methods are shared, but the "toggle this entity type and sync" recipe is repeated.

Similarly, "focus frame and jump to source" appears in: `keybinds.lua` (`<Space>` + `gd`), `telescope.lua` (frames/sessions picker `<CR>`), `focus_cmd.lua` + `jump_cmd.lua` (`:DapFocus` + `:DapJump`), and `stack_nav.lua` (`focus_and_jump` helper).

## Entity Preview

How an entity is previewed when selected but not yet acted on.

### `tree_preview.lua` + `preview_handler.lua`

The tree buffer sets `vim.b.focused_uri` on cursor movement. `tree_preview.lua` watches this and calls `preview_handler.refresh(bufnr, entity_uri)`. The preview handler:

1. Resolves the entity URI
2. Looks up a handler by entity type (`handlers[entityType]`)
3. Maps to a registered buffer scheme (e.g., Frame → `dap://source/`, Variable → `dap://var/`)
4. Delegates rendering to `entity_buffer.get_renderer(scheme)`
5. Falls back to a plain text summary if no renderer exists

### `telescope.lua`

Each picker defines its own `define_preview`:

- Sessions: Inline text showing name, state, ID, and thread list (queried via `debugger:queryAll(session.uri .. "/threads")`)
- Frames: Reads source file from disk, sets filetype for syntax highlighting, highlights current line
- Exception filters: No preview

### Observations

The tree preview system is generic and extensible (entity type → scheme → renderer). The telescope previews are self-contained and do not participate in this system. A Frame preview in the tree uses `dap://source/` with the full entity buffer machinery. A Frame preview in telescope reads the file and sets highlights manually.

## Edge Traversal

How child entities are discovered for tree rendering.

### `edges.lua`

A `by_type` dispatch table defines, for each entity type, which edges to traverse and how:

```
Debugger → sessionsGroups, targets, breakpointsGroups, exceptionFiltersGroups
Session  → children, threadGroups, stdios
Thread   → stacks (on_expand: fetchStackTrace)
Stack    → frames (on_expand: fetchFrames — no-op, frames come with stack)
Frame    → scopes (on_expand: fetchScopes)
Scope    → variables (eager unless Global; on_expand: fetchVariables)
Variable → children (recursive; on_expand: fetchChildren)
Breakpoint → bindings
ExceptionFilter → bindings
...
```

Each edge config specifies:
- `eager`: Whether children load immediately or on expand
- `on_expand`: Async callback to fetch data from the debug adapter
- `edges`: Nested edge definitions for deeper traversal
- `filters`: Property filters (e.g., `visible=true` for outputs)
- `sort`: Ordering (e.g., outputs by sequence number)
- `inline`: Whether the intermediate entity is hidden in the tree
- `recursive`: Whether the edge applies to its own children too

### Lists

Lists do not traverse edges. A URL query returns a flat result. There is no mechanism for a list item to reveal its children without switching to a tree view.

### Observations

Edge definitions are exclusively owned by the tree buffer. They encode both structural information (what are a Frame's children?) and behavioral information (how to fetch scopes from the adapter). No other UI surface has access to or reuses these definitions.

## Summary of the Current State

The five concerns of entity presentation — **display**, **actions**, **preview**, **edges**, and **location** — are each defined independently per UI surface:

|  | Tree Buffer | Quickfix | URI Picker | Telescope | Commands |
|---|---|---|---|---|---|
| **Display** | `render.lua` renderers | `format.lua` dispatcher | `:format()` methods on classes | inline `entry_maker` | — |
| **Actions** | `keybinds.lua` type dispatch | `bulk_cmd.lua` | — | inline `attach_mappings` | `*_cmd.lua` |
| **Preview** | `preview_handler.lua` → scheme routing | — | — | inline `define_preview` | — |
| **Edges** | `edges.lua` `by_type` | — | — | — | — |
| **Location** | `entity:location()` | `entity:location()` | — | `navigate.frame_location()` | `entity:location()` |

The entity methods themselves (`entity:toggle()`, `entity:location()`, `session:syncExceptionFilters()`, etc.) are shared. But the knowledge of *which* methods to call for *which* entity types, *how* to display the result, and *what interactions* are available — this knowledge is duplicated across every UI surface that presents entities.
