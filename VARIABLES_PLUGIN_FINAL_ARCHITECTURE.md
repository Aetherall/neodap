# Variables Plugin - Final Viewport Architecture

## Overview

The Variables plugin has been completely transformed from a dual-mode system to a unified viewport-based architecture. This document describes the final implementation.

## Core Concept

The plugin now operates on a single principle: **"A tree with a moveable viewport"**

Instead of switching between modes, users navigate by moving their viewport through the complete variable tree. This creates a consistent, intuitive experience that scales from simple variable inspection to deep object exploration.

## Architecture Components

### 1. Main Plugin (`init.lua`) - 487 lines
The core plugin that:
- Manages DAP integration and event handling
- Builds complete tree structures from debug data
- Renders tree through viewport system
- Handles all user interactions

Key features:
- Single rendering pipeline via `RenderWithViewport()`
- Unified keybindings for viewport navigation
- No mode switching - viewport is always active

### 2. Viewport System (`viewport_system.lua`) - 365 lines
Pure geometric calculations for viewport logic:
- Path management and comparison
- Distance calculations between nodes
- Relationship determination (ancestor/descendant/sibling)
- History navigation support

### 3. Viewport Renderer (`viewport_renderer.lua`) - 290 lines
Converts geometric relationships to visual representation:
- Node filtering based on viewport radius
- Multiple style modes (contextual/minimal/full/highlight)
- Breadcrumb header generation
- Consistent visual formatting

### 4. Visual Improvements (`visual_improvements.lua`) - 351 lines
Enhanced visual formatting:
- Type-specific icons
- Smart value truncation
- Tree guides and connectors
- Syntax highlighting

### 5. ID Generator (`id_generator.lua`) - 78 lines
Hierarchical ID generation for unique node identification

## Key Commands

### Navigation
- `<CR>` / `o` - Navigate into selected node (move viewport deeper)
- `u` / `<BS>` - Go up one level
- `b` - Go back in history
- `r` - Go to root

### Viewport Control
- `+` - Increase viewport radius (see more context)
- `-` - Decrease viewport radius (focus view)
- `s` - Cycle viewport style
- `q` - Close window

### Commands
- `:VariablesShow` - Open variables window
- `:VariablesToggle` - Toggle window
- `:VariablesViewport status` - Show current viewport location
- `:VariablesViewport reset` - Reset to root view

## Viewport Styles

1. **Contextual** (default) - Shows focused path with geometric hints
2. **Minimal** - Clean view with minimal decoration
3. **Full** - Complete paths for all nodes
4. **Highlight** - Emphasized focus node

## Implementation Highlights

### Complete Tree Building
The plugin builds a complete tree structure on demand:
```lua
function VariablesTreeNui:BuildCompleteTree()
  -- Recursively builds entire variable tree
  -- Lazy-loads children as needed
  -- Maintains DAP references for updates
end
```

### Geometric Rendering
Instead of semantic roles, nodes are rendered based on geometry:
```lua
-- Old approach: "parent-context", "sibling-context", etc.
-- New approach: Pure spatial relationships
relationship = ViewportSystem.determineRelationship(node_path, focus_path)
-- Returns: "ancestor", "descendant", "sibling", "focus", etc.
```

### Unified Navigation
All navigation is viewport movement:
```lua
function VariablesTreeNui:NavigateViewport(action, current_node)
  -- "enter" - Move viewport to node's path
  -- "up" - Shorten viewport path
  -- "back" - Restore previous viewport location
  -- "root" - Reset viewport to root
end
```

## Benefits of Final Architecture

1. **Conceptual Simplicity**: One mental model - viewport movement
2. **Code Reduction**: ~30% less code than original dual-mode system
3. **Maintainability**: Clear separation between geometry and rendering
4. **Extensibility**: Easy to add new viewport styles or navigation features
5. **Performance**: Single rendering pipeline, efficient tree traversal
6. **User Experience**: Consistent navigation without mode confusion

## Migration from Old System

The transformation included:
- Removed `breadcrumb_navigation.lua` (672 lines)
- Removed `viewport_integration.lua` (411 lines)
- Removed all mode switching logic
- Unified all navigation under viewport paradigm

Total reduction: ~1,083 lines removed, replaced with cleaner viewport implementation.

## Future Enhancements

The viewport architecture enables:
- Animation between viewport positions
- Multiple viewports (split views)
- Viewport bookmarks
- Smart viewport positioning based on search
- Visual viewport indicators
- Smooth scrolling transitions

## Conclusion

The Variables plugin now embodies the principle: **"Make the simple case simple, and the complex case possible."**

By reconceptualizing tree navigation as viewport movement, we've created a system that's both more powerful and easier to understand than the original implementation.