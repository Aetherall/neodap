# Auto-Wrapping Simplification Opportunities

This document catalogs every location in the Neodap codebase where the proposed auto-wrapping pattern (uppercase methods = auto-async) could simplify code by eliminating manual `NvimAsync.defer()` calls and direct async function invocations at vim context boundaries.

## Summary

**Total Opportunities**: 43 locations across 6 files
- **Keymap definitions**: 26 locations
- **User command callbacks**: 10 locations  
- **Telescope action callbacks**: 2 locations
- **Autocmd callbacks**: 5 locations (already using defer)

## Detailed Analysis

### 1. Playground Keymaps (`/lua/neodap/playground.lua`)

**Current Pattern** (lines 136-181):
```lua
vim.keymap.set("n", "<leader>db", function()
    nio.run(function()
        toggleBreakpoint:toggle()
    end)
end, { noremap = true, silent = true, desc = "Toggle Breakpoint" })
```

**With Auto-Wrapping**:
```lua
vim.keymap.set("n", "<leader>db", function()
    toggleBreakpoint:Toggle()  -- Uppercase = auto-wrapped
end, { noremap = true, silent = true, desc = "Toggle Breakpoint" })
```

**Locations**:
- Line 136-140: `<leader>db` → `toggleBreakpoint:Toggle()`
- Line 162-163: `<leader>du` → `stack:Up()`  
- Line 166-168: `<leader>dd` → `stack:Down()`
- Line 179-181: `<leader>dv` → Would need new auto-wrapped command method

**Benefit**: Eliminates 3 `nio.run()` wrappers, makes intent clearer

---

### 2. DebugMode Keymaps (`/lua/neodap/plugins/DebugMode/init.lua`)

**Current Pattern** (lines 172-197):
```lua
vim.keymap.set('n', '<Left>', NvimAsync.defer(function() self:navigateDown() end),
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Navigate down stack" }))
```

**With Auto-Wrapping**:
```lua
vim.keymap.set('n', '<Left>', function() self:NavigateDown() end,
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Navigate down stack" }))
```

**Locations**:
- Line 172-173: `<Left>` → `self:NavigateDown()`
- Line 174-175: `<Right>` → `self:SmartRightKey()`
- Line 176-177: `<Down>` → `self:StepOver()`
- Line 178-179: `<Up>` → `self:StepOut()`
- Line 182-183: `<CR>` → `self:JumpToCurrentFrame()`
- Line 186-187: `<Esc>` → `self:ExitDebugMode()`
- Line 188-189: `q` → `self:ExitDebugMode()`
- Line 192-193: `s` → `self:ShowStackFrameTelescope()`
- Line 196-197: `?` → `self:ShowHelp()`

**Method Mappings Needed**:
- `navigateDown()` → `NavigateDown()`
- `smartRightKey()` → `SmartRightKey()`
- `stepOver()` → `StepOver()`
- `stepOut()` → `StepOut()`
- `jumpToCurrentFrame()` → `JumpToCurrentFrame()`
- `exitDebugMode()` → `ExitDebugMode()`
- `showStackFrameTelescope()` → `ShowStackFrameTelescope()`
- `showHelp()` → `ShowHelp()`

**Benefit**: Eliminates 9 `NvimAsync.defer()` wrappers

---

### 3. FrameVariables Keymaps (`/lua/neodap/plugins/FrameVariables/init.lua`)

**Current Pattern** (lines 853-1181):
```lua
vim.keymap.set("n", "<CR>", function()
    local line = vim.api.nvim_win_get_cursor(win)[1]
    local data = line_to_data[line]
    if data then
        -- Complex async logic for expanding nodes
    end
end, opts)
```

**With Auto-Wrapping**:
```lua
vim.keymap.set("n", "<CR>", function()
    local line = vim.api.nvim_win_get_cursor(win)[1]
    local data = line_to_data[line]
    if data then
        self:ToggleExpansion(data)  -- Auto-wrapped method
    end
end, opts)
```

**Locations**:
- Line 853-875: `<CR>` → `self:ToggleExpansion(data)`
- Line 878-899: `<Space>` → `self:ToggleExpansion(data)` (duplicate)
- Line 1044-1052: `e` → `self:EnterEditMode(data)`
- Line 1055-1110: `l` → `self:EvaluateLazyVariable(data)`
- Line 1113-1122: `E` → `self:ExpandAll()`
- Line 1125-1129: `C` → `self:CollapseAll()`
- Line 1132-1139: `y` → `self:CopyValue(data)`
- Line 1145-1149: `<C-s>` (normal) → `self:SaveEdit()`
- Line 1151-1156: `<C-s>` (insert) → `self:SaveEdit()`
- Line 1159-1165: `<Esc>` → `self:CancelEdit()` or `self:CloseWindows()`

**Method Mappings Needed**:
- Extract async logic into: `ToggleExpansion()`, `EnterEditMode()`, `EvaluateLazyVariable()`, `ExpandAll()`, `CollapseAll()`, `CopyValue()`, `SaveEdit()`, `CancelEdit()`, `CloseWindows()`

**Benefit**: Eliminates inline async logic, improves organization

