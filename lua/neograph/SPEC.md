# neograph-native Specification

## Overview

neograph-native is a reactive in-memory graph database for Lua. It provides:

- Signal-based reactive properties
- EdgeHandle for edge operations
- **Materialized rollups** - property, reference, and collection rollups that auto-update
- Index-based filtering with covering index optimization
- Views with pagination, expansion state, and callbacks

### Materialized Rollups

All rollups are **materialized**, meaning they are stored and automatically kept in sync:

- **Property rollups** are stored as actual node properties, enabling use in indexes and view filters
- **Reference rollups** are virtual single-target edges, traversable in views
- **Collection rollups** are virtual filtered edges, traversable in views

Rollups update automatically when edges are linked/unlinked or when target properties change.

## Graph Creation

```lua
local neo = require("init")
local graph = neo.create(schema)
```

Creates a graph instance with the given schema.

## Graph Structure

A graph contains **nodes** and **edges**.

- **Node**: Has a unique numeric `id`, a `type` (string), and user-defined properties
- **Edge**: Directed link from source node to target node, identified by `(source_id, edge_name, target_id)`

Nodes have two reserved properties set automatically:
- `_id`: The node's unique id (read-only)
- `_type`: The node's type name (read-only)

### Node IDs

IDs are positive integers assigned sequentially starting from 1.

### Property Values

Supported types: `nil`, `boolean`, `number`, `string`.

Comparison rules:
- `nil` sorts after all non-nil values (ascending), before all (descending)
- Booleans: `false < true`
- Numbers and strings: standard comparison

## Schema

A schema defines types. Each type has:

- `name`: Type identifier
- `properties`: List of `{ name, type }` (type: "string", "number", "bool")
- `indexes`: List of `{ name, fields: [{ name, dir: "asc"|"desc" }] }`
- `edges`: List of edge definitions
- `rollups`: Optional list of rollup definitions

### Edge Definition

```lua
{
  name = "posts",
  target = "Post",
  reverse = "author",  -- optional
  indexes = {
    { name = "default", fields = {} },
    { name = "by_views", fields = {{ name = "views", dir = "desc" }} },
  }
}
```

### Rollup Definitions

Three kinds of rollups:

**Property Rollup** - Computes a scalar value from edge targets:
```lua
{ kind = "property", name = "post_count", edge = "posts", compute = "count" }
{ kind = "property", name = "total_views", edge = "posts", compute = "sum", property = "views" }
{ kind = "property", name = "published_count", edge = "posts", compute = "count",
  filters = {{ field = "published", value = true }} }
```

Compute operations: `count`, `sum`, `avg`, `min`, `max`, `first`, `last`, `any`, `all`

**Reference Rollup** - Returns a single node reference:
```lua
{ kind = "reference", name = "latest_post", edge = "posts",
  sort = { field = "created_at", dir = "desc" } }
{ kind = "reference", name = "top_published", edge = "posts",
  filters = {{ field = "published", value = true }},
  sort = { field = "views", dir = "desc" } }
```

**Collection Rollup** - Returns a filtered/sorted edge view:
```lua
{ kind = "collection", name = "published_posts", edge = "posts",
  filters = {{ field = "published", value = true }} }
{ kind = "collection", name = "posts_by_views", edge = "posts",
  sort = { field = "views", dir = "desc" } }
```

## Node Proxy API

Nodes returned by `insert` or `get` are proxies with reactive access:

```lua
local user = graph:insert("User", { name = "Alice", age = 30 })

-- Properties return Signal
user.name:get()           -- "Alice"
user.name:set("Bob")      -- Update property (reactive)
user.name:use(function(val, old_val)
  print("Name changed from", old_val, "to", val)
  return function() print("Cleanup") end  -- optional cleanup
end)

-- Edges return EdgeHandle
user.posts:iter()         -- Iterator over linked posts
user.posts:link(post)     -- Link a post
user.posts:unlink(post)   -- Unlink a post
user.posts:count()        -- Count of linked posts

-- Property rollups: Signal-like (materialized as node properties)
user.post_count:get()       -- Returns number
user.post_count:use(fn)     -- React to changes

-- Reference rollups: Signal-like (returns node or nil)
local post = user.latest_post:get()  -- node proxy or nil
user.latest_post:use(fn)             -- React to reference changes

-- Collection rollups: EdgeHandle-like (virtual filtered edge)
for post in user.published_posts:iter() do ... end
user.published_posts:count()
user.published_posts:each(fn)
```

