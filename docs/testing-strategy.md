# Neodap Testing Strategy: External Behavior Testing

## Overview

This document outlines Neodap's testing strategy focused on **external behavior testing** - testing plugins as users would interact with them, rather than testing internal implementation details. This approach makes tests more maintainable, intuitive to write, and resilient to internal refactoring.

## Core Philosophy

### Traditional Testing (Internal)
```lua
-- Tests internal API and state
local breakpoint = breakpointManager:addBreakpoint(location)
Test.assert.equals(breakpoint.location.line, 3)
Test.assert.equals(debugMode.is_active, true)
```

### External Behavior Testing (Preferred)
```lua
-- Tests what users actually see and do
vim.cmd("NeodapBreakpointToggle")
Test.TerminalSnapshot("breakpoint_visible")
Test.CommandSequence({"NeodapDebugModeEnter", "NeodapStepOver"})
```

## Key Principles

1. **Test Observable Behavior**: Focus on what users see - buffer content, messages, cursor position, window states
2. **Use Public Surface**: Test commands, public methods, and user-facing APIs only
3. **No Magic Assertions**: Every check should be explicit and verifiable
4. **Survival of Refactoring**: Tests should pass even when internal implementation changes
5. **Documentation Value**: Tests should read like usage examples

## Testing Approaches

### 1. Terminal Snapshots (Text-Based Screenshots)

Capture the entire terminal state as text, making visual testing version-control friendly.

#### Basic Usage
```lua
Test.It("debug_mode_ui_appears", function()
  vim.cmd("edit spec/fixtures/recurse.js")
  vim.api.nvim_win_set_cursor(0, {3, 0})
  vim.cmd("NeodapBreakpointToggle")
  vim.cmd("NeodapStart")
  
  -- Wait for breakpoint hit
  Test.WaitFor("thread_stopped")
  
  -- Capture what the user sees
  Test.TerminalSnapshot("debug_mode_active")
  
  -- Step over
  vim.cmd("NeodapStepOver")
  
  -- Capture new state
  Test.TerminalSnapshot("after_step_over")
end)
```

#### Terminal Snapshot Format
```
-- spec/terminal_snapshots/debug_mode_active.golden
TERMINAL SNAPSHOT: debug_mode_active
Size: 24x80
Cursor: [12, 5]
Mode: n

┌─────────────────────────────────────────────────────────────────────────────┐
│  1 │ let i = 0;                                                             │
│  2 │ setInterval(() => {                                                    │
│  3 │   ◐console.log("ALoop iteration: ", i++);                             │
│  4 │   console.log("BLoop iteration: ", i++);                              │
│  5 │ }, 1000)                                                               │
│  6 │                                                                        │
│  7 │                                                                        │
│  8 │ -- DEBUG --                                                            │
│  9 │                                                                        │
│ 10 │ ┌─ Variables ───────────────────────────────────────────────────────┐ │
│ 11 │ │ Local:                                                             │ │
│ 12 │ │   i: 0                                                            │ │
│ 13 │ │   arguments: []                                                    │ │
│ 14 │ │                                                                    │ │
│ 15 │ │ Global:                                                            │ │
│ 16 │ │   setInterval: function                                            │ │
│ 17 │ │   console: object                                                  │ │
│ 18 │ └────────────────────────────────────────────────────────────────────┘ │
│ 19 │                                                                        │
│ 20 │ [DEBUG] Frame 1/3 - recurse.js:3:2                                    │
│ 21 │ Press ? for help                                                       │
│ 22 │                                                                        │
│ 23 │ :                                                                      │
│ 24 │                                                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Implementation
```lua
-- Capture the entire terminal screen as text
function Test.TerminalSnapshot(name)
  local screen = {
    lines = {},
    cursor = vim.api.nvim_win_get_cursor(0),
    mode = vim.api.nvim_get_mode().mode,
    size = {vim.o.lines, vim.o.columns}
  }
  
  -- Capture each line of the terminal
  for row = 1, vim.o.lines do
    local line = ""
    for col = 1, vim.o.columns do
      local char = vim.fn.screenchar(row, col)
      if char == 0 then
        line = line .. " "
      else
        line = line .. vim.fn.nr2char(char)
      end
    end
    table.insert(screen.lines, line)
  end
  
  -- Save and compare with golden snapshot
  save_and_compare_snapshot(name, screen)