---

### 4. User Commands

#### DebugMode Commands (`/lua/neodap/plugins/DebugMode/init.lua`)

**Current Pattern** (lines 74-88):
```lua
vim.api.nvim_create_user_command("NeodapDebugModeEnter", function()
    self:enterDebugMode()
end, { desc = "Enter Neodap debug mode" })
```

**With Auto-Wrapping**:
```lua
vim.api.nvim_create_user_command("NeodapDebugModeEnter", function()
    self:EnterDebugMode()  -- Auto-wrapped
end, { desc = "Enter Neodap debug mode" })
```

**Locations**:
- Line 74-76: `NeodapDebugModeEnter` → `self:EnterDebugMode()`
- Line 78-80: `NeodapDebugModeExit` → `self:ExitDebugMode()`
- Line 82-88: `NeodapDebugModeToggle` → `self:ToggleDebugMode()`

#### FrameVariables Commands (`/lua/neodap/plugins/FrameVariables/init.lua`)

**Locations**:
- Line 232-238: `NeodapVariables` → Would need auto-wrapped command method
- Line 1194: `NeodapVariablesFloat` → `self:CreateVariablesTree()`

#### StackFrameTelescope Commands (`/lua/neodap/plugins/StackFrameTelescope/init.lua`)

**Locations**:
- Line 49-51: `NeodapStackFrameTelescope` → `self:ShowFramePicker()`

**Benefit**: Simplifies 6 user command callbacks

---

### 5. Telescope Action Callbacks (`/lua/neodap/plugins/StackFrameTelescope/init.lua`)

**Current Pattern** (lines 99-106, 324-340):
```lua
actions.select_default:replace(function()
    local selection = action_state.get_selected_entry()
    actions.close(prompt_bufnr)
    
    if selection and selection.frame then
        self:jump_to_frame(selection.frame)  -- Calls NvimAsync.run internally
    end
end)
```

**With Auto-Wrapping**:
```lua
actions.select_default:replace(function()
    local selection = action_state.get_selected_entry()
    actions.close(prompt_bufnr)
    
    if selection and selection.frame then
        self:JumpToFrame(selection.frame)  -- Auto-wrapped
    end
end)
```

**Locations**:
- Line 99-106: `actions.select_default:replace` → `self:JumpToFrame(frame)`
- Line 324-340: `jump_to_frame()` method → `JumpToFrame()` method

**Method Mappings Needed**:
- `jump_to_frame()` → `JumpToFrame()`

**Benefit**: Eliminates 2 manual `NvimAsync.run()` calls

---

### 6. Autocmd Callbacks (Already Fixed with defer)

These are already properly handled with `NvimAsync.defer()` but could be simplified with auto-wrapping:

#### FrameHighlight (`/lua/neodap/plugins/FrameHighlight/init.lua`)
- Line 156-158: `BufEnter/BufWinEnter/BufReadPost` → `self:HighlightAllVisibleLocations()`

#### ScopeViewer (`/lua/neodap/plugins/ScopeViewer/init.lua`)
- Line 112-114: `NeodapStackNavigationChanged` → `self:OnNavigationChanged()`
- Line 122-124: `CursorMoved` → `self:OnGlobalCursorMoved()`
- Line 133-135: `NeodapDebugOverlayLeftSelect` → `self:OnPanelSelect()`
- Line 144-146: `NeodapDebugOverlayLeftToggle` → `self:OnPanelToggle()`

#### CallStackViewer (3 autocmds, similar pattern)

**Benefit**: Would eliminate 5 `NvimAsync.defer()` calls

---

## Implementation Plan

### Phase 1: Add Auto-Wrapping to Class()
1. Enhance `Class()` in `/lua/neodap/tools/class.lua` to detect uppercase methods
2. Auto-wrap uppercase methods with `NvimAsync.defer()` equivalent
3. Add validation to prevent misuse

### Phase 2: Method Mappings
For each plugin, add uppercase versions of async methods:

```lua
-- DebugMode example
function DebugMode:navigateDown() 
    -- existing logic
end

function DebugMode:NavigateDown()  -- Auto-wrapped version
    return self:navigateDown()
end
```

### Phase 3: Update Call Sites
Replace all identified locations:
- Remove `NvimAsync.defer()` wrappers
- Remove `nio.run()` wrappers
- Change method calls to uppercase versions

### Phase 4: Validation
- Ensure all async operations work correctly
- Test boundary conditions
- Verify no performance regressions

## Expected Benefits

1. **Code Clarity**: Eliminate manual wrapping boilerplate
2. **Consistency**: Uniform pattern across all vim boundaries
3. **Maintainability**: Fewer places to remember manual wrapping
4. **Developer Experience**: Clearer intent with case conventions

## Risk Assessment

1. **Magic Behavior**: Auto-wrapping may surprise developers
2. **Debugging Complexity**: Stack traces may be less clear
3. **API Consistency**: Mixed case conventions may confuse
4. **Testing Overhead**: Need to test both sync and async contexts

---

*This analysis provides a comprehensive roadmap for implementing auto-wrapping across the entire Neodap codebase, with specific locations and expected benefits clearly documented.*