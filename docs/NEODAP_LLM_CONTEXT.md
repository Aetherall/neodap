# Neodap LLM Context Guide

## Project Overview

**Neodap** is a comprehensive SDK for building DAP (Debug Adapter Protocol) client plugins for Neovim. It provides a sophisticated API for managing debug sessions, breakpoints, threads, stacks, frames, variables, and more.

## Architecture & Core Patterns

### Language & Runtime
- **Primary Language**: Lua (for Neovim)
- **Runtime**: Neovim with lua-nio for async operations
- **Testing**: Busted framework with nix-based test runner
- **Package Manager**: Nix (use `nix run .#test spec/file_spec.lua --verbose`)

### Key Architectural Patterns

#### 1. Async/Await Pattern with nio
```lua
-- All async operations use nio.run() and nio.sleep()
nio.run(function()
  session:start({
    configuration = { type = "pwa-node", program = "..." },
    request = "launch",
  })
end)
```

#### 2. Event-Driven Architecture
```lua
-- Session lifecycle events
session:onInitialized(function() end, { once = true })
session:onThread(function(thread) end)

-- Thread state events  
thread:onStopped(function(body) end)
thread:onContinued(function(body) end)
```

#### 3. Reference-Based Object Model
- Objects maintain `ref` field with actual data
- Use `obj.ref.property` to access properties
- Example: `frame.ref.line`, `frame.ref.column`

#### 4. Manager Pattern
- `Manager.create()` for session management
- `Api.register(manager)` for API registration
- Plugin registration via `PluginName.plugin(api)`

## Critical Implementation Details

### Stack Caching Issue (RESOLVED)
**Problem**: The `Thread:stack()` method was caching stack traces, causing stepping operations to appear "stuck" at the same line.

**Root Cause**: 
```lua
-- PROBLEMATIC CODE (now fixed)
function Thread:stack()
  if self._stack then
    return self._stack  -- Returns stale cache!
  end
  -- ... fetch fresh stack
end
```

**Solution**: Disabled stack caching to ensure fresh stack traces after stepping:
```lua
-- FIXED CODE
function Thread:stack()
  -- if self._stack then
  --   return self._stack
  -- end
  -- Always fetch fresh stack trace
end
```

**Impact**: This fix resolves stepping issues where debugger appeared to do nothing or return to previous lines.

### DAP Protocol Specifics

#### Breakpoint Setting
```lua
session.ref.calls:setBreakpoints({
  source = { path = vim.fn.fnamemodify("file.js", ":p") },
  breakpoints = { { line = 3 } }
}):wait()
```

#### Stepping Operations
- Step operations are async and require proper timing
- Use `nio.sleep()` between operations for stability
- Stack traces must be fetched fresh after each step

#### Session Management
- Session IDs start from 1, skip session 1 in tests: `if session.ref.id == 1 then return end`
- Always use absolute paths for file references
- Handle session termination gracefully

### Plugin Development Patterns

#### DebugMode Plugin Structure
```lua
local DebugMode = {}

function DebugMode.plugin(api)
  -- Plugin registration and event handling
  api:onSession(function(session)
    -- Session-specific logic
  end)
end

-- Key mappings and UI interactions
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<leader>dm', true, false, true), 'x', false)
```

#### Common Plugin Events
- `onInitialized`: Set breakpoints, configure session
- `onThread`: Handle thread lifecycle
- `onStopped`: Handle breakpoint hits, stepping
- `onContinued`: Handle execution resume

### Testing Patterns

#### Test Structure
```lua
describe("Feature description", function()
  local function prepare()
    local manager = Manager.create()
    local adapter = ExecutableTCPAdapter.create({
      executable = { cmd = "js-debug", cwd = vim.fn.getcwd() },
      connection = { host = "::1" }
    })
    local api = Api.register(manager)
    
    local function start(fixture)
      -- Session creation and startup
    end
    
    return api, start
  end
  
  it('test description', function()
    local api, start = prepare()
    -- Test implementation
  end)
end)
```

#### Async Test Patterns
- Use `nio.control.event()` for test synchronization
- Always use `vim.wait()` with reasonable timeouts (15000-25000ms)
- Proper timing with `nio.sleep()` between operations

#### JavaScript Fixture Patterns
```javascript
// setInterval patterns (complex async behavior)
setInterval(() => {
  console.log("ALoop iteration: ", i++);  // Line 3
  console.log("BLoop iteration: ", i++);  // Line 4
}, 1000);

// Simple sequential patterns (predictable stepping)
function simpleFunction() {
  let x = 1;     // Line 2
  let y = 2;     // Line 3
  return x + y;  // Line 4
}
```

## Common Debugging Scenarios

### Stepping Issues
**Symptoms**: Debugger appears to do nothing on step operations, or returns to previous lines
**Root Cause**: Usually stack caching or insufficient timing
**Solution**: Ensure fresh stack traces and proper async timing

### Timing Issues
**Symptoms**: Test failures with "Should handle X" assertions
**Root Cause**: Insufficient wait times for async operations
**Solution**: Increase `nio.sleep()` delays and `vim.wait()` timeouts

### Session Management Issues
**Symptoms**: Multiple sessions interfering with each other
**Root Cause**: Not filtering session IDs properly
**Solution**: Skip session ID 1, handle session termination

## File Structure & Responsibilities

