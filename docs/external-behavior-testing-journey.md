# The Journey to External Behavior Testing in Neodap

## Executive Summary

This document chronicles the development of a revolutionary testing approach for neodap plugins that fundamentally shifts from testing internal implementation details to testing actual user experience. We successfully implemented a **terminal snapshot system** that captures text-based "screenshots" of vim buffer content, enabling visual verification of plugin behavior in a version-control-friendly format.

## The Problem: Traditional Testing Limitations

### What We Started With
Traditional neodap testing focused on internal APIs and state verification:

```lua
-- ❌ Traditional approach - testing internals
local breakpoint = breakpointManager:addBreakpoint(location)
Test.assert.equals(breakpoint.location.line, 3)
Test.assert.equals(debugMode.is_active, true)
```

### Why This Wasn't Enough
1. **Not explicit**: Tests could pass even if user-visible functionality was broken
2. **Complex for plugin developers**: Required deep knowledge of internal APIs
3. **Fragile**: Tests broke with internal refactoring
4. **No visual verification**: Couldn't verify that breakpoint markers, UI elements, or visual feedback actually appeared

### The Vision
We needed a way to test plugins **as users interact with them** - through commands, keymaps, and visual feedback. The goal was to make testing feel like demonstrating plugin functionality rather than probing internal state.

## The Breakthrough: Terminal Snapshots

### The Key Insight
Instead of testing *what the code does*, we decided to test *what the user sees*. This led to the revolutionary idea of **text-based terminal screenshots**.

### The Technical Challenge
How do you capture visual elements (extmarks, signs, virtual text) in a way that:
- Works in headless mode (no graphics)
- Is version-control friendly (text, not images)
- Shows actual user-visible changes
- Can be embedded in test files for self-contained tests

### The Solution: `vim.fn.screenchar()`
We discovered that `vim.fn.screenchar(row, col)` captures the actual rendered characters on the terminal screen, including all visual elements that users see.

```lua
-- Capture the entire terminal screen as text
local function capture_screen()
  vim.cmd("redraw")  -- Force redraw to ensure current state
  vim.cmd("redraw!")
  
  local screen = { lines = {} }
  
  for row = 1, vim.o.lines do
    local line = ""
    for col = 1, vim.o.columns do
      local char = vim.fn.screenchar(row, col)
      line = line .. (char == 0 and " " or vim.fn.nr2char(char))
    end
    table.insert(screen.lines, line:gsub("%s+$", ""))
  end
  
  return screen
end
```

## Implementation Journey

### Phase 1: Proving the Concept
We started with a simple test using `make run` to validate that `vim.fn.screenchar()` could capture visual elements in headless mode.

```bash
echo 'print(vim.fn.screenchar(1, 1))' | make run
```

This confirmed that screen functions worked in our testing environment.

### Phase 2: Self-Contained Architecture
Rather than external snapshot files, we decided to embed snapshots directly in test files. This eliminated dependencies and made tests completely self-contained.

```lua
--[[ TERMINAL SNAPSHOT: after_breakpoint
Size: 24x80
Cursor: [3, 0]
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3| ●       console.log("ALoop iteration: ", i++);
 4|         console.log("BLoop iteration: ", i++);
 5| }, 1000)
]]
```

### Phase 3: The Timing Discovery
Initial tests showed empty screens or test output instead of vim buffer content. The breakthrough came when we realized async plugins need time to process:

```lua
toggleBreakpoint:toggle()
nio.sleep(20)  -- ⭐ This was the key!
Test.TerminalSnapshot("after_breakpoint")
```

Without this small delay, visual elements wouldn't appear in snapshots because the plugin's async processing hadn't completed.

### Phase 4: Complete System
We built a comprehensive system with:
- Automatic snapshot comparison and updating
- Embedded snapshot parsing with regex
- Clear diff output when tests fail
- Seamless integration with existing test framework

## The Working Solution

### Test Structure
Our final test demonstrates the complete external behavior testing approach:

```lua
Test.It("creates_and_removes_breakpoints_with_visual_markers", function()
    local api = prepare()
    
    -- Get plugin instances
    local breakpointApi = api:getPluginInstance(BreakpointApi)
    local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
    api:getPluginInstance(BreakpointVirtualText)
    
    -- Open fixture and position cursor
    vim.cmd("edit spec/fixtures/loop.js")
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    
    -- Capture before state
    Test.TerminalSnapshot("before_breakpoint")
    
    -- Toggle breakpoint and wait for async processing
    toggleBreakpoint:toggle()
    nio.sleep(20)
    
    -- Capture after state - should show ● marker
    Test.TerminalSnapshot("after_breakpoint")
    
    -- Verify both visually AND through data structure
    local breakpoints = breakpointApi.getBreakpoints()
    if breakpoints:count() ~= 1 then
        error("Expected 1 breakpoint, got " .. breakpoints:count())
    end
    
    -- Remove breakpoint
    toggleBreakpoint:toggle()
    nio.sleep(20)
    
    -- Verify visual removal
    Test.TerminalSnapshot("after_removal")
end)
```