### Direct Property Assignment

Direct assignment (`node.prop = value`) is **not reactive**. It bypasses the Signal system and shadows future Signal access for that property:

```lua
user.name = "Charlie"     -- NOT reactive, shadows Signal
user.name:get()           -- ERROR: calling :get() on string

-- Always use Signal:set() for reactive updates:
user.name:set("Charlie")  -- Reactive, triggers watchers
```

## Metatable Preservation

When inserting a node with a user-defined metatable, the metatable is preserved and user methods remain accessible:

```lua
-- Define a class with methods
local Session = {}
Session.__index = Session

function Session:start()
  self.status:set("running")
  return self
end

function Session:stop()
  self.status:set("stopped")
  return self
end

function Session:isRunning()
  return self.status:get() == "running"
end

-- Insert with metatable
local session = graph:insert("Session", setmetatable({
  name = "debug-session",
  status = "idle",
}, Session))

-- User methods work
session:start()
session:stop()
print(session:isRunning())  -- false

-- Property access still works via Signal
session.name:get()          -- "debug-session"
session.status:set("running")

-- Retrieved nodes preserve metatable
local s = graph:get(session._id)
s:start()  -- works - same object with same metatable
```

### How It Works

1. **On insert**: The user's metatable `__index` is captured before the node is set up
2. **Combined metatable**: A new metatable is created that:
   - First checks user's `__index` for methods
   - Then checks for virtual edges (reference/collection rollups)
   - Then checks for regular edges (returns EdgeHandle)
   - Finally returns a Signal for property access
3. **Same object**: `graph:get(id)` returns the exact same object that was stored
4. **Graph-level caching**: EdgeHandles and Signals are cached by `(node_id, key)` for consistent identity

### Reserved Keys

These keys are handled specially and cannot be overridden by user metatables:

| Key | Returns |
|-----|---------|
| `_id` | Node's unique numeric ID |
| `_type` | Node's type name string |
| `_graph` | Reference to the graph instance |

## Signal

Reactive wrapper for property access.

| Method | Description |
|--------|-------------|
| `signal:get()` | Get current value |
| `signal:set(value)` | Set new value, triggers reactivity |
| `signal:use(effect)` | Run effect immediately and on changes |

### use() Pattern

```lua
local unsub = user.name:use(function(new_value, old_value)
  print("Changed from", old_value, "to", new_value)
  return function()
    print("Cleanup for:", new_value)
  end
end)

-- Later: stop watching
unsub()
```

The effect receives:
- `new_value`: Current value
- `old_value`: Previous value (nil on initial call)

The cleanup function (if returned) runs:
- Before each subsequent effect call
- When `unsub()` is called

## EdgeHandle

Reactive wrapper for edge operations.

| Method | Description |
|--------|-------------|
| `edge:iter()` | Iterator over linked nodes |
| `edge:link(target)` | Link target node |
| `edge:unlink(target)` | Unlink target node |
| `edge:count()` | Count of linked nodes |
| `edge:onLink(callback)` | Subscribe to link events |
| `edge:onUnlink(callback)` | Subscribe to unlink events |
| `edge:each(effect)` | Run effect for each item with cleanup |
| `edge:filter(options)` | Create filtered EdgeHandle |

### each() Pattern

```lua
local unsub = user.posts:each(function(post)
  print("Post entered:", post.title:get())
  return function()
    print("Post left:", post.title:get())
  end
end)

-- Later: all cleanups run
unsub()
```

### filter() Method

