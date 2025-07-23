# Breadcrumb-Based Navigation Approaches for Variables Tree

## Core Concept
Instead of showing the entire tree with deep indentation, show:
1. Current location as a breadcrumb trail
2. Only the immediate context (current level + children)
3. Navigation controls to move up/down the hierarchy

## Variation 1: Classic Breadcrumb with Focused View

```
┌─Variables────────────────────────────────────────────────────┐
│ 📍 Local > complexObject > level1 > nested1 > nested2        │
├──────────────────────────────────────────────────────────────┤
│ ▾ 󰆩 nested2                                                  │
│ ├─▾ 󰅪 array [10, 20, 30, 40, 50]                            │
│ │ ├─ [0]: 10                                                 │
│ │ ├─ [1]: 20                                                 │
│ │ ├─ [2]: 30                                                 │
│ │ ├─ [3]: 40                                                 │
│ │ └─ [4]: 50                                                 │
│ └─▸ 󰆩 nested3 {properties: {...}, nested4: {...}}           │
└──────────────────────────────────────────────────────────────┘
```

**Features:**
- Clickable breadcrumb segments for quick navigation
- Clean, uncluttered view of current level
- No horizontal scrolling needed

## Variation 2: Breadcrumb with Parent Context

```
┌─Variables────────────────────────────────────────────────────┐
│ Local > complexObject > level1 > nested1 > nested2           │
├──────────────────────────────────────────────────────────────┤
│ ↑ 󰆩 nested1 (parent)                                         │
│   ├─ 󰀫 info: 'Level 2 info'                                  │
│   └▾ 󰆩 nested2 ← YOU ARE HERE                                │
│     ├▾ 󰅪 array [10, 20, 30, 40, 50]                          │
│     │ ├─ [0]: 10                                             │
│     │ ├─ [1]: 20                                             │
│     │ └─ ... 3 more                                          │
│     └▸ 󰆩 nested3 {properties: {...}, nested4: {...}}         │
└──────────────────────────────────────────────────────────────┘
```

**Features:**
- Shows immediate parent for context
- Visual indicator of current position
- Maintains some tree structure

## Variation 3: Breadcrumb with Sibling Awareness

```
┌─Variables────────────────────────────────────────────────────┐
│ 🏠 Local > 📁 complexObject > 📁 level1 > 📁 nested1         │
├──────────────────────────────────────────────────────────────┤
│ Siblings at this level:                                      │
│ [•] info                                                     │
│ [▾] nested2 ← current                                        │
├──────────────────────────────────────────────────────────────┤
│ ▾ 󰆩 nested2                                                  │
│ ├─▾ 󰅪 array [5 items]                                       │
│ │ └─ (items hidden for clarity)                             │
│ └─▸ 󰆩 nested3 {2 properties}                                │
└──────────────────────────────────────────────────────────────┘
```

**Features:**
- Quick sibling navigation
- Awareness of parallel structures
- Compact sibling list

## Variation 4: Floating Breadcrumb HUD

```
╭─── Local › complexObject › level1 › nested1 › nested2 ──────╮
│ Press ‹b› for breadcrumb menu, ‹u› to go up                 │
╰──────────────────────────────────────────────────────────────╯

▾ 󰆩 nested2
├─▾ 󰅪 array [10, 20, 30, 40, 50]
│ ├─ [0]: 10
│ ├─ [1]: 20
│ ├─ [2]: 30
│ ├─ [3]: 40
│ └─ [4]: 50
└─▸ 󰆩 nested3 {properties: {...}, nested4: {...}}
```

**Features:**
- Non-intrusive overlay
- Keyboard shortcuts for navigation
- Appears/disappears on demand

## Variation 5: Split View - Breadcrumb + Full Tree