end
```

### 2. Session Recording & Replay

Record actual usage sessions and replay them as tests.

#### Recording a Session
```lua
-- Plugin author records a session once
Test.RecordSession("debug_workflow", function()
  -- Just use the plugin normally
  vim.cmd("edit spec/fixtures/recurse.js")
  vim.cmd("NeodapStart")
  vim.api.nvim_win_set_cursor(0, {3, 0})
  vim.cmd("NeodapBreakpointToggle")
  -- Wait for hit...
  vim.cmd("NeodapStepOver")
  vim.cmd("NeodapStepOver")
  vim.cmd("NeodapStop")
end)
```

#### Replaying as Test
```lua
-- Test just replays the session
Test.It("debug_workflow_still_works", function()
  Test.ReplaySession("debug_workflow")
  -- Framework automatically detects if anything broke
end)
```

#### Generated Recording Format
```lua
-- recordings/debug_workflow.lua
return {
  name = "debug_workflow",
  steps = {
    {
      type = "command",
      command = "edit spec/fixtures/recurse.js",
      timestamp = 0
    },
    {
      type = "cursor_move", 
      position = {3, 0},
      timestamp = 100
    },
    {
      type = "command",
      command = "NeodapBreakpointToggle",
      timestamp = 200
    },
    {
      type = "buffer_snapshot",
      bufnr = 1,
      content = "let i = 0;\nsetInterval(() => {\n  ◐console.log(\"ALoop iteration: \", i++);  // ◄ vt:◐\n  console.log(\"BLoop iteration: \", i++);",
      timestamp = 300
    },
    {
      type = "wait_for_event",
      event = "thread_stopped",
      timeout = 5000,
      timestamp = 500
    },
    -- ... more steps
  }
}
```

### 3. Command Sequence Testing

Test workflows through command sequences.

```lua
Test.It("debug_mode_commands", function()
  Test.StartWith("spec/fixtures/recurse.js")
  
  Test.CommandSequence({
    "NeodapStart",
    {"cursor", {3, 0}},
    "NeodapBreakpointToggle",
    {"wait", "thread_stopped"},
    "NeodapDebugModeEnter",
    "NeodapStepOver",
    "NeodapStepOver",
    "NeodapDebugModeExit",
    "NeodapStop"
  })
  
  -- If any command fails, test fails
  -- Framework tracks all state changes automatically
end)
```

### 4. Before/After Buffer Testing

Show explicit before and after states.

```lua
Test.It("breakpoint_toggle_works", function()
  Test.WithBuffer("spec/fixtures/recurse.js", function()
    Test.Before([[
let i = 0;
setInterval(() => {
  console.log("ALoop iteration: ", i++);
  console.log("BLoop iteration: ", i++);
}, 1000)
    ]])
    
    -- Cursor on line 3
    vim.api.nvim_win_set_cursor(0, {3, 0})
    vim.cmd("NeodapBreakpointToggle")
    
    Test.After([[
let i = 0;
setInterval(() => {
  ◐console.log("ALoop iteration: ", i++);  // ◄ vt:◐
  console.log("BLoop iteration: ", i++);
}, 1000)
    ]])
  end)
end)
```

### 5. Focused Region Snapshots

Capture specific areas of the terminal for focused testing.

```lua
-- Capture only the variables floating window
function Test.RegionSnapshot(name, region)
  local screen = {}
  
  -- Capture only specified region
  for row = region.start_row, region.end_row do
    local line = ""
    for col = region.start_col, region.end_col do
      local char = vim.fn.screenchar(row, col)
      line = line .. (char == 0 and " " or vim.fn.nr2char(char))
    end
    table.insert(screen, line)
  end
  
  save_region_snapshot(name, screen, region)
end

-- Usage: Only capture the floating window area
Test.RegionSnapshot("variables_float", {
  start_row = 10, end_row = 18,
  start_col = 5, end_col = 70
})
```

## Testing Framework Components

### Helper Functions
```lua
-- Wait for specific events
function Test.WaitFor(event_name, timeout)
  -- Wait for DAP events, UI updates, etc.
end

-- Send key sequences
function Test.SendKeys(keys)
  -- Simulate user keystrokes
end

-- Run command with error handling
function Test.RunCommand(cmd)
  local success, error = pcall(vim.cmd, cmd)
  if not success then
    error("Command failed: " .. cmd .. " - " .. error)
  end
end

-- Capture vim messages
function Test.CaptureMessages()
  return vim.api.nvim_exec("messages", true)
