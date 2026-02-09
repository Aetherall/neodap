# WIP: Entity Presentation Initiative

This document tracks the entity presentation initiative for neodap. It provides enough context to resume work from any point.

## Goal

Reduce duplication across UI surfaces (tree buffer, quickfix, telescope, uri_picker, commands) by introducing three shared layers: entity methods, composable components, and abstract actions. This makes entity presentation consistent, configurable, and extensible by the community.

## Reference Documents

Read these in order to understand the full picture:

1. **[docs/entity-presentation.md](./entity-presentation.md)** — Problem statement. Exhaustive description of the current fragmentation: five presentation concerns (display, actions, preview, edges, location) implemented independently across five UI surfaces. Read this first.

2. **[docs/entity-presentation-design.md](./entity-presentation-design.md)** — Solution design. Describes the three enablers, the two-key registry tactic, why components return plain tables, layouts as configuration, the testing kit, and community extensibility. Read this second.

## Key Design Decisions (already made)

These decisions are documented in `entity-presentation-design.md` but summarized here for quick reference:

- **Three enablers**: (1) Useful Entity Methods — semantic derived state on entity classes. (2) Composable Entity UI Components — `{ text, hl }` building blocks registered per `(name, entity_type)`. (3) Abstract Entity Actions — named recipes registered per `(name, entity_type)`.

- **Two-key registry on debugger**: `debugger:register_component(name, entity_type, fn)` and `debugger:register_action(name, entity_type, fn)`. Both use double-dispatch: concept name × entity type. Lives on the debugger instance alongside `query()` and `queryAll()`.

- **Components return plain tables**: `{ text = string, hl? = string }` or `nil`. Not signals. Components call `:get()` on signals internally and return snapshots. Consumers handle reactivity at a higher level (View change events for tree buffer, wholesale rebuild for quickfix/telescope). Follows the `getMark()` / `chainName()` pattern.

- **Layouts as configuration**: UI plugins accept a list of component names per entity type. `{ Session = { "icon", "title", "state" } }`. The surface iterates the list, calls `debugger:component(name, entity)` for each, skips nils, and renders with its own arrangement logic.

- **Testing kit**: Harness methods `query_component(name, url)`, `query_components(url)`, `run_action(name, url)`, `query_actions_for(url)`. Same URL-in value-out convention as existing `query_field` / `wait_field`. Tests use real debug sessions via `harness.integration()`.

## Architecture Quick Reference

```
┌─────────────────────────────┐
│        UI Surfaces          │  Tree, Quickfix, Telescope, Picker, Commands
│  (compose layouts +         │
│   map inputs to actions)    │
└──────────┬──────────────────┘
           │ compose                    │ invoke
           ▼                            ▼
┌──────────────────┐         ┌──────────────────────┐
│    Components    │         │   Abstract Actions   │
│  (name, type) →  │         │  (name, type) →      │
│  { text, hl }    │         │  handler(entity,ctx)  │
└──────────┬───────┘         └──────────┬───────────┘
           │ call                       │ call
           ▼                            ▼
┌─────────────────────────────────────────────────────┐
│                  Entity Methods                      │
│         displayState(), chainName(), location()      │
└──────────────────────────────────────────────────────┘
```

## What's Done

### stack_nav.lua — enhanced with frame-skip + auto-jump
- **File**: `lua/neodap/plugins/stack_nav.lua`
- Config: `skip_hints` (default `{ label = true }`), `auto_jump` (default `true`), `pick_window`, `create_window`
- Uses URL-based resolution: `debugger:query("@frame+" .. n)` for up/down, `debugger:queryAll("@thread/stack/frames")` for top
- Commands: `DapUp`, `DapDown`, `DapTop`
- Already registered in `boost.lua`

### telescope.lua — new picker plugin
- **File**: `lua/neodap/plugins/telescope.lua`
- Three pickers: `api.sessions()`, `api.frames()`, `api.exception_filters()`
- Command: `DapPick sessions|frames|exception_filters`
- NOT in `boost.lua` (external dependency — user registers explicitly)
- Uses URL-based resolution throughout

