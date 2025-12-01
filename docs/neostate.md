# Neostate

A fine-grained reactive state management library for Neovim written in Lua.

## Overview

Neostate provides reactive primitives for building responsive UIs and managing state in Neovim plugins. Key features include:

- **Reactive Primitives**: Signal, List, Set, Collection with automatic change tracking
- **Automatic Lifecycle Management**: Parent-child relationships ensure proper cleanup
- **Context Tracking**: Implicit parent-child relationships during object creation
- **Indexed Collections**: Fast lookup with reactive filtering and aggregation
- **Async Support**: Promise/await pattern with coroutine-based execution
- **Class System**: OOP with reactive properties and automatic lifecycle

## Quick Start

```lua
local neostate = require("neostate")

-- Reactive value
local count = neostate.Signal(0, "counter")

count:use(function(val)
  print("Count:", val)
end)

count:set(1)  -- Prints "Count: 1"
count:set(2)  -- Prints "Count: 2"

-- Observable list
local items = neostate.List("items")

items:on_added(function(item)
  print("Added:", item.name)
end)

items:add(neostate.Disposable({ name = "Item1" }))
```

## Disposable

The foundation of lifecycle management. All reactive objects are disposables.

### Creating Disposables

```lua
local obj = neostate.Disposable(target?, parent?, debug_name?)
```

**Parameters:**
- `target` (table): Object to make disposable (default: `{}`)
- `parent` (Disposable): Explicit parent (default: current context)
- `debug_name` (string): Name for debugging/tracing

**Example:**

```lua
local root = neostate.Disposable({}, nil, "Root")

local child = neostate.Disposable({ data = "value" }, root, "Child")
-- child automatically disposed when root is disposed
```

### Methods

#### `on_dispose(fn)`

Register a cleanup function.

```lua
local unsubscribe = obj:on_dispose(function()
  print("Cleaning up")
end)

-- Optionally remove the cleanup
unsubscribe()
```

#### `dispose()`

Dispose the object and all children (LIFO order).

```lua
obj:dispose()
```

#### `run(fn, ...)`

Execute function with this object as the context parent.

```lua
root:run(function()
  -- Any disposables created here become children of root
  local child = neostate.Disposable({}, nil, "Child")
end)
```

#### `bind(fn)`

Create a callback that preserves context across async boundaries.

```lua
vim.schedule(obj:bind(function()
  -- Children created here still belong to obj
  local async_child = neostate.Disposable({}, nil, "AsyncChild")
end))
```

#### `set_parent(parent)`

Change parent (reparenting).

```lua
child:set_parent(new_parent)
child:set_parent(nil)  -- Detach (become root)
```

## Signal

Reactive single-value container.

### Creating Signals

```lua
local signal = neostate.Signal(initial_value, debug_name?)
```

**Example:**

```lua
local name = neostate.Signal("Alice", "name")
local age = neostate.Signal(25, "age")
```

### Methods

#### `get()`

Get current value.

```lua
local value = signal:get()
```

#### `set(value)`

Set new value (triggers subscribers if changed).

```lua
signal:set("Bob")
```

#### `use(fn)`

React to current value AND all future changes.

```lua
local cleanup = signal:use(function(value)
  print("Value:", value)

  -- Optional: return cleanup function
  return function()
    print("Cleanup before next value")
  end
end)
```

#### `watch(fn)`

React to future changes only (not current value).

```lua
signal:watch(function(new_value)
  print("Changed to:", new_value)
end)
```

#### `release()`

Release current value without disposing it (for moving values).

```lua
local value = signal:release()
-- Signal now holds nil, but value wasn't disposed
```

## Computed

Derived reactive values.

```lua
local computed = neostate.computed(fn, deps, debug_name?)
```

**Parameters:**
- `fn` (function): Computation function
- `deps` (Signal[]): Dependencies to watch
- `debug_name` (string): Name for debugging

**Example:**

