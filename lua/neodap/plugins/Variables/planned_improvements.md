# Variables Plugin: Planned Improvements

## Current Status
We've successfully implemented:
- ✅ Basic breadcrumb navigation structure
- ✅ Architectural separation between breadcrumb and tree
- ✅ Split window for breadcrumb display
- ✅ Proper NUI Tree integration with linenr_start
- ✅ Class factory pattern implementation

## Improvement Phases

### Phase 1: Complete Navigation Integration (High Priority)
**Goal**: Make breadcrumb navigation fully functional

#### 1.1 Fix Navigation Commands
- **Issue**: Navigation methods exist but aren't properly tested/working
- **Implementation**:
  ```lua
  -- In breadcrumb_navigation.lua:toggleNode()
  -- Currently navigates down but needs to properly update the view
  -- The filtered nodes should reflect current_path correctly
  ```
- **Testing**: Create comprehensive test that verifies content changes

#### 1.2 Navigation Feedback
- Show loading indicator when fetching child nodes
- Flash or highlight the breadcrumb when path changes
- Add status message showing current navigation action

#### 1.3 Keybinding Improvements
- Add `<Esc>` to exit breadcrumb mode
- Add `?` to show navigation help
- Consider vim-style navigation (h for up, l for down)

### Phase 2: Visual Enhancements (Medium Priority)
**Goal**: Improve readability and visual hierarchy

#### 2.1 Enhanced Breadcrumb Display
```lua
-- Example breadcrumb formats:
-- Current: "📍 Variables > Local > complexObject > nested"
-- Enhanced: "📍 Variables › 󰌾 Local › 󰆧 complexObject › 󰆧 nested"
-- With counts: "📍 Variables › 󰌾 Local (15) › 󰅪 array [25] › [5]"
```

#### 2.2 Depth Indicators
- **Color Gradient**: Deeper levels get progressively dimmer/different colors
- **Indentation Guides**: 
  ```
  ├─ level1 (depth 1)
  │ ├─ level2 (depth 2)
  │ │ └─ level3 (depth 3)
  │ │   └─ level4 (depth 4) [dimmed]
  ```
- **Depth Counter**: Show "Depth: 4" in statusline or breadcrumb

#### 2.3 Improved Variable Display
- **Type-specific Icons**: 
  - 󰅪 Arrays
  - 󰆧 Objects  
  - 󰊄 Functions
  - 󰎠 Strings
  - 󰎠 Numbers
- **Smart Truncation**: "very_long_variable_na..." → "very_long...name"
- **Value Previews**: Consistent formatting with better alignment

### Phase 3: Advanced Features (Lower Priority)
**Goal**: Power user features and polish

#### 3.1 Focus Mode
```lua
-- Show only current level + immediate parent context
-- Example: When deep in nested object:
-- ┌─ Context: complexObject.nested.data ─┐
-- │ parent: nested (Object)              │
-- ├──────────────────────────────────────┤
-- │ → items: Array[5]                    │
-- │ → metadata: Object                   │
-- │ → timestamp: 1234567890              │
-- └──────────────────────────────────────┘
```

#### 3.2 State Persistence
- Save navigation history per debug session
- Remember breadcrumb mode state
- Restore position when switching modes
- Quick bookmarks for frequently accessed paths

#### 3.3 Smart Layout
- Auto-adjust breadcrumb height for long paths
- Horizontal breadcrumb option for wide windows
- Collapsible breadcrumb (show only on hover/focus)
- Mini-map view for large structures

### Phase 4: Integration Features
**Goal**: Better integration with debugging workflow

#### 4.1 Search Within Level
- `/` already mapped but needs implementation
- Search highlights matches in current level
- Quick jump to search results

#### 4.2 Watch Integration  
- Add variable to watch from breadcrumb view
- Show watched status in tree
- Quick toggle watch with `w` key

#### 4.3 Value Editing
- Edit primitive values directly in tree
- Copy value to clipboard
- Set conditional breakpoints based on value

## Implementation Priority Order

1. **Immediate** (Complete todo #8):
   - Fix navigation commands to actually work
   - Add proper test coverage for navigation
   - Basic visual feedback

2. **Next Sprint**:
   - Enhanced breadcrumb formatting with icons
   - Depth indicators (colors)
   - Better variable preview display

3. **Future**:
   - Focus mode
   - State persistence  
   - Advanced search and integration features

## Technical Considerations

### Performance
- Lazy load child nodes only when needed
- Cache navigation paths to avoid re-fetching
- Limit preview depth to avoid slowdowns

### NUI Limitations
- Work within NUI Tree's buffer ownership model
- Use proper render() API with line offsets
- Respect non-modifiable buffer constraints

### User Experience
- Keep default mode simple (current tree view)
- Make breadcrumb mode discoverable but not intrusive
- Provide clear visual cues for current mode
- Ensure all actions have visual feedback