```lua
local published = user.posts:filter({
  filters = {{ field = "published", op = "eq", value = true }},
  sort = { field = "created_at", dir = "desc" }
})

for post in published:iter() do
  print(post.title:get())
end
```

Filter operators: `eq`, `gt`, `gte`, `lt`, `lte`

## Property Rollup

Property rollups are **materialized as node properties**. They provide Signal-like access and can be used in type indexes and view filters.

| Method | Description |
|--------|-------------|
| `rollup:get()` | Get current value |
| `rollup:set(value)` | Not allowed (read-only, auto-computed) |
| `rollup:use(effect)` | React to value changes |

Compute types:
- `count` - Number of targets (optionally filtered)
- `sum` - Sum of property values
- `avg` - Average of property values (nil if empty)
- `min` - Minimum property value (nil if empty)
- `max` - Maximum property value (nil if empty)
- `first` - First target's property value
- `last` - Last target's property value
- `any` - True if any target matches filters (or has truthy property)
- `all` - True if all targets have truthy property value

### Using Property Rollups in Indexes

```lua
{
  name = "User",
  indexes = {
    { name = "by_post_count", fields = {{ name = "post_count", dir = "desc" }} },
  },
  rollups = {
    { kind = "property", name = "post_count", edge = "posts", compute = "count" },
  },
}

-- Then filter views by rollup value
local view = graph:view({
  type = "User",
  filters = {{ field = "post_count", op = "gte", value = 10 }},
})
```

## Reference Rollup

Reference rollups are **computed single-node references**. They provide Signal-like access, returning the node proxy directly (or nil).

| Method | Description |
|--------|-------------|
| `rollup:get()` | Get the referenced node (or nil) |
| `rollup:set(value)` | Not allowed (computed) |
| `rollup:use(effect)` | React to reference changes |

```lua
-- Get the referenced node (or nil)
local post = user.latest_post:get()
if post then
  print(post.title:get())
end

-- React to changes
local unsub = user.latest_post:use(function(post)
  if post then
    print("Latest post is now:", post.title:get())
  else
    print("No posts")
  end
  return function()  -- optional cleanup
    print("Cleanup")
  end
end)
```

## Collection Rollup

Collection rollups are **virtual filtered edges**. They provide full EdgeHandle access with pre-applied filters and are traversable in views.

| Method | Description |
|--------|-------------|
| `rollup:iter()` | Iterator over matching nodes |
| `rollup:count()` | Count of matching nodes |
| `rollup:each(effect)` | Run effect for each matching item |
| `rollup:onLink(callback)` | Subscribe to matching items entering |
| `rollup:onUnlink(callback)` | Subscribe to matching items leaving |
| `rollup:link(target)` | Not allowed (use underlying edge) |
| `rollup:unlink(target)` | Not allowed (use underlying edge) |

```lua
-- Iterate filtered items
for post in user.published_posts:iter() do
  print(post.title:get())
end

-- React to membership changes
user.published_posts:each(function(post)
  print("Published:", post.title:get())
  return function()
    print("No longer published:", post.title:get())
  end
end)
```

## Index Coverage

A query is **covered** by an index if:

1. All equality filters match a prefix of index fields (in order)
2. At most one range filter, immediately after equality filters
3. Sort field equals the range field and direction matches
4. No gaps in filter field coverage

## Graph Methods

### CRUD

| Method | Description |
|--------|-------------|
| `graph:insert(type, props)` | Create node, returns node proxy |
| `graph:get(id)` | Get node by id, returns proxy or nil |
| `graph:update(id, props)` | Merge properties, returns node or nil |
| `graph:delete(id)` | Delete node and edges, returns success |

### Low-Level Edge Operations

| Method | Description |
|--------|-------------|
| `graph:link(src, edge, tgt)` | Create edge |
| `graph:unlink(src, edge, tgt)` | Remove edge |
| `graph:targets(id, edge)` | All target ids |
| `graph:sources(id, edge)` | All source ids via reverse |
| `graph:targets_count(id, edge)` | Count of targets |
| `graph:has_edge(src, edge, tgt)` | Check edge exists |

