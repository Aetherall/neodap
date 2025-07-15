# Async Patterns Analysis for Neodap

## Overview

This document captures insights from analyzing different approaches to handling async operations at vim context boundaries in Neodap. The core challenge is bridging synchronous vim contexts (keymaps, autocmds, commands) with asynchronous DAP operations while maintaining good developer experience.

## The Core Problem

### Vim Context Boundaries
Neovim operates on a single-threaded event loop where:
- **Sync contexts**: Keymaps, autocmds, user commands (main thread)
- **Async contexts**: NIO tasks, DAP protocol operations
- **Blocking the main thread** = Frozen UI, no input processing

### Current Solution: defer Pattern
```lua
-- ✅ Correct: Use defer at vim boundaries
vim.keymap.set('n', '<F5>', NvimAsync.defer(function()
  plugin:stepOver()  -- Async operation
end))

-- ❌ Incorrect: NvimAsync.run at vim boundaries  
vim.api.nvim_create_autocmd("CursorMoved", {
  callback = function()
    NvimAsync.run(function()  -- Should be defer
      plugin:updateDisplay()
    end)
  end
})
```

## Analyzed Approaches

### 1. Explicit defer (Current Implementation) ✅

**Pattern:**
```lua
-- Sync methods remain sync
function MyPlugin:getData()
  return self.cached_data
end

-- Async operations wrapped at boundaries
vim.keymap.set('n', '<F5>', NvimAsync.defer(function()
  plugin:refreshData()
end))
```

**Benefits:**
- ✅ Clear separation of sync/async
- ✅ Predictable behavior  
- ✅ No magic behavior
- ✅ Explicit at boundaries

**Drawbacks:**
- ⚠️ Manual wrapping required
- ⚠️ Verbose for many boundaries

### 2. Auto-Wrapping with Context Detection

**Pattern:**
```lua
-- Hypothetical: Methods auto-detect context
function MyPlugin:GetData()  -- Uppercase = auto-wrapped
  -- Returns different types based on calling context
end

-- Async context
nio.run(function()
  local data = plugin:GetData()  -- Returns UserData
end)

-- Sync context
vim.keymap.set('n', '<F5>', function()
  local data = plugin:GetData()  -- Returns ??? 
end)
```

**Major Issues:**
- ❌ **Inconsistent return types** - Same method, different behavior
- ❌ **Race conditions** - Sequential operations become concurrent
- ❌ **Debugging nightmares** - Context-dependent behavior
- ❌ **API contract violations** - Documentation becomes meaningless
- ❌ **Testing complexity** - Must test every method in multiple contexts

### 3. Return Value Strategies for Context-Dependent Calls

When auto-wrapping is used, what should sync context calls return?

#### 3a. Fake Waitable ❌
```lua
vim.keymap.set('n', '<F5>', function()
  local waitable = plugin:GetData()
  local data = waitable.wait()  -- Always returns nil
end)
```

**Problems:**
- ❌ Silent failure (always nil)
- ❌ Confusing interface (why does wait() exist if it returns nothing?)
- ❌ Misleading (suggests you can wait for data)

#### 3b. Poisoned Return ⚠️
```lua
vim.keymap.set('n', '<F5>', function()
  local result = plugin:GetData()
  print(result.value)  -- ❌ Throws: "Cannot access async result from sync context"
end)
```

**Benefits:**
- ✅ Fast failure with clear errors
- ✅ Educational - forces proper patterns
- ✅ Prevents silent race conditions

**Problems:**
- ❌ No interface guidance
- ❌ Inconsistent API

#### 3c. Smart Waitable (Mixed Approach) ✅
```lua
local function create_smart_waitable(function_name, original_function)
  return setmetatable({}, {
    __index = function(_, key)
      if key == "wait" then
        return function()
          error(string.format(
            "Cannot wait for async function '%s' result in sync context.\n" ..
            "Try one of these patterns:\n" .. 
            "  • nio.run(function() local data = plugin:%s() end)\n" ..
            "  • plugin:on%sCompleted(function(data) ... end)\n" ..
            "  • Use defer pattern: plugin.%sDeferred()",
            function_name, function_name, function_name, function_name
          ))
        end
      elseif key == "then" then
        return function(_, callback)
          NvimAsync.run(function()
            local result = original_function()
            callback(result)
          end)
        end
      elseif key == "is_resolved" then
        return function() return false end
      else
        error("Cannot access property '" .. key .. "' of async result in sync context.")
      end
    end
  })
end
```