### Entity methods (enabler #1) — DONE
- **Commit**: `16b87fa`
- All semantic display methods added to entity classes: `displayState()`, `chainName()`, `isSubtle()`, `isSkippable()`, `displayValue()`, `displayType()`, `hasChildren()`, `isHit()`, `isAdjusted()`, `displayLabel()`, etc.

### Component/action registry (enabler #2) — DONE
- **Files**: `lua/neodap/presentation/init.lua`, `lua/neodap/presentation/components.lua`, `lua/neodap/presentation/actions.lua`
- Two-key `(name, entity_type)` registry on debugger instance
- API: `register_component`, `component`, `components`, `register_action`, `action`, `actions_for`
- Default components registered for: Session, Thread, Frame, Breakpoint, Variable, Scope, Source, ExceptionFilterBinding, ExceptionFilter
- Default actions registered: toggle, enable, disable, remove, focus, focus_and_jump, edit_condition, edit_hit_condition, edit_log_message, clear_override, yank_value, yank_name

### Testing kit — DONE
- **Files**: `tests/helpers/test_harness.lua`, `tests/neodap/presentation/components.lua`, `tests/neodap/presentation/actions.lua`
- 5 harness methods: `query_component`, `query_components`, `query_component_text`, `run_action`, `query_actions_for`
- 57 integration tests per adapter (114 total across both adapters):
  - **Component tests** (54): exhaustive coverage of all entity states — Session (stopped/terminated icon+state), Thread (stopped icon+state+detail), Frame (index/title/location), Breakpoint (all 4 icon+state branches: unverified/disabled/verified/hit, title, condition nil/condition/logMessage), Variable (title/value/type), Scope (title), Source (title), ExceptionFilter (icon+toggle, title), ExceptionFilterBinding (icon cycling all 4 override×enabled branches, title, condition nil/set), query_component_text shorthand, actions_for per entity type
  - **Action tests** (10): toggle (disable+re-enable), enable/disable, enable no-op, remove, focus, edit_condition/edit_hit_condition/edit_log_message via `type_keys` driving `vim.ui.input`
- All tests use real entities through user commands and presentation actions — no manual state manipulation

## What's Not Done

### ~~1. Entity methods (enabler #1)~~
~~Add semantic derived-state methods to entity classes via the existing method injection pattern in `lua/neodap/entities/*.lua`.~~

Key methods to add:
- `Session:displayState()` → `"running"` / `"stopped"` / `"terminated"`
- `Thread:displayState()`, `Thread:isStopped()`
- `Frame:isSubtle(hints)`, `Frame:isSkippable(hints)`
- `Breakpoint:displayState()` → `"verified"` / `"hit"` / `"adjusted"` / `"unverified"` / `"disabled"`
- `Breakpoint:isAdjusted()`, `Breakpoint:isHit()`
- `Variable:displayValue()`, `Variable:displayType()`, `Variable:hasChildren()`
- `ExceptionFilterBinding:displayLabel()`

Some already exist: `session:chainName()`, `session:isTerminated()`, `binding:getEffectiveEnabled()`, `binding:hasOverride()`, `binding:canHaveCondition()`, `frame:location()`.

Look at `render.lua` and `format.lua` for the signal-reading logic that should move into these methods.

### ~~2. Component/action registry (core infrastructure)~~ DONE

### ~~3. Default component registrations~~ DONE

### ~~4. Default action registrations~~ DONE

Component vocabulary per type is documented in `entity-presentation-design.md` § Component Vocabulary.

### 4. Default action registrations
A plugin (or part of core setup) that registers the default actions. This is where the duplicated recipes from `keybinds.lua`, `telescope.lua`, `*_cmd.lua` get consolidated.

Action vocabulary is documented in `entity-presentation-design.md` § Action Vocabulary.