### Watch

```lua
local unsub = graph:watch(id, {
  on_change = function(id, prop, new_val, old_val)
    print(prop, "changed to", new_val)
  end
})
```

## Views

Views provide virtualized, reactive windows into graph data with expand/collapse support.

```lua
local view = graph:view({
  type = "User",
  filters = {{ field = "active", value = true }},
  edges = {
    posts = { eager = true, inline = false }
  }
}, {
  offset = 0,
  limit = 50,
  callbacks = {
    on_enter = function(node, position, edge_name, parent_id) end,
    on_leave = function(node, edge_name, parent_id) end,
    on_change = function(node, prop, new_val, old_val) end,
    on_expand = function(id, edge_name) end,
    on_collapse = function(id, edge_name) end,
  }
})
```

### Virtualized Strategy

Views use a **virtualized range strategy** that stores only expansion metadata rather than materializing all expanded children:

- **O(1) expand/collapse** for metadata updates
- **O(M) subscriptions** when expanding M children (for deep reactivity)
- **Sparse storage**: Only expanded nodes track expansion state
- **On-demand resolution**: Virtual positions resolved to actual nodes during `items()`

This means expanding a node with 100K children is O(1) time and memory for metadata, with subscriptions added incrementally.

### View Methods

| Method | Description |
|--------|-------------|
| `view:items()` | Iterator over visible items in viewport |
| `view:total()` | Count of root nodes matching filter |
| `view:visible_total()` | Total visible items (roots + all expansions) |
| `view:collect()` | All viewport items as list |
| `view:scroll(offset)` | Set pagination offset |
| `view:expand(id, edge)` | Expand edge on node at any depth |
| `view:collapse(id, edge)` | Collapse edge, fires on_leave for descendants |
| `view:destroy()` | Clean up all subscriptions |

### Item Properties

| Property | Description |
|----------|-------------|
| `item.id` | Node id |
| `item.node` | Node proxy |
| `item.depth` | Visual depth (0 = root) |
| `item.edge` | Edge name (nil for roots) |

### View Edge Configuration

When creating a view, edge configuration controls how children are displayed and loaded:

```lua
edges = {
  posts = {
    eager = true,      -- Auto-expand on view creation
    inline = true,     -- Skip items, hoist children
    filters = {{ field = "published", value = true }},
    sort = { field = "created_at", dir = "desc" },
    skip = 0,          -- Skip first N children (default: 0)
    take = 10,         -- Take at most N children (default: nil = all)
    edges = {          -- Nested edge configuration
      comments = { eager = true }
    }
  }
}
```

| Option | Type | Description |
|--------|------|-------------|
| `eager` | bool/function | Auto-expand this edge when parent enters view |
| `inline` | bool/function | Skip children in items, hoist grandchildren up |
| `filters` | list | Only show children matching filters |
| `sort` | table | Sort children by field and direction |
| `skip` | number | Skip first N children after filter/sort (default: 0) |
| `take` | number | Take at most N children after skip (default: nil = all) |
| `edges` | table | Nested edge configuration for children |
| `recursive` | bool | Apply same config recursively to matching edges |

#### Inline Edges

When `inline = true`, children from that edge are **not displayed** as separate items. Instead, their descendants (via non-inline edges) are hoisted up to the parent's level:

```lua
-- User → posts (inline) → Post → comments → Comment
-- Visible items: User, Comment (Post is skipped)

local view = g:view({
  type = "User",
  edges = {
    posts = {
      inline = true,
      edges = { comments = {} }  -- non-inline by default
    }
  }
})

view:expand(user._id, "posts")
view:expand(post._id, "comments")

-- items(): [User at depth 0, Comment at depth 1]
-- Post is skipped because posts edge is inline
```

Key behaviors:
- Inline children don't fire `on_enter`/`on_leave` callbacks
- Inline children don't count toward `visible_total()`
- Depth calculation skips inline levels
- Nested inline edges stack (all intermediates skipped)