**Benefits:**
- ✅ Consistent interface (waitable pattern)
- ✅ Clear error messages with suggestions
- ✅ Guided alternatives (.then() callback)
- ✅ Educational value
- ✅ Works naturally in async contexts

## LSP Integration Possibilities

### @async Annotation
```lua
---@async
function MyPlugin:GetData()
end
```

**Current Capabilities:**
- ✅ Visual await hints in LSP
- ✅ Diagnostic warnings for async usage
- ✅ Standardized annotation

**Limitations:**
- ❌ Can't discriminate runtime context
- ❌ Dynamic function wrapping loses annotations
- ❌ No context-dependent type checking

### Potential Solutions
```lua
-- Explicit marker parameters
---@overload fun(self: MyPlugin, marker: AsyncMarker): UserData
---@overload fun(self: MyPlugin, marker: SyncMarker): FakeWaitable
function MyPlugin:GetData(marker)
end
```

## Current Implementation Status

### ✅ Implemented
- [x] `NvimAsync.defer()` function in `/lua/neodap/tools/async.lua`
- [x] Fixed vim boundary violations:
  - [x] FrameHighlight autocmd (1 fix)
  - [x] ScopeViewer autocmds (4 fixes)
  - [x] CallStackViewer autocmds (3 fixes)  
  - [x] StackFrameTelescope actions (2 fixes)
- [x] Proper usage patterns in DebugMode, ToggleBreakpoint, StackNavigation

### Pattern Violations Fixed
Total: 10 violations → 10 fixes applied

| File | Context | Fix Applied |
|------|---------|-------------|
| FrameHighlight | `BufEnter` autocmd | `NvimAsync.run()` → `NvimAsync.defer()` |
| ScopeViewer | 4x autocmds | `NvimAsync.run()` → `NvimAsync.defer()` |
| CallStackViewer | 3x autocmds | `NvimAsync.run()` → `NvimAsync.defer()` |
| StackFrameTelescope | 2x telescope actions | `NvimAsync.run()` → `NvimAsync.defer()` |

### ✅ Correct Usage (No changes needed)
- BreakpointManager internal batching (legitimate `NvimAsync.run()` usage)

## Recommendations

### 1. Stick with Explicit defer Pattern ✅
- Clear, predictable behavior
- Good separation of concerns  
- No magic context detection
- Proven to work well

### 2. Enhanced Error Messages
```lua
function NvimAsync.defer(func)
  return function(...)
    local args = { ... }
    if nio.current_task() then
      error("defer() called from async context - use direct call instead")
    end
    NvimAsync.run(function()
      return func(unpack(args))
    end)
  end
end
```

### 3. Documentation Patterns
```lua
-- ✅ Clear patterns for developers
local MyPlugin = Class()

-- Sync operations
function MyPlugin:getCurrentData() end
function MyPlugin:isReady() end  

-- Async operations (called via defer at boundaries)
function MyPlugin:refreshData() end
function MyPlugin:stepOver() end

-- Boundary usage
vim.keymap.set('n', '<F5>', NvimAsync.defer(function()
  plugin:stepOver()
end))
```

### 4. Future Considerations
If auto-wrapping is ever reconsidered:
- Use **Smart Waitable** approach for return values
- Require explicit `@async` annotations  
- Provide extensive documentation and examples
- Consider separate APIs over context-dependent behavior

## Principles Learned

1. **Explicit > Implicit**: Clear boundaries better than magic behavior
2. **Fast Failure > Silent Failure**: Throw early with helpful messages
3. **Consistent APIs > Context-Dependent**: Same method should behave predictably  
4. **Educational Errors**: Error messages should guide toward correct patterns
5. **Vim Boundaries Are Special**: Sync→Async transitions need special handling

## Testing Patterns

```lua
-- Test both contexts explicitly
describe("Plugin methods", function()
  it("works in sync context via defer", function()
    vim.keymap.set('n', '<F5>', NvimAsync.defer(function()
      plugin:stepOver()
    end))
    -- Test the deferred execution
  end)
  
  it("works in async context directly", function()
    nio.run(function()
      plugin:stepOver()  -- Direct call
    end)
  end)
end)
```

---

*This analysis captures the evolution of async pattern handling in Neodap, providing guidance for future development and serving as reference for similar async boundary problems.*