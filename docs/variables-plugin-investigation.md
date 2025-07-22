# Variables Plugin Investigation: Neo-tree Integration Issues

## Executive Summary

This document details our investigation into duplicate node ID errors and expansion issues in the neodap Variables plugin's Neo-tree integration. We discovered fundamental misunderstandings about Neo-tree's expansion mechanisms and race conditions in state management.

## The Problem

### Symptoms
1. **Duplicate ID Error**: `duplicate node id scope[3]:Global[-9223372036854775808]`
2. **Visual State Mismatch**: Global scope appears expanded (󰉖) but shows no children
3. **Expansion Failure**: Node reports `expanded=false` even after toggle operations
4. **Test Failures**: All Variables plugin tests pass despite broken functionality (errors are swallowed)

### The Mysterious Suffix
The `-9223372036854775808` (min int64) suffix appears to be added by nui.nvim's fallback ID generation when something goes wrong internally.

## Root Causes Discovered

### 1. Race Condition: Refresh vs Manual Expansion

Our original implementation triggered Neo-tree refresh on thread stop:

```lua
thread:onStopped(function()
    -- ...state management...
    vim.schedule(function()
        mgr.refresh("variables")  -- This races with manual expansion!
    end)
end)
```

**Timeline:**
1. Thread stops → triggers async refresh
2. User expands Global scope → loads children
3. Async refresh completes → tries to reload tree
4. Duplicate ID error → Global node exists in two states

### 2. Fundamental Misunderstanding of toggle_node

We incorrectly implemented the toggle callback:

```lua
-- WRONG: Our implementation
commands.toggle_node(state, function()
    -- We tried to load children here
    -- But never actually expanded the node!
    plugin:LoadVariablesData(state, node.id, callback)
end)
```

**The Problem:**
- When you pass a callback to `toggle_node`, YOU are responsible for ALL toggle behavior
- We loaded children but never called `node:expand()`
- The node stayed collapsed forever

### 3. Fighting Neo-tree's Automatic Expansion

Neo-tree's renderer automatically expands nodes when loading children:

```lua
-- From renderer.lua
if parent_id ~= nil then
    local node = assert(state.tree:get_node(parent_id))
    node.loaded = true      -- Marks as loaded
    node:expand()           -- Automatically expands!
end
```

But we were trying to manually expand BEFORE loading, creating state conflicts.

## How Neo-tree Sources Actually Work

### The Filesystem Pattern

```lua
M.toggle_directory = function(state, node, path_to_reveal, skip_redraw, recursive, callback)
    if node.loaded == false then
        -- First toggle: Just load data, don't expand
        state.explicitly_opened_nodes[id] = true
        fs_scan.get_items(state, id, path_to_reveal, callback, false, recursive)
    elseif node:has_children() then
        -- Subsequent toggles: Already loaded, so toggle expansion
        if node:is_expanded() then
            node:collapse()
        else
            node:expand()
        end
        renderer.redraw(state)
    end
end
```

**Key Insights:**
1. First click loads data (node stays collapsed visually)
2. Second click expands the already-loaded node
3. `renderer.show_nodes` with parent_id automatically handles expansion

### The Correct Flow

1. **User clicks collapsed node** → `toggle_node` called
2. **Check if loaded**:
   - If not loaded → Load children via `show_nodes(items, state, parent_id)`
   - If loaded → Toggle expansion state and redraw
3. **Renderer handles expansion** when loading children with parent_id

## Our Implementation Mistakes

### 1. Clearing Tree State Too Aggressively

```lua
-- We were clearing the entire tree
state.tree = nil  -- This is too aggressive!
```

### 2. Triggering Unnecessary Refreshes

```lua
-- These refreshes caused race conditions
mgr.refresh("variables")  -- Don't do this during expansion!
```

### 3. Manual Expansion Before Loading

```lua
-- Wrong order!
node:expand()  // Don't expand first
plugin:LoadVariablesData(...)  // Load should happen before expansion
```

### 4. Not Understanding Node States

- `loaded`: Whether children have been fetched
- `expanded`: Whether node is visually expanded
- These are independent states!

## Debugging Methodology

### 1. Strategic Logging
We added logging at every critical point:
- ID generation
- Node creation
- Load operations
- Toggle callbacks
- Neo-tree integration boundaries

### 2. Key Discovery Points
- The toggle callback wasn't expanding nodes
- Refresh was racing with manual operations
- Neo-tree has specific expectations about state transitions

### 3. What We Learned
- **Always trace actual execution flow** - don't assume
- **Integration points are complex** - understand the framework's expectations
- **State management is critical** - know who owns what state

## The Solution

### Remove Race Conditions
1. Don't trigger refreshes during manual operations
2. Let Neo-tree handle its own state

### Follow Neo-tree's Pattern
```lua
toggle_node = function(state)
    local node = state.tree:get_node()
    
    if not node.loaded then
        -- Just load, don't expand
        plugin:LoadVariablesData(state, node.id, callback)
    else
        -- Already loaded, toggle expansion
        if node:is_expanded() then
            node:collapse()
        else
            node:expand()
        end
        renderer.redraw(state)
    end
end
```

### Trust the Renderer
- When calling `show_nodes` with a parent_id, the renderer handles expansion
- Don't fight the framework

## Remaining Issues

1. **The duplicate ID error persists** - suggesting deeper architectural issues
2. **State synchronization** - Visual and internal state can diverge
3. **Error handling** - Errors are swallowed by the framework, making debugging difficult

## Lessons Learned

1. **Read the source code** of the framework you're integrating with
2. **Understand ownership** - Who manages expansion state? Who triggers redraws?
3. **Beware of race conditions** in async operations
4. **Log strategically** - At integration boundaries
5. **Test the actual behavior** - Not just that tests pass

## Next Steps

1. Completely rewrite toggle_node to follow Neo-tree's patterns
2. Remove all manual refresh triggers
3. Ensure state consistency between visual and internal representations
4. Add integration tests that verify actual tree behavior, not just snapshots