#### Edge Cursors (skip/take)

The `skip` and `take` options provide per-edge pagination, controlling which children are selected after filtering and sorting:

```lua
edges = {
  posts = {
    sort = { field = "created_at", dir = "desc" },
    skip = 0,   -- Skip first N (default: 0)
    take = 1,   -- Take at most N (default: nil = all)
  }
}
```

| `take` value | Behavior |
|--------------|----------|
| `nil` (default) | All matching children |
| `N` | At most N children after `skip` |
| `0` | No children (valid but rarely useful) |

**Evaluation order**: `filters` → `sort` → `skip` → `take`

**Index efficiency**: With `take = 1` on a sorted edge, iteration stops after one item, avoiding full traversal.

**Combined with inline**: Select specific children, skip them, hoist their descendants:

```lua
-- User's latest post's first 3 comments (post not visible)
edges = {
  posts = {
    inline = true,
    sort = { field = "created_at", dir = "desc" },
    take = 1,  -- Only latest post
    edges = {
      comments = { take = 3 }  -- Its first 3 comments
    }
  }
}
-- Visible: User (depth 0), up to 3 Comments (depth 1)
```

**Combined with eager**: Auto-expands but respects cursor limits:

```lua
edges = {
  friends = {
    eager = true,
    sort = { field = "score", dir = "desc" },
    take = 5,  -- Only top 5 friends auto-expand
  }
}
```

**Combined with recursive**: Each recursion level applies the same skip/take:

```lua
edges = {
  children = {
    recursive = true,
    take = 3,  -- Each level shows at most 3 children
  }
}
```

### Deep Reactivity

Views automatically track all visible nodes (roots and expanded children) and fire callbacks when they change:

```lua
-- Callbacks fire for nodes at any depth
callbacks = {
  on_enter = function(node, position, edge_name, parent_id)
    -- position: index in root list (nil for children)
    -- edge_name: edge from parent (nil for roots)
    -- parent_id: parent node ID (nil for roots)
  end,

  on_leave = function(node, edge_name, parent_id)
    -- Fires when node unlinked, collapsed, or deleted
    -- edge_name/parent_id: nil for roots
  end,

  on_change = function(node, prop, new_val, old_val)
    -- Fires for any visible node property change
    -- For multi-parent nodes, fires once per path
  end,
}
```

**Multi-parent DAG support**: When a node appears at multiple paths (via different parents), `on_change` fires once per path, and `on_enter`/`on_leave` fire for each path independently.

### View Internal State

Views maintain sparse expansion metadata:

```lua
view = {
  -- Core state
  graph = graph,
  type = "User",
  filters = {...},
  offset = 0,
  limit = 50,

  -- Virtualized expansion (sparse)
  expansions = {},       -- [path_key][edge_name] = { count, index_name }
  expanded_at = {},      -- [path_key] = true if has expansions
  _expansion_size = 0,   -- Sum of all expansion counts

  -- Deep reactivity subscriptions (ref-counted)
  node_watchers = {},    -- [node_id] = { unsub, ref_count }
  edge_watchers = {},    -- ["path_key:edge_name"] = unsub
}
```

Path keys encode the tree location: `"1"` for root, `"1:posts:5"` for child, `"1:posts:5:comments:12"` for nested child.

## Reactivity

### Property Changes

When a property changes:
1. Re-index in affected type indexes (including materialized rollup values)
2. Re-index in affected edge indexes
3. Notify views:
   - Root nodes: `on_enter`/`on_leave` if filter matching changes
   - All visible nodes: `on_change` for property updates (fires per-path for multi-parent)
4. Trigger Signal subscribers
5. Update affected property rollups on source nodes (via reverse edges)

### Edge Changes

When an edge is linked/unlinked:
1. Update edge indexes
2. **Update view expansion counts** (O(1) metadata update)
3. **Fire view callbacks for expanded edges**:
   - `on_enter` when child linked to expanded parent
   - `on_leave` when child unlinked from expanded parent
