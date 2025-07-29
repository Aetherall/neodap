# DebugTree State Tree Refactoring V2: The Pragmatic Approach

## The Revelation

After deep analysis of NUI Tree's code, we discovered:
1. NUI Tree stores nodes as simple table references in `self.nodes.by_id`
2. Multiple NUI Trees CAN share the same nodes table
3. The "buffer requirement" is trivial - just one scratch buffer
4. There's ZERO overhead if we don't call render()

## The Current Waste

We're maintaining 100+ lines of custom tree code that's just a worse version of NUI Tree:
- Custom add_node (40 lines)
- Custom remove_node (35 lines) 
- Custom _processPendingNodes (25 lines) - suggests we have bugs!
- Custom render method

## The Simple Solution

```lua
-- State tree: Real NUI Tree with scratch buffer
local state_bufnr = vim.api.nvim_create_buf(false, true)
self.state_tree = NuiTree({ bufnr = state_bufnr, nodes = {} })

-- View trees: Share the nodes structure
view_tree = NuiTree({ bufnr = popup.bufnr, nodes = {} })
view_tree.nodes = self.state_tree.nodes  -- Share the entire structure!
```

## Implementation Plan

1. Replace custom state tree with NUI Tree
2. Keep the node sharing mechanism
3. Remove all custom tree management code
4. Fix the pending nodes issue properly

## Benefits

- Remove 100+ lines of buggy code
- Get battle-tested tree operations
- Maintain the elegant shared node architecture
- Better debugging (can actually render state tree if needed)