```lua
local first = neostate.Signal("John", "first")
local last = neostate.Signal("Doe", "last")

local fullName = neostate.computed(function()
  return first:get() .. " " .. last:get()
end, { first, last }, "fullName")

fullName:use(function(name)
  print("Full name:", name)  -- "John Doe"
end)

last:set("Smith")  -- Prints "Full name: John Smith"
```

## List

Observable array.

### Creating Lists

```lua
local list = neostate.List(debug_name?)
```

### Methods

#### `add(item)`

Add a disposable item.

```lua
local item = neostate.Disposable({ name = "Item1" })
list:add(item)
```

#### `adopt(item)`

Add existing disposable with reparenting.

```lua
local orphan = neostate.Disposable({ name = "Orphan" }, nil, "Orphan")
list:adopt(orphan)  -- orphan now belongs to list
```

#### `delete(predicate)`

Remove and dispose item matching predicate.

```lua
list:delete(function(item) return item.id == 5 end)
```

#### `extract(predicate)`

Remove item without disposing (for moving).

```lua
local item = list:extract(function(item) return item.id == 5 end)
other_list:adopt(item)  -- Move to another list
```

#### `find(predicate_or_name)`

Find first matching item.

```lua
local item = list:find(function(item) return item.id == 5 end)
local item = list:find("ItemName")  -- Match by .name property
```

#### `iter()`

Iterate over items.

```lua
for item in list.iter() do
  print(item.name)
end
```

#### `on_added(fn)` / `on_removed(fn)`

Subscribe to additions/removals.

```lua
list:on_added(function(item)
  print("Added:", item.name)
end)

list:on_removed(function(item)
  print("Removed:", item.name)
end)
```

#### `each(fn)`

React to existing AND future items.

```lua
list:each(function(item)
  print("Item:", item.name)

  return function()
    print("Item cleanup:", item.name)
  end
end)
```

#### `subscribe(fn)`

React to future items only.

```lua
list:subscribe(function(item)
  print("New item:", item.name)
end)
```

#### `latest()`

Get reactive Signal for most recently added item.

```lua
local latest = list:latest()
latest:use(function(item)
  if item then
    print("Latest item:", item.name)
  end
end)
```

## Set

Observable set (uses table keys for O(1) lookup).

```lua
local set = neostate.Set(debug_name?)

set:add(item)     -- Add item
set:remove(item)  -- Remove and dispose item

for item in set.iter() do
  print(item)
end
```

## Collection

List with indexing capabilities.

### Creating Collections

```lua
local collection = neostate.Collection(debug_name?)
```

### Adding Indexes

```lua
collection:add_index("by_id", function(item) return item.id end)
collection:add_index("by_name", function(item) return item.name end)
collection:add_index("by_state", function(item) return item.state:get() end)
-- Reactive indexes update automatically when Signal values change
```

### Querying

```lua
-- Get all items with key
local items = collection:get("by_name", "Alice")

-- Get first item with key
local item = collection:get_one("by_id", 42)
```

### Filtering

```lua
-- Filter by index
local active = collection:where("by_state", "active")

-- Filter by predicate
local large = collection:where(function(item) return item.size > 100 end)

-- Chain filters
local active_large = collection:where("by_state", "active")
                              :where(function(item) return item.size > 100 end)
```

### Aggregation

```lua
-- Aggregate with optional signal watching
local total = collection:aggregate(
  function(items)
    local sum = 0
    for _, item in ipairs(items) do
      sum = sum + item.value:get()
    end
    return sum
  end,
  function(item) return item.value end  -- Watch this signal per item
)

total:use(function(sum)
  print("Total:", sum)
end)
```

### Predicates

```lua
-- Check if any item matches
local has_error = collection:some(function(item) return item.error:get() end)

-- Check if all items match
local all_ready = collection:every(function(item) return item.ready:get() end)

has_error:use(function(has)
  if has then
    print("There are errors!")
  end
end)
```