### ~~5. Migrate UI surfaces to use registry~~ DONE
~~Rewrite each surface to consume the registry instead of its own dispatch tables:~~
- ~~`format.lua` / `quickfix.lua` → layout-based component composition via `debugger:component()`~~
- ~~`list_cmd.lua` / `command_router.lua` → thread debugger through to quickfix/format~~
- ~~`uri_picker.lua` → removed class prototype patches, uses `debugger:component()` in format_item~~
- ~~`telescope.lua` → components for display, `debugger:action()` for handlers, `format.entity()` for exception filters~~
- ~~`keybinds.lua` → 9 handlers replaced with `debugger:action()` calls (toggle, remove, clear_override, edit_condition, edit_hit_condition, edit_log_message, yank_value, yank_name, focus)~~
- ~~`tree_buffer/render.lua` → layout-driven entity renderers with component registry integration (completed in layout step)~~

### ~~6. Layout configuration~~ DONE
~~Add `layouts` config support to UI plugins so users can configure which components appear per entity type.~~
- ~~`format.lua` → exported `M.LAYOUTS` for consumer reference~~
- ~~`quickfix.lua` → optional `layout` parameter passed through to `format.entity()`~~
- ~~`list_cmd.lua` → accepts `layouts` in config, derives per-entity layout~~
- ~~`command_router.lua` → accepts `layouts` in config, derives per-entity layout~~
- ~~`tree_buffer/config.lua` → `layouts = {}` in default config~~
- ~~`tree_buffer.lua` → threads `debugger` and `config.layouts` to `render_item`~~
- ~~`tree_buffer/render.lua` → `TREE_LAYOUTS` defaults, `make_set` helper, layout-aware entity renderers with component registry, generic component slot for community extensions~~

### ~~7. Testing kit~~ DONE
~~Add harness methods to `tests/helpers/test_harness.lua`:~~
~~- `query_component(name, url)`~~
~~- `query_components(url)`~~
~~- `query_component_text(name, url)`~~
~~- `run_action(name, url)`~~
~~- `query_actions_for(url)`~~

~~Write tests for default components and actions using `harness.integration()`.~~

### 8. Tests for stack_nav and telescope
These plugins were implemented but have no test coverage yet.

## Suggested Implementation Order

1. ~~**Entity methods** — pure additions to entity classes, no breaking changes, immediately useful~~ DONE
2. ~~**Registry infrastructure** — core API on debugger, no consumers yet~~ DONE
3. ~~**Default registrations** — populate the registry with components and actions extracted from existing code~~ DONE
4. ~~**Testing kit + tests** — harness methods, then tests for default components/actions~~ DONE
5. ~~**Migrate surfaces** — format/quickfix, uri_picker, telescope, keybinds, tree_buffer/render.lua~~ DONE
6. ~~**Layout configuration** — layouts config for all surfaces, tree_buffer render.lua migration~~ DONE
7. **stack_nav/telescope tests** — can happen at any point

## Key Files to Understand

| File | Role |
|---|---|
| `lua/neodap/init.lua` | `debugger:use(plugin, config)`, plugin lazy loading |
| `lua/neodap/identity/init.lua` | `debugger:query()`, `debugger:queryAll()` — pattern for adding core methods |
| `lua/neodap/entity.lua` | `entity.class()`, method injection pattern |
| `lua/neodap/entities/*.lua` | Entity method definitions (session, frame, breakpoint, etc.) |
| `lua/neodap/schema.lua` | Declarative entity schema — edges, indexes, rollups |
| `lua/neodap/plugins/tree_buffer/render.lua` | Current rich rendering — dispatch table to extract from |
| `lua/neodap/plugins/tree_buffer/keybinds.lua` | Tree keybinds — 9 handlers now delegate to `debugger:action()` |
| `lua/neodap/plugins/utils/format.lua` | Layout-based component composition — `format.entity(debugger, entity, layout?)` |
| `lua/neodap/plugins/utils/quickfix.lua` | Quickfix entry builder — delegates to format.entity |
| `lua/neodap/plugins/uri_picker.lua` | URI picker — uses `debugger:component()` for format_item |
| `lua/neodap/plugins/telescope.lua` | Telescope pickers — components for display, actions for handlers |
| `lua/neodap/plugins/preview_handler.lua` | Preview routing — pattern for registry with handlers |
| `lua/neodap/boost.lua` | Batteries-included setup — where default registrations would be wired |
| `tests/helpers/test_harness.lua` | Test harness — where testing kit methods go |
