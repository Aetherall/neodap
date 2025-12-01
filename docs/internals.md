# Neodap Internals

This document explains the internal architecture of Neodap, focusing on the EntityStore, named edges, and how plugins can leverage these primitives to create custom reactive graph views.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [EntityStore](#entitystore)
  - [Entity Structure](#entity-structure)
  - [Adding Entities](#adding-entities)
  - [Querying Entities](#querying-entities)
- [Named Edges](#named-edges)
  - [Edge Structure](#edge-structure)
  - [Creating Edges](#creating-edges)
  - [Querying Edges](#querying-edges)
  - [Edge Events](#edge-events)
  - [Edge Types in Neodap](#edge-types-in-neodap)
- [Views and Collections](#views-and-collections)
  - [Type Views](#type-views)
  - [Filtered Views](#filtered-views)
  - [Indexes](#indexes)
- [Graph Traversal](#graph-traversal)
  - [BFS and DFS](#bfs-and-dfs)
  - [Traversal Context](#traversal-context)
- [TreeWindow](#treewindow)
  - [Virtual URIs](#virtual-uris)
  - [Configuration](#configuration)
- [Building Custom Plugins](#building-custom-plugins)
  - [Example: Custom Edge Type](#example-custom-edge-type)
  - [Example: tree_buffer Plugin](#example-tree_buffer-plugin)

---

## Architecture Overview

Neodap uses a **graph-based entity store** where:

1. **All entities** live in a single EntityStore (flat URI-indexed storage)
2. **All relationships** are expressed via named edges (not nested properties)
3. **Collections** are reactive query results, not stored data
4. **Plugins** can create custom edge types to build their own graph views

```
┌─────────────────────────────────────────────────────────────┐
│                      EntityStore                            │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐        │
│  │ Session │  │ Thread  │  │  Frame  │  │Variable │  ...   │
│  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘        │
│       │            │            │            │              │
│       └────────────┴────────────┴────────────┘              │
│                    Named Edges                              │
│         (parent, scope, variable, tree_parent, ...)         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Reactive Views                           │
│   store:view("thread")  →  Collection (all threads)         │
│   collection:where(...)  →  Collection (filtered)           │
│   store:bfs(...)         →  Collection (traversal result)   │
└─────────────────────────────────────────────────────────────┘
```

---

## EntityStore

The EntityStore is the central data structure that holds all debug entities.

### Entity Structure

Every entity must have:

```lua
local entity = {
  uri = "dap:session:abc123",    -- Required: unique identifier
  _type = "session",             -- Set automatically by store:add()
  key = "abc123",                -- Optional: human-readable key for display
  -- Additional properties...
}
```

**Common patterns:**

```lua
-- Reactive properties use Signals
entity.name = neostate.Signal("Thread-1")
entity.state = neostate.Signal("running")
entity.value = neostate.Signal("42")

-- Static properties are plain values
entity.id = 1
entity.line = 42
entity.source = { path = "/path/to/file.py" }
```

### Adding Entities

```lua
-- Add entity with type and optional initial edges
debugger.store:add(entity, "session", {
  { type = "parent", to = debugger.uri },
})

-- Add entity without edges (add edges separately)
debugger.store:add(thread, "thread", {})
debugger.store:add_edge(thread.uri, "parent", session.uri)
```

### Querying Entities

```lua
-- Get entity by URI
local entity = debugger.store:get("dap:session:abc123")

-- Check existence
if debugger.store:has(uri) then ... end

-- Get entity type
local entity_type = debugger.store:type_of(uri)  -- "session"

-- Remove entity (also removes all edges)
debugger.store:remove(uri)
```

---

## Named Edges

Edges are directed relationships between entities. Each edge has a **type** that describes the relationship.

### Edge Structure

```lua
-- Conceptually: from_uri --[type]--> to_uri
-- Example: thread.uri --[parent]--> session.uri
```

### Creating Edges

```lua
-- Append edge (adds to end of sibling list)
debugger.store:add_edge(from_uri, "parent", to_uri)

-- Prepend edge (adds to beginning - useful for newest-first ordering)
debugger.store:prepend_edge(from_uri, "parent", to_uri)

-- Remove edge
debugger.store:remove_edge(from_uri, "parent", to_uri)
```

**Ordering matters:** Use `prepend_edge` when you want newest items first (e.g., REPL messages, newest stack at top).

### Querying Edges

```lua
-- Get outgoing edges FROM an entity
local edges = debugger.store:edges_from(uri)              -- All types
local edges = debugger.store:edges_from(uri, "parent")    -- Specific type
-- Returns: { { type = "parent", to = "target_uri" }, ... }

-- Get incoming edges TO an entity
local edges = debugger.store:edges_to(uri)                -- All types
local edges = debugger.store:edges_to(uri, "parent")      -- Specific type
-- Returns: { { type = "parent", from = "source_uri" }, ... }

-- Get single parent via edge type
local parent_uri = debugger.store:get_parent(uri, "parent")

-- Get siblings (entities with same parent via same edge type)
local before = debugger.store:siblings_before(uri, "parent")
local after = debugger.store:siblings_after(uri, "parent")

-- Get path to root following edge type
local path = debugger.store:path_to_root(uri, "parent")
-- Returns: { uri, parent_uri, grandparent_uri, ..., root_uri }
```

### Edge Events

Subscribe to edge creation/removal for reactive behavior:

```lua
-- React to new edges
local unsub = debugger.store:on_edge_added("parent", function(from_uri, to_uri)
  print("New parent edge:", from_uri, "->", to_uri)
end)

-- React to edge removal
local unsub = debugger.store:on_edge_removed("parent", function(from_uri, to_uri)
  print("Removed parent edge:", from_uri, "->", to_uri)
end)

-- React to entity additions by type
local unsub = debugger.store:on_added("thread", function(entity)
  print("New thread:", entity.uri)
end)

-- React to entity removals by type
local unsub = debugger.store:on_removed("thread", function(entity)
  print("Thread removed:", entity.uri)
end)
```

### Edge Types in Neodap

The SDK uses these edge types for the debug entity graph:

| Edge Type | From → To | Description |
|-----------|-----------|-------------|
| `parent` | child → parent | Hierarchy: thread→session, stack→thread, frame→stack, output→session |
| `scope` | scope → frame | Frame's scopes |
| `variable` | variable → parent | Variable hierarchy (to scope or parent variable) |
| `threads` | session → thread | Session's threads |
| `frames` | stack → frame | Stack's frames |
| `children` | parent → child | Session parent-child, debugger→session |
| `binding` | binding → session/breakpoint | Breakpoint binding (edges to both) |
| `source_binding` | binding → session/source | Source registration (edges to both) |
| `exception_filter_binding` | binding → session/filter | Exception filter binding (edges to both) |

**Plugin-defined edges:**

| Edge Type | Plugin | Description |
|-----------|--------|-------------|
| `tree_parent` | tree_buffer | Virtual tree hierarchy for visualization |

---

## Views and Collections

Collections are **reactive query results**, not stored data. They automatically update when the underlying data changes.

### Type Views

Get all entities of a type:

```lua
-- Create a view of all sessions
local sessions = debugger.store:view("session")

-- Iterate over current sessions
for session in sessions:iter() do
  print(session.name:get())
end

-- React to additions (existing + future)
sessions:each(function(session)
  print("Session:", session.uri)
end)

-- React to future additions only
sessions:subscribe(function(session)
  print("New session:", session.uri)
end)
```

### Filtered Views

Filter collections by indexed properties:

```lua
-- Get threads for a specific session
local threads = debugger.threads:where("by_session_id", session.id)

-- Get frames for a specific session
local frames = debugger.frames:where("by_session_id", session.id)

-- Chain filters aren't directly supported - use traversal instead
```

### Indexes

Indexes enable fast lookups. Define them when adding entities:

```lua
-- In entity_store.lua, indexes are defined per type
-- Example: threads indexed by session_id
debugger.store:define_index("thread", "by_session_id", function(thread)
  return thread.session_id
end)

-- Now you can query: debugger.threads:where("by_session_id", session.id)
```

---

## Graph Traversal

The EntityStore provides reactive graph traversal via BFS and DFS.

### BFS and DFS

```lua
-- Breadth-first traversal from root
local reachable = debugger.store:bfs(root_uri, {
  direction = "in",                 -- "in", "out", or "both"
  edge_types = { "tree_parent" },   -- Which edges to follow
  max_depth = 10,                   -- Maximum depth (optional)

  -- Filter: controls visibility (children still traversed)
  filter = function(entity, ctx)
    return entity.name ~= "hidden"
  end,

  -- Prune: stops traversal at this node AND its subtree
  prune = function(entity, ctx)
    return ctx.depth > 5
  end,
})

-- Depth-first traversal
local collection = debugger.store:dfs(root_uri, opts)

-- Iterate results
for item in reachable:iter() do
  print(item.uri, item._virtual.depth)
end
```

### Traversal Context

Filter and prune functions receive rich context:

```lua
local ctx = {
  depth = 2,                           -- Distance from start
  path = { uri1, uri2 },               -- Ancestor URIs
  pathkeys = { "key1", "key2" },       -- Ancestor keys
  parent = parent_uri,                 -- Immediate parent URI
  uri = "key1/key2/current",           -- Virtual URI (path-based)
}
```

---

## TreeWindow

TreeWindow provides a reactive, windowed view of a tree with O(window + depth) performance.

### Virtual URIs

TreeWindow tracks items with **virtual URIs** - composite paths that allow the same entity to appear multiple times in different locations:

```lua
-- Entity URI: "dap:variable:xyz" (globally unique)
-- Virtual URI: "session-1/~threads/Thread-1/Stack-0/Frame-0/Locals/myVar"
--              (path-specific, allows same entity in multiple trees)

item._virtual = {
  uri = "session-1/Locals/myVar",      -- Virtual URI
  entity_uri = "dap:variable:xyz",     -- Actual entity URI
  depth = 3,                           -- Tree depth
  path = { session_uri, scope_uri },   -- Path of entity URIs
  pathkeys = { "session-1", "Locals" }, -- Path of keys
  parent_vuri = "session-1/Locals",    -- Parent's virtual URI
}
```

### Configuration

```lua
local window = TreeWindow:new(store, root_uri, {
  edge_types = { "tree_parent" },   -- Edges to follow
  direction = "in",                 -- "in" = incoming edges (children → parent)
  above = 50,                       -- Viewport items above focus
  below = 50,                       -- Viewport items below focus
  default_collapsed = true,         -- Start collapsed

  -- Called when node is expanded
  on_expand = function(entity, vuri, entity_uri)
    if entity.children then
      entity:children()  -- Trigger lazy loading
    end
  end,

  -- Called when node is collapsed
  on_collapse = function(entity, vuri, entity_uri)
    -- Optional cleanup
  end,
})

-- Navigation
window:focus_on(vuri)           -- Focus by virtual URI
window:focus_entity(entity_uri) -- Focus by entity URI (computes path)
window:move_down()
window:move_up()
window:move_into()              -- Move to first child
window:move_out()               -- Move to parent

-- Collapse/Expand
window:toggle(vuri)
window:expand(vuri)
window:collapse(vuri)

-- Events
window:on_rebuild(function()
  -- Tree structure changed
end)
```

---

## Building Custom Plugins

Plugins can create custom edge types to build specialized views of the entity graph.

### Example: Custom Edge Type

Create a "favorites" edge type to track user-selected entities:

```lua
return function(debugger, config)
  local favorites = {}

  -- Add to favorites
  local function add_favorite(entity)
    if not favorites[entity.uri] then
      favorites[entity.uri] = true
      -- Create edge from entity to a virtual "favorites" root
      debugger.store:add_edge(entity.uri, "favorite", "favorites:root")
    end
  end

  -- Query favorites via traversal
  local function get_favorites()
    return debugger.store:bfs("favorites:root", {
      direction = "in",
      edge_types = { "favorite" },
    })
  end

  -- Command to toggle favorite
  vim.api.nvim_create_user_command("DapFavorite", function()
    local ctx = debugger:context()
    local frame = ctx.frame:get()
    if frame then
      add_favorite(frame)
    end
  end, {})

  return function()
    -- Cleanup
  end
end
```

### Example: tree_buffer Plugin

The `tree_buffer` plugin demonstrates the full pattern:

1. **Mirror existing edges** to a custom `tree_parent` edge type
2. **Create virtual group entities** for organization
3. **Use TreeWindow** to render the custom graph

```lua
return function(debugger, config)
  -- 1. Mirror "parent" edges as "tree_parent"
  debugger.store:on_edge_added("parent", function(from_uri, to_uri)
    local entity = debugger.store:get(from_uri)
    if entity._type == "stack" then
      -- Prepend so newest stack appears first
      debugger.store:prepend_edge(from_uri, "tree_parent", to_uri)
    else
      debugger.store:add_edge(from_uri, "tree_parent", to_uri)
    end
  end)

  -- Mirror "scope" and "variable" edges
  debugger.store:on_edge_added("scope", function(from_uri, to_uri)
    debugger.store:add_edge(from_uri, "tree_parent", to_uri)
  end)

  debugger.store:on_edge_added("variable", function(from_uri, to_uri)
    debugger.store:add_edge(from_uri, "tree_parent", to_uri)
  end)

  -- 2. Create virtual groups when sessions are added
  debugger.store:on_added("session", function(session)
    -- Groups are created lazily when first child arrives
    local groups = {}

    debugger.store:on_added("thread", function(thread)
      -- Check if thread belongs to this session
      if thread.session_id ~= session.id then return end

      -- Create ~threads group on first thread
      if not groups["~threads"] then
        local group = {
          uri = session.uri .. "/~threads",
          key = "~threads",
          name = "Threads",
          _type = "group",
          count = neostate.Signal(0),
        }
        debugger.store:add(group, "group", {})
        debugger.store:add_edge(group.uri, "tree_parent", session.uri)
        groups["~threads"] = group
      end

      -- Add thread to group via tree_parent
      debugger.store:add_edge(thread.uri, "tree_parent", groups["~threads"].uri)
      groups["~threads"].count:set(groups["~threads"].count:get() + 1)
    end)
  end)

  -- 3. Handle dap-tree: buffer URIs
  vim.api.nvim_create_autocmd("BufReadCmd", {
    pattern = "dap-tree:*",
    callback = function(opts)
      local bufnr = opts.buf
      local uri = opts.file

      -- Parse URI to get root entity
      local root_uri = parse_tree_uri(uri)

      -- Create TreeWindow following tree_parent edges
      local window = TreeWindow:new(debugger.store, root_uri, {
        edge_types = { "tree_parent" },
        direction = "in",
        on_expand = function(entity)
          if entity.children then entity:children() end
        end,
      })

      -- Render and set up keymaps...
    end,
  })
end
```

### Key Design Patterns

1. **Edge Mirroring**: Create custom edges that mirror existing relationships with different ordering or filtering

2. **Virtual Entities**: Create group/container entities that don't exist in the DAP model but help organize the UI

3. **Lazy Creation**: Create groups only when first child arrives (not eagerly)

4. **Prepend for Ordering**: Use `prepend_edge` for newest-first display (stacks, REPL messages)

5. **Event-Driven Updates**: Subscribe to edge/entity events to maintain custom edge graph

6. **TreeWindow for Rendering**: Use TreeWindow to efficiently render large trees with virtual URIs

---

## Summary

| Component | Purpose |
|-----------|---------|
| **EntityStore** | Central storage for all entities |
| **Named Edges** | Relationships between entities |
| **Views/Collections** | Reactive query results |
| **TreeWindow** | Windowed tree rendering |
| **Custom Edges** | Plugin-defined relationships |

The power of this architecture is that plugins can create entirely new views of the data by:
1. Defining custom edge types
2. Subscribing to entity/edge events
3. Building derived graphs
4. Using TreeWindow to render them

This allows the `dap-tree:` buffer to show a different structure than the raw DAP model, with virtual groups, custom ordering, and lazy-loaded children.
