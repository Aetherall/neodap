# Variables Plugin Test Suite

This directory contains comprehensive tests for the Variables plugin's breadcrumb navigation functionality.

## Test Files

### `breadcrumb_test.spec.lua` - Core Navigation Test
**Purpose**: Demonstrates the fundamental breadcrumb navigation features
**Key Features Tested**:
- Mode switching (normal ↔ breadcrumb)
- Navigate down into scopes and variables
- Navigate up one level (`u`)
- Navigate back to previous location (`b`)
- Navigate to root (`r`)
- Tree filtering based on current path

**Expected Behavior**:
- `02_breadcrumb_mode_shows_scopes`: Shows "📍 Variables" with Local and Global scopes
- `03_breadcrumb_inside_local_scope`: Shows "📍 Variables > Local" with only Local variables
- `04_breadcrumb_inside_complex_object`: Shows "📍 Variables > Local > complexObject" with only object properties
- Navigation commands properly update both breadcrumb text and tree content

### `navigation_demo.spec.lua` - Simple Navigation Demo
**Purpose**: Clean demonstration that navigation actually filters tree content
**Key Focus**: Visual proof that breadcrumb mode shows different content than normal mode

**Expected Behavior**:
- Clear contrast between normal mode (shows all scopes) and breadcrumb mode (shows filtered content)
- Breadcrumb text updates to reflect current path
- Tree content changes based on navigation

### `breadcrumb_navigation_complete.spec.lua` - Comprehensive Test
**Purpose**: Exhaustive test of all navigation features
**Features Tested**:
- All basic navigation commands
- Quick segment jumping (`1-9`)
- Deep navigation paths
- Array navigation
- Different scope types (Local, Global)
- State persistence when switching modes
- Edge cases and complex navigation patterns

**Expected Behavior**:
- 17 distinct snapshots showing progression through complex navigation
- Breadcrumb text accurately reflects navigation path
- Tree always shows appropriate filtered content
- All navigation commands work correctly

## Visual Verification Guidelines

When reviewing test snapshots, verify:

1. **Breadcrumb Text Accuracy**:
   ```
   📍 Variables                    (at root)
   📍 Variables > Local           (in Local scope)
   📍 Variables > Local > obj     (in object)
   ```

2. **Tree Content Filtering**:
   - Root: Shows both Local and Global scopes
   - Local scope: Shows only variables in Local scope
   - Object: Shows only object properties
   - Array: Shows only array elements

3. **Navigation Commands**:
   - `<CR>` or `o`: Navigate down into selected node
   - `u` or `<BS>`: Go up one level
   - `b`: Go back to previous location
   - `r`: Return to root
   - `1-9`: Jump to breadcrumb segment
   - `B`: Toggle back to normal mode

4. **Visual Consistency**:
   - Breadcrumb always on lines 1-2
   - Tree content starts at line 3
   - No duplication or rendering artifacts
   - Proper indentation and icons

## Running Tests

To run individual tests:
```bash
# Core navigation test
nvim -c "lua require('plenary.busted').run('lua/neodap/plugins/Variables/specs/breadcrumb_test.spec.lua')"

# Simple demo
nvim -c "lua require('plenary.busted').run('lua/neodap/plugins/Variables/specs/navigation_demo.spec.lua')"

# Comprehensive test
nvim -c "lua require('plenary.busted').run('lua/neodap/plugins/Variables/specs/breadcrumb_navigation_complete.spec.lua')"
```

## Troubleshooting

If tests fail:
1. Check that debug session starts properly (2s wait should be sufficient)
2. Verify Variables window opens in correct position
3. Ensure keybindings are properly set up in breadcrumb mode
4. Check that navigation commands update both breadcrumb text and tree content

## Expected Output Format

Each snapshot should show:
```
 1| 📍 Variables > Local > complexObject
 2| ────────────────────────────────────
 3|   ▸ level1: Object
 4|   ▸ description: "Root level"
 5| ~
```

The breadcrumb line (1) and separator (2) should always be present in breadcrumb mode, with tree content starting at line 3.