### Scoped Collections

```lua
-- Filter where item's indexed value matches any ID in source collection
local scoped_frames = all_frames:where_in("by_stack_id", current_stacks)
```

## Promise

Async/await support for coroutines.

### Creating Promises

```lua
-- Empty promise (resolve/reject manually)
local promise = neostate.Promise(nil, debug_name?)

-- With executor
local promise = neostate.Promise(function(resolve, reject)
  vim.defer_fn(function()
    resolve("Done!")
  end, 1000)
end, "timer")
```

### Methods

```lua
promise:resolve(value)
promise:reject(error)
promise:is_pending()
promise:is_settled()

promise:then_do(function(value)
  print("Resolved:", value)
end)

promise:catch_do(function(err)
  print("Error:", err)
end)
```

### Await

```lua
-- In coroutine context
local result = neostate.await(promise)

-- Settle (returns result, error tuple)
local result, err = neostate.settle(promise)
if err then
  print("Error:", err)
else
  print("Result:", result)
end
```

## void

Fire-and-forget async helper.

```lua
neostate.void(function()
  -- Async code here
  local result = neostate.await(some_promise)
  print("Got:", result)
end)()
```

## mount

Mount a disposable to a buffer lifecycle.

```lua
local root = neostate.mount(bufnr, "BufferRoot")

-- root is disposed when buffer is wiped
root:run(function()
  -- Create children that will be cleaned up with buffer
end)
```

## Class

OOP class system with reactive properties.

### Defining Classes

```lua
local MyClass = neostate.Class("MyClass")

function MyClass:init(name)
  self.name = self:signal(name, "name")
  self.items = self:list("items")
end

function MyClass:greet()
  print("Hello, " .. self.name:get())
end
```

### Using Classes

```lua
local instance = MyClass:new("Alice")

instance.name:use(function(name)
  print("Name is:", name)
end)

instance.name:set("Bob")
instance:greet()

instance:dispose()  -- Cleans up signals and lists
```

### Class Methods

Within a class:

```lua
self:signal(value, name)      -- Create child signal
self:list(name)               -- Create child list
self:collection(name)         -- Create child collection
```

## Configuration

```lua
neostate.setup({
  trace = false,          -- Enable detailed logging
  debug_context = false,  -- Add file:line introspection (expensive)
  log_fn = print,         -- Custom log function
})
```

## Patterns

### Effect Cleanup

```lua
signal:use(function(value)
  local timer = vim.loop.new_timer()
  timer:start(1000, 0, function()
    print("Timer fired for:", value)
  end)

  return function()
    timer:stop()
    timer:close()
  end
end)
```

### Async Safety

```lua
local obj = neostate.Disposable({}, nil, "Async")

vim.schedule(obj:bind(function()
  -- Children created here inherit obj's lifecycle
  local child = neostate.Disposable({}, nil, "ScheduledChild")
end))
```

### Moving Items

```lua
local item = list1:extract(function(x) return x.id == 5 end)
list2:adopt(item)  -- Reparents without disposal
```

### Reactive Indexes

```lua
collection:add_index("by_state", function(item)
  return item.state  -- If this is a Signal, index updates automatically
end)

item.state:set("active")  -- Index automatically updated
```

### Computed Dependencies

```lua
local a = neostate.Signal(1)
local b = neostate.Signal(2)

local sum = neostate.computed(function()
  return a:get() + b:get()
end, { a, b })

a:set(10)  -- sum updates to 12
```

## Debug Tracing

Enable tracing to see reactive operations:

```lua
neostate.setup({ trace = true })

-- Output shows:
-- ⚡ [Signal:counter] nil -> 0
-- 👀 [Signal:counter] subscribe registered
-- ⚡ [Signal:counter] 0 -> 1
-- 📥 [List:items] Adopted Item. Count: 1
-- 🔴 [Child] Disposing...
```