end

-- Check if floating windows exist
function Test.FindFloatingWindows()
  local floats = {}
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    local config = vim.api.nvim_win_get_config(winid)
    if config.relative ~= "" then
      table.insert(floats, winid)
    end
  end
  return floats
end
```

### Auto-Detection Features
```lua
-- Automatically detect interesting UI areas
function Test.AutoSnapshot(name)
  local areas = detect_ui_areas()
  
  for area_name, bounds in pairs(areas) do
    Test.RegionSnapshot(name .. "_" .. area_name, bounds)
  end
end

function detect_ui_areas()
  local areas = {}
  
  -- Detect floating windows
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    local config = vim.api.nvim_win_get_config(winid)
    if config.relative ~= "" then
      areas["float_" .. winid] = {
        start_row = config.row,
        end_row = config.row + config.height,
        start_col = config.col,
        end_col = config.col + config.width
      }
    end
  end
  
  -- Detect status line, command line, etc.
  return areas
end
```

## Plugin Testing Examples

### BreakpointApi Plugin
```lua
Test.Describe("BreakpointApi Plugin", function()
  Test.It("can_toggle_breakpoint_with_command", function()
    vim.cmd("edit spec/fixtures/recurse.js")
    vim.api.nvim_win_set_cursor(0, {3, 0})
    
    Test.RunCommand("NeodapBreakpointToggle")
    
    -- Verify through buffer snapshot
    Test.expectBufferSnapshot(bufnr, [[
let i = 0;
setInterval(() => {
  ◐console.log("ALoop iteration: ", i++);  // ◄ vt:◐
  console.log("BLoop iteration: ", i++);
}, 1000)
    ]])
  end)
  
  Test.It("breakpoint_actually_stops_execution", function()
    vim.cmd("edit spec/fixtures/recurse.js")
    vim.api.nvim_win_set_cursor(0, {3, 0})
    vim.cmd("NeodapBreakpointToggle")
    vim.cmd("NeodapStart")
    
    Test.WaitFor("thread_stopped")
    Test.TerminalSnapshot("stopped_at_breakpoint")
  end)
end)
```

### DebugMode Plugin
```lua
Test.Describe("DebugMode Plugin", function()
  Test.It("activates_on_thread_stop", function()
    vim.cmd("edit spec/fixtures/recurse.js")
    vim.api.nvim_win_set_cursor(0, {3, 0})
    vim.cmd("NeodapBreakpointToggle")
    vim.cmd("NeodapStart")
    
    Test.WaitFor("thread_stopped")
    
    -- Verify debug mode message appears
    local messages = Test.CaptureMessages()
    Test.assert.contains(messages, "-- DEBUG --")
    
    -- Verify arrow keys work differently
    Test.SendKeys("<Down>")  -- Should step, not move cursor
    Test.TerminalSnapshot("after_step_over")
  end)
  
  Test.It("commands_work_correctly", function()
    vim.cmd("edit spec/fixtures/recurse.js")
    
    Test.RunCommand("NeodapDebugModeEnter")
    Test.TerminalSnapshot("debug_mode_entered")
    
    Test.RunCommand("NeodapDebugModeExit")
    Test.TerminalSnapshot("debug_mode_exited")
  end)
end)
```

## Benefits of This Approach

### For Plugin Authors
- **Intuitive**: Write tests like you use the plugin
- **Documentation**: Tests serve as usage examples
- **Maintainable**: Tests survive internal refactoring
- **Visual**: See exactly what users see

### For the Framework
- **Version Control Friendly**: Text-based snapshots diff well in git
- **Comprehensive**: Catches visual regressions and UX issues
- **Debuggable**: Clear diff output when tests fail
- **Portable**: Works across different terminals and systems

### For Users
- **Confidence**: Tests verify the actual user experience
- **Examples**: Tests show how to use plugins
- **Reliability**: External behavior testing catches more real-world issues

## Implementation Plan

1. **Phase 1**: Implement `Test.TerminalSnapshot()` and basic diff functionality
2. **Phase 2**: Add session recording and replay capabilities
3. **Phase 3**: Build command sequence testing framework
4. **Phase 4**: Create focused region snapshots and auto-detection
5. **Phase 5**: Integrate with existing buffer snapshot system
6. **Phase 6**: Add comprehensive helper functions and utilities

This approach transforms testing from complex internal verification to simple demonstration of plugin functionality, making tests more valuable for both development and documentation.