### Core API (`lua/neodap/api/`)
- `Api.lua`: Main API registration and management
- `Session.lua`: Debug session lifecycle
- `Thread.lua`: Thread management and stepping (**contains critical stack caching fix**)
- `Frame.lua`: Stack frame representation
- `Stack.lua`: Stack trace management

### Adapters (`lua/neodap/adapter/`)
- `executable_tcp.lua`: TCP-based debug adapter communication
- `components/connection.lua`: Network connection handling

### Plugins (`lua/neodap/plugins/`)
- `DebugMode.lua`: Interactive debugging mode (**primary user interface**)
- `JumpToStoppedFrame.lua`: Automatic cursor positioning

### Testing (`spec/`)
- `neodap_core_spec.lua`: Core functionality tests
- `debug_mode_spec.lua`: Plugin interaction tests
- `api_stack_spec.lua`: Stack API tests

## Performance Considerations

### Critical Timing Patterns
```lua
-- Always allow time for DAP operations
nio.sleep(100)  -- Minimal delay
nio.sleep(200)  -- UI operations
nio.sleep(300)  -- Step operations

-- Use appropriate test timeouts
vim.wait(15000, event.is_set)  -- Standard timeout
vim.wait(25000, event.is_set)  -- Complex operations
```

### Memory Management
- Disable stack caching when fresh data is required
- Clean up event handlers properly
- Terminate sessions gracefully

## Common Gotchas

1. **Stack Caching**: Always verify fresh stack traces after stepping
2. **Session IDs**: Skip session 1 in tests, it's used for initialization
3. **Async Timing**: Never assume immediate completion of DAP operations
4. **File Paths**: Always use absolute paths with `vim.fn.fnamemodify(file, ":p")`
5. **UI Operations**: Use `vim.schedule()` for cursor positioning and display updates
6. **setInterval Behavior**: JavaScript setInterval creates complex stepping patterns, use simpler fixtures for predictable behavior

## CLI Commands & Testing Approaches

### ✅ Working Commands (Nix-Based)

#### Test Execution (ONLY WORKING APPROACH)
```bash
# Single test file - THIS IS THE ONLY WAY THAT WORKS
nix run .#test spec/neodap_core_spec.lua --verbose

# Multiple test files
nix run .#test spec/debug_mode_spec.lua --verbose
nix run .#test spec/api_stack_spec.lua --verbose

# All tests in directory
nix run .#test spec/ --verbose
```

**Why Nix Works**: 
- Provides isolated environment with correct Neovim version
- Includes all required dependencies (lua-nio, busted, js-debug)
- Proper PATH configuration for debug adapters
- Consistent environment across different systems

### ❌ Failed Approaches (DO NOT USE)

#### Direct Busted Commands
```bash
# THESE DO NOT WORK
busted spec/neodap_core_spec.lua
nvim-busted spec/neodap_core_spec.lua
lua busted spec/neodap_core_spec.lua
```

**Why They Fail**:
- Missing lua-nio dependency
- Incorrect Neovim API environment
- Missing debug adapter executables (js-debug)
- Wrong Lua version or missing modules

#### Standard Lua Test Runners
```bash
# THESE DO NOT WORK
lua spec/neodap_core_spec.lua
luajit spec/neodap_core_spec.lua
```

**Why They Fail**:
- No access to Neovim APIs (`vim.*` functions)
- Missing nio async framework
- No DAP protocol support

#### NPM/Node.js Approaches
```bash
# THESE DO NOT WORK
npm test
node spec/neodap_core_spec.lua
```

**Why They Fail**:
- This is a Lua project, not a Node.js project
- JavaScript is only used for test fixtures

### 🔧 Development Commands

#### Git Operations
```bash
# Check status after cleanup
git status

# Unstage debugging artifacts
git reset HEAD debug_file.lua

# View staged changes
git diff --cached --name-only
```

#### File Operations
```bash
# Remove debugging artifacts
rm spec/minimal_step_test.lua spec/stepin_test.lua

# List directory contents
ls -la spec/fixtures/
```

### 🚨 Critical Testing Requirements

1. **ALWAYS use Nix**: No other test runner works reliably
2. **Environment Setup**: Nix handles all dependencies automatically
3. **Debug Adapters**: js-debug must be available (provided by Nix)
4. **Async Support**: lua-nio must be properly configured (handled by Nix)
5. **Neovim APIs**: Full vim.* API access required (only in Nix environment)

### Test Timing & Results

#### Successful Test Patterns
```bash
# Core functionality (fast, reliable)
nix run .#test spec/neodap_core_spec.lua --verbose
# Expected: "2 successes / 0 failures / 0 errors"
# Time: ~7 seconds

# Debug mode (slower, integration tests)
nix run .#test spec/debug_mode_spec.lua --verbose  
# Expected: Multiple tests with stepping verification
# Time: ~15-25 seconds per test
```

#### Common Test Warnings
```bash
warning: Git tree '/path/to/neodap' is dirty
```
**Meaning**: Uncommitted changes exist (normal during development)
**Action**: Safe to ignore, does not affect test execution

#### Test Output Patterns
```bash
# Success Pattern
Process spawned with PID: XXXXX
stdout: Debug server listening at ::1:XXXXX
Connected to ::1:XXXXX
X successes / 0 failures / 0 errors / 0 pending : X.XXX seconds

# Failure Pattern  
X successes / Y failures / 0 errors / 0 pending : X.XXX seconds
Failure → spec/file_spec.lua @ line
Expected: (value)
Actual: (different value)
```

## Development Workflow