4. **Update materialized property rollups** (count, sum, etc.)
5. Trigger EdgeHandle subscribers
6. Reference and collection rollups automatically reflect changes

### Deep View Reactivity

Views subscribe to all visible nodes using ref-counted watchers:

```lua
-- When a node is expanded into the view:
1. Subscribe to node changes (increment ref_count if already subscribed)
2. Subscribe to expanded edge link/unlink events

-- When a node is collapsed/unlinked from view:
1. Decrement ref_count for node subscription
2. Unsubscribe if ref_count reaches 0
3. Clean up edge subscriptions
```

This ensures callbacks fire for deep children without materializing the entire tree.

### Rollup Update Triggers

Property rollups are updated when:
- An edge is linked or unlinked (affects count, any, all, etc.)
- A target property changes (affects sum, avg, min, max, etc.)
- A filter field changes (affects filtered counts)

Reference and collection rollups are computed on access but react to:
- Edge link/unlink events
- Target property changes affecting filters or sort order

---

## Appendix: Planned Improvements

This section documents improvements to neograph-native based on user feedback.

### A.1 Edge Handle Identity

**Status:** ✅ Implemented

Edge handles are now cached at the graph level by `(node_id, edge_name)`, ensuring consistent identity across accesses. All subscriptions share state regardless of which handle instance registered them:

```lua
local edge1 = node.sessions
local edge2 = node.sessions
edge1:onLink(callback)
edge2:link(target)  -- callback fires correctly
```

---

### A.2 Multi-Subscriber Events

**Status:** ✅ Implemented

Multiple subscribers via `View:on()` and constructor callbacks all fire correctly, in registration order.

---

### A.3 Reverse Edge Event Propagation

**Status:** ✅ Implemented

Both forward and reverse edges fire their respective events when either is linked/unlinked:

```lua
-- Schema: breakpoints -> Breakpoint, reverse = "sources"
source.breakpoints:onLink(callback_a)
breakpoint.sources:onLink(callback_b)

breakpoint.sources:link(source)
-- Both callback_a and callback_b fire
```

---

### A.4 Use-After-Free Safety

**Status:** Design decision pending

Disposed views/signals can still have callbacks fire, potentially accessing freed state. Currently, users must call `view:destroy()` explicitly before releasing references.

**Options under consideration:**
1. Guard all callback invocations with validity checks
2. Use weak references for callbacks
3. Document explicit `dispose()` requirement (current approach)
4. Integrate with Lua `__gc` finalizers for automatic cleanup

---

### A.5 Undefined Property Access

**Status:** Design decision pending

Currently, accessing any property returns a Signal, even undefined ones:

```lua
local node = graph:insert("Session", { name = "test" })
node.nonexistent  -- returns Signal (not nil)
node._internal    -- returns Signal (intercepts internal state)
```

**Options under consideration:**
1. Require property declarations in schema, return nil for undefined
2. Add `node:signal(name)` for explicit access, return raw values for direct access
3. Reserve `_` prefix for internal use, return nil for `_` keys

---

### A.6 Previous Value in Callbacks

**Status:** ✅ Implemented

Signal `use()` callbacks now receive the old value as a second argument (backward compatible):

```lua
signal:use(function(new_value, old_value)
  print("Changed from", old_value, "to", new_value)
end)
```

---

### A.7 Deep Equality for Change Detection

**Status:** ✅ Already Working

Primitive values (nil, boolean, number, string) use value equality. Setting a property to the same value does not trigger subscribers:

```lua
signal:set("Alice")
signal:set("Alice")  -- No update triggered
```

Table properties are not supported by neograph-native. Use separate properties or JSON serialization for structured data.

---

### A.8 Edge Iteration API (Documentation)

**Status:** ✅ Documented

These methods exist for array access and counting:

```lua
-- Collect items as array
local items = view:collect()

-- Get count without iterating
local count = view:visible_total()
```
