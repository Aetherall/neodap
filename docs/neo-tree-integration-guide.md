# Neo-tree Integration Guide: Building Sources the Right Way

## Table of Contents

1. [Introduction](#introduction)
2. [Core Architecture](#core-architecture)
3. [The Item-to-Node Abstraction](#the-item-to-node-abstraction)
4. [The Sacred Contract: What Sources Should and Shouldn't Do](#the-sacred-contract)
5. [The Delegation Pattern](#the-delegation-pattern)
6. [State Management Philosophy](#state-management-philosophy)
7. [Custom Types and Renderers](#custom-types-and-renderers)
8. [The renderer.show_nodes API](#the-renderershownodes-api)
9. [Common Pitfalls and Their Solutions](#common-pitfalls-and-their-solutions)
10. [Debugging Neo-tree Integrations](#debugging-neo-tree-integrations)
11. [Case Study: Variables Plugin Investigation](#case-study-variables-plugin-investigation)
12. [Best Practices Checklist](#best-practices-checklist)

## Introduction

This guide documents the internal architecture of Neo-tree and provides comprehensive guidelines for building source plugins. It's based on extensive investigation of Neo-tree's source code and real-world debugging of integration issues.

**Key Insight**: Neo-tree provides a powerful abstraction layer that allows source developers to provide simple data structures (items) without worrying about the complexities of tree UI management. Understanding this abstraction is crucial for successful integration.

## Core Architecture

Neo-tree follows a three-layer architecture:

```
┌─────────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Source Layer       │ --> │  Renderer Layer  │ --> │   NUI Layer     │
│ (Your Plugin)       │     │ (Neo-tree Core)  │     │ (Tree Widget)   │
├─────────────────────┤     ├──────────────────┤     ├─────────────────┤
│ • Provides items    │     │ • Transforms     │     │ • Manages tree  │
│ • Loads data        │     │   items to nodes │     │   state         │
│ • Handles commands  │     │ • Manages UI     │     │ • Handles events│
│ • Source logic      │     │ • Preserves state│     │ • Renders lines │
└─────────────────────┘     └──────────────────┘     └─────────────────┘
```

### Key Components

1. **Sources** (`neo-tree.sources.*`): Provide data and handle source-specific logic
2. **Renderer** (`neo-tree.ui.renderer`): Transforms items to nodes and manages display
3. **Common Commands** (`neo-tree.sources.common.commands`): Reusable command implementations
4. **Manager** (`neo-tree.sources.manager`): Coordinates sources and handles events
5. **NUI Tree** (`nui.tree`): The underlying tree widget implementation

## The Item-to-Node Abstraction

### What Are Items?

Items are simple Lua tables that sources provide to represent their data:

```lua
{
  -- Required fields:
  id = "unique_identifier",      -- Must be unique within the tree
  name = "display_name",         -- What users see in the tree
  type = "file|directory|custom", -- Determines icon and behavior
  
  -- Optional fields:
  children = { ... },            -- Child items (for hierarchical data)
  loaded = true/false,           -- Whether children have been fetched
  path = "/full/path",           -- File path (for filesystem sources)
  extra = { ... },               -- Source-specific data
  filtered_by = { ... },         -- Filtering information
  
  -- Any other custom fields your source needs
}
```

### What Are Nodes?

Nodes are complex NUI objects created from items. They contain:
- Internal tree state (position, parent/child relationships)
- UI state (expanded/collapsed)
- Rendering information (line numbers, indentation)
- Event handling capabilities

**Critical**: Sources should NEVER directly create or manipulate nodes. Always work with items and let Neo-tree handle the conversion.

### The Transformation Process

```lua
-- Inside renderer.lua
local function create_nodes(source_items, state, level)
  local nodes = {}
  for i, item in ipairs(source_items) do
    -- Enrich item with rendering data
    local nodeData = {
      ...item,                        -- All item properties preserved
      level = level,                  -- Tree depth
      is_last_child = (i == #items),  -- For tree lines
    }
    
    -- Create children recursively
    local children = create_nodes(item.children or {}, state, level + 1)
    
    -- Create the actual node
    local node = NuiTree.Node(nodeData, children)
    table.insert(nodes, node)
  end
  return nodes
end
```

## The Sacred Contract: What Sources Should and Shouldn't Do

### Sources SHOULD:

1. **Provide Simple Items**
   ```lua
   local items = {
     {
       id = "scope:1",
       name = "Local Variables",
       type = "directory",
       children = {},
       loaded = false
     }
   }
   ```

2. **Handle Data Loading**
   ```lua
   function MySource:load_data(node_id, callback)
     -- Fetch your data asynchronously
     self:fetch_from_backend(node_id, function(data)
       local items = self:transform_to_items(data)
       callback(items)
     end)
   end
   ```

3. **Use Common Commands with Handlers**
   ```lua
   commands = {
     toggle_node = function(state)
       common_commands.toggle_node(state, function(node)
         if not node.loaded then
           plugin:load_data(node.id, function(items)
             renderer.show_nodes(items, state, node.id)
           end)
         end
       end)
     end
   }
   ```

4. **Implement Source-Specific Logic**
   ```lua
   function MySource:custom_action(state)
     local node = state.tree:get_node()
     local item_data = node.extra  -- Access your custom data
     -- Perform source-specific operations
   end
   ```

5. **Define Custom Commands**
   ```lua
   commands = {
     my_custom_command = function(state)
       -- Source-specific functionality
     end
   }
   ```

### Sources SHOULD NOT:

1. **❌ Directly Manipulate Nodes**
   ```lua
   -- WRONG: Don't do this!
   node:expand()  -- Let Neo-tree handle expansion
   node.loaded = true  -- This is internal state
   ```

2. **❌ Clear or Reset Tree State**
   ```lua
   -- WRONG: This causes race conditions
   state.tree = nil
   state.explicitly_opened_nodes = {}
   ```

3. **❌ Call Refresh During Operations**
   ```lua
   -- WRONG: Creates race conditions
   mgr.refresh("my_source")  -- Don't refresh while user is interacting
   ```

4. **❌ Manually Manage Expansion State**
   ```lua
   -- WRONG: Neo-tree handles this
   item._is_expanded = true
   state.force_open_folders = [...]
   ```

5. **❌ Access Internal Node Structure**
   ```lua
   -- WRONG: Use provided APIs
   node._parent_id = something
   node._children = []
   ```

6. **❌ Create Nodes Directly**
   ```lua
   -- WRONG: Always use items
   local node = NuiTree.Node(...)  -- Never do this in sources
   ```

## The Delegation Pattern

Neo-tree's common commands use a delegation pattern where sources provide handlers for source-specific behavior:

### How It Works

```lua
-- From common/commands.lua
M.toggle_node = function(state, toggle_directory)
  local node = assert(state.tree:get_node())
  
  if not utils.is_expandable(node) then
    return
  end
  
  if node.type == "directory" and toggle_directory then
    toggle_directory(node)  -- Delegate to source handler!
  elseif node:has_children() then
    -- Handle UI toggle for already-loaded nodes
    if node:is_expanded() then
      node:collapse()
    else
      node:expand()
    end
    renderer.redraw(state)
  end
end
```

### Implementing the Pattern

```lua
-- In your source's commands
local common = require("neo-tree.sources.common.commands")

commands = {
  toggle_node = function(state)
    -- Pass your handler for directory/expandable nodes
    common.toggle_node(state, function(node)
      plugin:handle_toggle(state, node)
    end)
  end,
  
  -- Reuse other common commands
  close_node = common.close_node,
  close_all_nodes = common.close_all_nodes,
}
```

### The Handler Contract

Your toggle handler should:
1. Check if data needs loading (`not node.loaded`)
2. Load the data if needed
3. Call `renderer.show_nodes` with the results
4. NOT manually expand the node (renderer does this)

```lua
function Plugin:handle_toggle(state, node)
  if not node.loaded then
    self:load_children(node.id, function(child_items)
      -- Just show the nodes, renderer handles expansion
      renderer.show_nodes(child_items, state, node.id)
    end)
  end
  -- If already loaded, common.toggle_node handles UI toggle
end
```

## State Management Philosophy

Neo-tree maintains a clear separation between data state and UI state:

### Data State (Source Responsibility)

- **`loaded`**: Whether children have been fetched
- **`children`**: The actual child items
- **`extra`**: Source-specific data

Sources manage when and how data is loaded.

### UI State (Neo-tree Responsibility)

- **`expanded`**: Whether node is visually open
- **`selected`**: Whether node is selected
- **`focused`**: Whether node has focus
- **Tree position**: Where nodes appear in the tree

Neo-tree manages all visual state internally.

### State Lifecycle

1. **Initial Load**: Source provides root items
2. **User Expands Node**: 
   - Neo-tree calls your toggle handler
   - You load data and provide child items
   - Neo-tree marks node as loaded and expanded
3. **Subsequent Toggles**: Neo-tree handles expand/collapse without calling your handler
4. **Data Changes**: You call `renderer.show_nodes` with updated items
5. **State Preservation**: Neo-tree preserves expansion state across updates

### Example: Handling Ephemeral Data

For sources with ephemeral data (like debug variables):

```lua
-- When data becomes invalid (e.g., debugger stops)
function Plugin:on_debugger_stopped()
  -- Just track that we need fresh data
  self.current_frame = nil
  -- Don't clear tree state!
end

-- When loading data
function Plugin:load_children(node_id, callback)
  if not self.current_frame then
    -- Return empty items, Neo-tree handles the rest
    callback({})
    return
  end
  
  -- Normal loading
  self:fetch_variables(node_id, callback)
end
```

## Custom Types and Renderers

While Neo-tree provides default rendering for "file" and "directory" types, you can define custom types with their own rendering logic.

### Defining Custom Types

```lua
-- In your items
local item = {
  id = "breakpoint:1",
  name = "main.lua:42",
  type = "breakpoint",  -- Custom type!
  extra = {
    enabled = true,
    condition = "x > 10"
  }
}
```

### Creating Custom Renderers

Define renderers in your source configuration:

```lua
require("neo-tree").setup({
  sources = {
    "my_source",
  },
  my_source = {
    renderers = {
      -- Override default renderer
      directory = {
        { "indent" },
        { "icon", default = "󰉋" },
        { "name" },
        { "custom_info" },  -- Custom component
      },
      -- Custom type renderer
      breakpoint = {
        { "indent" },
        { "breakpoint_icon" },  -- Custom component
        { "name" },
        { "breakpoint_condition" },  -- Custom component
      }
    },
    components = {
      -- Define custom components
      breakpoint_icon = function(config, node, state)
        local enabled = node.extra and node.extra.enabled
        return {
          text = enabled and "●" or "○",
          highlight = enabled and "NeotreeBreakpointEnabled" or "NeotreeBreakpointDisabled"
        }
      end,
      breakpoint_condition = function(config, node, state)
        local condition = node.extra and node.extra.condition
        if condition then
          return {
            text = " [" .. condition .. "]",
            highlight = "Comment"
          }
        end
        return {}
      end,
    }
  }
})
```

### Renderer Components

Components return tables with:
- `text`: The text to display
- `highlight`: The highlight group to use

Built-in components include:
- `indent`: Tree indentation
- `icon`: File/folder icons
- `name`: The item name
- `git_status`: Git status indicators
- `diagnostics`: LSP diagnostics

### Making Custom Types Expandable

Custom types can be expandable like directories:

```lua
local item = {
  id = "custom:1",
  name = "Expandable Custom Type",
  type = "my_custom_type",
  children = {},  -- Having children makes it expandable
  loaded = false,
}

-- In your toggle handler
function Plugin:handle_toggle(state, node)
  if node.type == "my_custom_type" and not node.loaded then
    self:load_custom_children(node.id, function(items)
      renderer.show_nodes(items, state, node.id)
    end)
  end
end
```

## The renderer.show_nodes API

The `renderer.show_nodes` function is the primary interface between sources and Neo-tree:

```lua
renderer.show_nodes(items, state, parent_id, callback)
```

### Parameters

- **`items`**: Array of item tables to display
- **`state`**: The current source state
- **`parent_id`**: (Optional) ID of parent node for lazy loading
- **`callback`**: (Optional) Function to call after rendering

### Behavior Without parent_id (Full Tree Update)

```lua
-- Replace entire tree
renderer.show_nodes(root_items, state)

-- Neo-tree will:
-- 1. Save currently expanded nodes
-- 2. Replace tree with new items
-- 3. Restore expansion state for matching IDs
-- 4. Focus previously focused node if it still exists
```

### Behavior With parent_id (Lazy Loading)

```lua
-- Load children for a specific node
renderer.show_nodes(child_items, state, "parent_node_id")

-- Neo-tree will:
-- 1. Find the parent node
-- 2. Set parent.loaded = true
-- 3. Add children to parent
-- 4. AUTOMATICALLY expand the parent
-- 5. Redraw the tree
```

### Critical Discovery: Automatic Expansion

When loading children with `parent_id`, Neo-tree automatically expands the parent node:

```lua
-- From renderer.lua
if parent_id ~= nil then
  local node = assert(state.tree:get_node(parent_id))
  node.loaded = true
  node:expand()  -- Automatic expansion!
end
```

**This means**: Never manually expand nodes after loading children. The renderer handles it.

## Common Pitfalls and Their Solutions

### 1. Race Condition: Refresh During User Interaction

**Problem**:
```lua
thread:onStopped(function()
  mgr.refresh("my_source")  -- Races with user clicks!
end)
```

**Solution**:
```lua
thread:onStopped(function()
  -- Just update your internal state
  self.current_data = nil
  -- Let Neo-tree refresh when needed
end)
```

### 2. Fighting Automatic Expansion

**Problem**:
```lua
node:expand()  -- Manual expansion
plugin:LoadData(...)  -- Then load
-- Results in duplicate operations
```

**Solution**:
```lua
-- Just load, let renderer expand
plugin:LoadData(node.id, function(items)
  renderer.show_nodes(items, state, node.id)
  -- That's it!
end)
```

### 3. Misunderstanding the Toggle Callback

**Problem**:
```lua
toggle_node = function(state)
  common.toggle_node(state, function()
    -- Wrong: This replaces ALL toggle behavior
    plugin:LoadData(...)
  end)
end
```

**Solution**:
```lua
toggle_node = function(state)
  common.toggle_node(state, function(node)
    -- Right: Only handle unloaded nodes
    if not node.loaded then
      plugin:LoadData(...)
    end
  end)
end
```

### 4. Clearing Tree State

**Problem**:
```lua
-- Trying to reset the tree
state.tree = nil
state.explicitly_opened_nodes = {}
```

**Solution**:
```lua
-- Provide empty items, preserve tree structure
renderer.show_nodes({}, state)
```

### 5. Manual State Management

**Problem**:
```lua
-- Trying to track expansion manually
item._is_expanded = true
state.force_open_folders = [item.id]
```

**Solution**:
```lua
-- Let Neo-tree handle all UI state
-- Just provide data through items
```

### 6. ID Instability

**Problem**:
```lua
-- IDs that change between refreshes
item.id = "node_" .. math.random()
```

**Solution**:
```lua
-- Use stable, deterministic IDs
item.id = string.format("type:%s:name:%s", item.type, item.name)
```

### 7. Not Using Common Commands

**Problem**:
```lua
-- Reimplementing common functionality
commands = {
  close_node = function(state)
    -- Custom implementation
  end
}
```

**Solution**:
```lua
-- Reuse common commands
local cc = require("neo-tree.sources.common.commands")
commands = {
  close_node = cc.close_node,
  -- Add source-specific commands
  my_custom_command = function(state) ... end
}
```

## Debugging Neo-tree Integrations

### 1. Enable Neo-tree Logging

```vim
:lua require("neo-tree.log").set_level("trace")
```

### 2. Check for Duplicate IDs

The most common error. Ensure IDs are:
- Unique within the tree
- Stable across refreshes
- Not modified after creation

### 3. Trace Execution Flow

Add strategic logging:
```lua
function Plugin:LoadData(node_id, callback)
  log.debug("[Plugin] Loading data for:", node_id)
  self:fetch_data(node_id, function(data)
    log.debug("[Plugin] Received data:", #data, "items")
    local items = self:transform_to_items(data)
    log.debug("[Plugin] Transformed to items:", vim.inspect(items))
    callback(items)
  end)
end
```

### 4. Monitor State Changes

```lua
-- In your commands
toggle_node = function(state)
  local node = state.tree:get_node()
  log.debug("Toggle node:", node.id, "loaded:", node.loaded, "expanded:", node:is_expanded())
  -- ... rest of implementation
end
```

### 5. Use NEODAP_PANIC for Error Visibility

```bash
NEODAP_PANIC=true nvim
```

This makes async errors fatal instead of logged, helping identify issues during development.

## Case Study: Variables Plugin Investigation

Our investigation of the Variables plugin revealed several anti-patterns:

### The Problem

1. **Duplicate ID Error**: `duplicate node id scope[3]:Global[-9223372036854775808]`
2. **Visual State Mismatch**: Nodes appeared expanded but showed no children
3. **Test Failures**: Tests passed despite broken functionality

### Root Causes Discovered

1. **Race Condition with Refresh**:
   ```lua
   -- WRONG: Refresh races with user interaction
   thread:onStopped(function()
     mgr.refresh("variables")
   end)
   ```

2. **Manual Expansion Management**:
   ```lua
   -- WRONG: Fighting Neo-tree's automatic expansion
   node:expand()
   plugin:LoadVariablesData(...)
   ```

3. **Misunderstood Toggle Callback**:
   ```lua
   -- WRONG: Thought callback should expand
   commands.toggle_node(state, function()
     plugin:LoadVariablesData(...)  -- Never expanded!
   end)
   ```

### The Solution

Properly implement the delegation pattern:
```lua
toggle_node = function(state)
  common_commands.toggle_node(state, function(node)
    if not node.loaded then
      plugin:LoadVariablesData(state, node.id, function(items)
        renderer.show_nodes(items, state, node.id)
        -- Let renderer handle expansion
      end)
    end
  end)
end
```

### Lessons Learned

1. **Read the source code** - Assumptions about how Neo-tree works were wrong
2. **Follow established patterns** - Common commands exist for a reason
3. **Don't fight the framework** - Neo-tree knows how to manage trees
4. **Test actual behavior** - Passing tests don't mean working functionality

## Best Practices Checklist

### Source Setup

- [ ] Use stable, unique IDs for all items
- [ ] Define clear item types (use custom types when needed)
- [ ] Include all necessary data in item.extra
- [ ] Set loaded=false for lazy-loadable items

### Command Implementation

- [ ] Use common commands with delegation
- [ ] Only load data in toggle handlers, don't manage UI
- [ ] Never manually expand/collapse nodes in handlers
- [ ] Implement source-specific commands separately

### State Management

- [ ] Let Neo-tree manage all UI state
- [ ] Only track data availability in your source
- [ ] Don't clear or reset tree state
- [ ] Use renderer.show_nodes for all updates

### Integration Patterns

- [ ] Follow the prefetcher pattern for recursive operations
- [ ] Handle async operations properly
- [ ] Don't refresh during user interactions
- [ ] Test with actual user interactions, not just snapshots

### Debugging

- [ ] Add logging at integration boundaries
- [ ] Check for duplicate IDs
- [ ] Verify your assumptions about Neo-tree behavior
- [ ] Use NEODAP_PANIC during development

### Performance

- [ ] Implement lazy loading for large datasets
- [ ] Use the prefetcher pattern for background loading
- [ ] Don't reload unchanged data
- [ ] Minimize renderer.show_nodes calls

## Conclusion

Neo-tree provides a powerful abstraction that makes building sources straightforward - if you follow its patterns. The key insight is that sources should focus on providing data through simple item structures while letting Neo-tree handle all the complex tree UI management.

By following this guide and avoiding the common pitfalls, you can build robust Neo-tree sources that integrate seamlessly with the ecosystem. Remember: when in doubt, look at how the built-in sources (filesystem, buffers, git_status) implement their functionality, and follow their patterns.

The mantra for Neo-tree source development:
> "Provide the data, trust the framework."