### Visual Verification
The terminal snapshots show actual user-visible changes:

**Before:** Normal code display
```
 3|         console.log("ALoop iteration: ", i++);
```

**After:** Breakpoint marker appears
```
 3| ●       console.log("ALoop iteration: ", i++);
```

**After Removal:** Marker disappears
```
 3|         console.log("ALoop iteration: ", i++);
```

## Technical Implementation

### Core Components

#### 1. Terminal Snapshot Capture (`spec/helpers/terminal_snapshot.lua`)
- **Screen capture**: Uses `vim.fn.screenchar()` to capture terminal content
- **Embedded format**: Stores snapshots directly in test files
- **Automatic comparison**: Compares current state with embedded snapshots
- **Self-updating**: Updates snapshots when differences are detected

#### 2. Test Framework Integration (`spec/helpers/testing.lua`)
- **Simple API**: `Test.TerminalSnapshot(name)` function
- **Async compatibility**: Works within NvimAsync execution context
- **Consistent interface**: Matches existing `Test.Describe()` and `Test.It()` patterns

#### 3. Real-World Test (`spec/plugins/breakpoint_extmark.spec.lua`)
- **External behavior focus**: Tests visual markers, not internal state
- **Plugin interaction**: Uses actual plugin APIs as users would
- **Dual verification**: Both visual snapshots AND data structure checks

### Key Technical Challenges Solved

#### 1. Async Plugin Processing
**Problem**: Visual elements weren't appearing in snapshots
**Solution**: Strategic use of `nio.sleep(20)` to allow async processing

#### 2. Screen Content Capture
**Problem**: Getting actual rendered content, not buffer content
**Solution**: `vim.fn.screenchar()` with proper redraw commands

#### 3. Self-Contained Tests
**Problem**: Managing external snapshot files
**Solution**: Embedded snapshots with regex-based parsing

#### 4. Test Environment Compatibility
**Problem**: Working in headless mode without graphics
**Solution**: Text-based approach that works in all environments

## Results and Impact

### What We Achieved
1. **Visual Regression Testing**: Can now verify that UI elements appear correctly
2. **User Experience Testing**: Tests verify what users actually see and interact with
3. **Maintainable Tests**: Tests survive internal refactoring and focus on stable public interfaces
4. **Documentation Value**: Tests serve as usage examples for plugin authors
5. **Version Control Integration**: Text-based snapshots diff well in git

### The Paradigm Shift
- **From**: Testing internal APIs and state
- **To**: Testing external behavior and user experience
- **Result**: More valuable, maintainable, and intuitive tests

### Real-World Evidence
Our working test successfully demonstrates:
- Breakpoint markers (`●`) appearing when breakpoints are set
- Markers disappearing when breakpoints are removed  
- Proper cursor positioning and buffer content
- Integration with existing plugin ecosystem

## Future Directions

### Phase 2 Enhancements
Based on our documentation in `docs/testing-strategy.md`, future improvements include:

1. **Session Recording**: `Test.RecordSession()` and `Test.ReplaySession()`
2. **Command Sequences**: `Test.CommandSequence()` for workflow testing
3. **Region Snapshots**: `Test.RegionSnapshot()` for focused testing
4. **Auto-Detection**: Smart detection of floating windows and UI areas

### Development Experience Improvements
- **Snapshot preview**: Show snapshot content before embedding
- **Diff tools**: Integration with external diff viewers
- **Performance optimizations**: Incremental updates and caching

## Lessons Learned

### Technical Insights
1. **Async timing matters**: Small delays are crucial for async plugin processing
2. **Redraw is essential**: Force redraws to ensure current state is captured
3. **Screen functions work**: `vim.fn.screenchar()` reliably captures visual elements
4. **Embedded > External**: Self-contained tests are more maintainable

### Testing Philosophy
1. **User perspective wins**: Testing what users see is more valuable than testing internals
2. **Visual verification crucial**: Many bugs are visual and can't be caught by internal tests
3. **Documentation through tests**: Good external tests serve as usage examples
4. **Simplicity enables adoption**: Simple APIs like `Test.TerminalSnapshot(name)` encourage usage

## Conclusion

We successfully transformed neodap plugin testing from complex internal verification to simple demonstration of user functionality. The terminal snapshot system provides a foundation for visual regression testing that is:

- **Practical**: Works in real development environments
- **Maintainable**: Survives code refactoring
- **Valuable**: Catches real user-facing issues
- **Intuitive**: Easy for plugin developers to adopt

This approach represents a fundamental shift in testing philosophy that makes tests more valuable for both development and documentation, ultimately leading to better plugin quality and user experience.

The journey from traditional testing to external behavior testing demonstrates that sometimes the most innovative solutions come from asking a simple question: "What does the user actually see?"