```
┌─Path─────────────────┬─Current Level──────────────────────┐
│ Local                │ ▾ 󰆩 nested2                        │
│ └ complexObject      │ ├─▾ 󰅪 array [10, 20, 30, 40, 50]  │
│   └ level1           │ │ ├─ [0]: 10                       │
│     └ nested1        │ │ ├─ [1]: 20                       │
│       └ nested2 •    │ │ ├─ [2]: 30                       │
│         └ nested3    │ │ ├─ [3]: 40                       │
│           └ nested4  │ │ └─ [4]: 50                       │
│             └ nested5│ └─▸ 󰆩 nested3 {properties: {...}} │
└──────────────────────┴────────────────────────────────────┘
```

**Features:**
- Path overview in sidebar
- Full tree context available
- Two-panel navigation

## Variation 6: Inline Breadcrumb (Telescope-style)

```
> Local > complexObject > level1 > nested1 > nested2
  ─────────────────────────────────────────────────
  array: [10, 20, 30, 40, 50]
    [0]: 10
    [1]: 20
    [2]: 30
    [3]: 40
    [4]: 50
  nested3: {properties: {...}, nested4: {...}}
```

**Features:**
- Minimal chrome
- Telescope/FZF-like interface
- Keyboard-driven navigation

## Variation 7: Smart Breadcrumb with Preview

```
┌─Variables────────────────────────────────────────────────────┐
│ Local > complexObject > ... > nested2  [5/7 levels]         │
├──────────────────────────────────────────────────────────────┤
│ ▾ 󰆩 nested2                                                  │
│ ├─▾ 󰅪 array [10, 20, 30, 40, 50]                            │
│ └─▸ 󰆩 nested3 ─┬─ preview ─────────────┐                    │
│                 │ properties:           │                    │
│                 │   type: 'deep'        │                    │
│                 │   count: 42           │                    │
│                 │ nested4: {...}        │                    │
│                 └───────────────────────┘                    │
└──────────────────────────────────────────────────────────────┘
```

**Features:**
- Hover previews for collapsed nodes
- Depth indicator
- Path compression for very deep trees

## Implementation Approaches

### A. Pure UI Overlay
- Add breadcrumb as a separate UI element
- Keep existing tree structure
- Toggle between full tree and focused view

### B. Modified Tree Rendering
- Integrate breadcrumb into tree buffer
- Filter tree nodes based on current path
- Smooth transitions between levels

### C. Hybrid Navigation
- Breadcrumb for deep navigation
- Traditional tree for shallow levels (< 4 deep)
- Automatic mode switching

## Interaction Patterns

### Keyboard Navigation
- `b` - Toggle breadcrumb mode
- `u` - Go up one level
- `<BS>` - Navigate to parent
- `1-9` - Jump to breadcrumb segment
- `/` - Search within current level
- `g/` - Global search (all levels)

### Mouse Navigation
- Click breadcrumb segments
- Double-click to expand inline
- Right-click for context menu
- Hover for previews

### Smart Navigation
- Auto-collapse siblings when diving deep
- Remember expansion state per path
- Quick jump to recently visited paths
- Bookmarks for important nodes

## Benefits of Breadcrumb Approach

1. **Constant Context** - Always know where you are
2. **No Horizontal Scroll** - Content always fits
3. **Quick Navigation** - Jump to any ancestor instantly
4. **Clean View** - See relevant data without clutter
5. **Scalable** - Works at any depth
6. **Familiar Pattern** - Users know breadcrumbs from file explorers

## Recommended Implementation Path

1. **Phase 1**: Basic breadcrumb display (Variation 1)
   - Show path at top
   - Filter tree to current level only
   - Basic up/down navigation

2. **Phase 2**: Enhanced navigation (Variation 2/3)
   - Add parent context
   - Sibling awareness
   - Keyboard shortcuts

3. **Phase 3**: Advanced features
   - Previews
   - Search integration
   - Bookmarks/history

The breadcrumb approach fundamentally solves the deep nesting problem by changing from "show everything with indentation" to "show where you are and what's immediately relevant".