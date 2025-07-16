# Neodap Development Guide

Neodap is a SDK for building DAP client plugins for Neovim. It provides a comprehensive API for interacting with the lifecycle of DAP sessions, breakpoints, threads, stacks, frames, variables, and more.

## Quick Start & Environment Setup

### Prerequisites
- Nix package manager (required for testing environment)
- Basic understanding of Lua and Neovim APIs
- Familiarity with DAP (Debug Adapter Protocol) concepts

### Environment Setup
```bash
nix develop  # Sets up complete development environment

# Run tests to verify setup
make test spec/core/neodap_core.spec.lua
```

## Architecture Overview

### Event-Driven Hierarchical API
Neodap uses a hierarchical event system where objects automatically clean up their child resources:
- Session → Thread → Stack → Frame hierarchy
- Automatic cleanup via hierarchical event registration
- Plugin lifecycle management through managers

### Async/Await Pattern with NvimAsync
- **NvimAsync Integration**: Seamlessly interleaves async context with vim context on the main thread
- **No Wrapper Overhead**: Eliminates need for `nio.run` or `vim.schedule` wrappers in most cases
- **Preemptive Execution**: Provides preemption of hook execution for responsive UI
- **Event Synchronization**: Uses futures and promises for reliable async coordination
- **All DAP operations are async** using lua-nio for non-blocking behavior

### Reference-Based Object Model
- Objects maintain `.ref` field with actual DAP data
- Clean separation between API objects and protocol data
- Lazy loading of expensive operations

### Logging and Debugging
Neodap uses a namespaced file-based logging system for debugging and development:

```lua
-- Get the logger instance with optional namespace
local log = require('neodap.tools.logger').get("MyPlugin")

-- Available log levels
log:debug("Development debugging information")
log:info("General operational information") 
log:warn("Warning conditions")
log:error("Error conditions") -- Also forwards to vim.notify

-- Multiple arguments are concatenated with spaces
log:info("Session started", "with ID:", session.ref.id)

-- Tables are automatically inspected with vim.inspect
log:debug("DAP response received", {
  command = "setBreakpoints",
  success = response.success,
  body = response.body
})

-- Buffer snapshots for visual debugging (currently disabled)
log:snapshot(bufnr, "After breakpoint set")
```

**Logger Features:**
- **Namespace Support**: `Logger.get("namespace")` creates separate instances per namespace
- **Automatic File Management**: Creates numbered log files in `log/neodap_N.log`
- **Structured Output**: Includes timestamp, log level, namespace, source location, and message
- **Table Inspection**: Automatically formats Lua tables using `vim.inspect()`
- **Line Buffering**: Immediate writes for real-time debugging
- **Error Forwarding**: `error()` calls are forwarded to `vim.notify()` for immediate visibility
- **Playground Mode**: Automatically detects playground environment for silent operation

**Log File Format:**
```
[2025-01-13 14:30:25.123] [INFO] [MyPlugin] session.lua:45 - Session initialized with ID: 2
[2025-01-13 14:30:25.124] [DEBUG] [MyPlugin] breakpoint.lua:12 - Breakpoint data: { id = 1, line = 10 }
```


**Best Practices:**
- Use `debug()` for detailed execution flow and development debugging
- Use `info()` for important operational events (session start/stop, breakpoint hits)
- Use `warn()` for recoverable issues or unusual conditions
- Use `error()` for serious problems requiring attention
- Include relevant context data as additional arguments or tables
- The logger automatically handles file creation, numbering, and location tracking

## Development Workflow

### Quick Commands (Recommended)
Use the provided Makefile for simplified development workflow:

```bash
# Run tests - various options
make test                                    # Run all tests in spec/
make test spec/core/neodap_core.spec.lua     # Run specific test file
make test PATTERN=breakpoint_hit             # Run tests matching pattern
make test spec/breakpoints/ PATTERN=toggle   # Run tests in folder with pattern

# View logs
make log                    # Show latest log file
make log FILTER=ERROR       # Show only ERROR lines from latest log
make log FILTER=breakpoint  # Show lines containing "breakpoint"

# Run playground
make play                   # Start neodap playground
```

### Direct Commands (Advanced)
If you need to use nix commands directly:

```bash
# Single test file - ONLY RELIABLE METHOD
nix run .#test spec/core/neodap_core.spec.lua -- --verbose

# Run with pattern filter - IMPORTANT: Use snake_case test names
nix run .#test spec/core/neodap_core.spec.lua -- --pattern "breakpoint_hit"

# ❌ PROBLEMATIC: Spaces in test names cause imprecise matching
# --pattern "it should" will match "it does" AND "should work" (word-based matching)

# ❌ DON'T USE: Direct busted, lua, or npm commands
```

### Common Development Patterns
```lua
-- Always use absolute paths
local abs_path = vim.fn.fnamemodify("file.js", ":p")

-- Skip session ID 1 in tests to avoid initialization conflicts
if session.ref.id == 1 then return end

-- ✅ PREFERRED: Use spies for event verification (no timing needed)
local spy = Test.spy()
session:onInitialized(spy)
-- ... trigger event ...
Test.assert.spy(spy).was_called()

-- ⚠️ MINIMAL USE: Only when absolutely necessary for async operations
nio.sleep(100)  -- Only for letting async operations complete when required
```

## Plugin Development

### Plugin Structure
```lua
local MyPlugin = {}

function MyPlugin.plugin(api)
  -- Clean hierarchical event registration
  api:onSession(function(session)
    session:onThread(function(thread)
      thread:onStopped(function(event)
        -- Handle breakpoint hits, stepping, etc.
      end)
    end)
  end)
end

return MyPlugin
```

### Key Patterns
- Use hierarchical APIs for automatic cleanup
- Leverage the manager pattern for resource coordination
- Follow the lazy binding architecture for breakpoints
- Maintain event responsibility separation

## Core APIs

### Session Management
```lua
local api, start = prepare()
api:onSession(function(session)
  -- Session lifecycle events
  session:onInitialized(function() end, { once = true })
  session:onTerminated(function() end)
end)
```

### Breakpoint Management (Lazy Binding Architecture)
```lua
local breakpointManager = BreakpointManager.create(api)

-- Hierarchical event API
breakpointManager:onBreakpoint(function(breakpoint)
  breakpoint:onBinding(function(binding)
    binding:onHit(function(hit)
      -- Handle breakpoint hits
    end)
  end)
end)
```

### Stack Navigation
```lua
thread:onStopped(function()
  local stack = thread:stack()
  local frame = stack:top()
  local scopes = frame:scopes()
  
  -- Access variables
  for _, scope in ipairs(scopes) do
    local variables = scope:variables()
    -- Process variables
  end
end)
```

## Testing Guidelines

### Test Structure
- Use `Test.Describe()` and `Test.It()` from `spec/helpers/testing.lua`
- Prepare clean instances with `spec/helpers/prepare.lua`
- Use JavaScript fixtures from `spec/fixtures/`

### Test Naming Convention (CRITICAL)
**Always use snake_case for test names to enable precise pattern matching:**

```lua
-- ✅ CORRECT: Enables precise --pattern targeting
Test.It("breakpoint_hit_triggers_event", function()
  -- Test implementation
end)

Test.It("stack_frame_navigation_works", function()
  -- Test implementation
end)

-- ❌ INCORRECT: Causes imprecise pattern matching
Test.It("it should trigger breakpoint hit", function()
  -- --pattern "should" will match unrelated tests
end)

Test.It("breakpoint hit works correctly", function()
  -- --pattern "hit" will match many unrelated tests
end)
```

**Rationale**: The `--pattern` flag uses word-based matching, so `--pattern "it should"` will match any test containing either "it" OR "should", not the exact phrase.

### Timing Patterns
```lua
-- ✅ PREFERRED: Use spies for reliable event testing (no timing delays)
local breakpoint_spy = Test.spy()
local stopped_spy = Test.spy()

breakpointManager:onBreakpoint(function(breakpoint)
  breakpoint_spy()
  breakpoint:onBinding(function(binding)
    binding:onHit(stopped_spy)
  end)
end)

-- ... trigger breakpoint hit ...

Test.assert.spy(breakpoint_spy).was_called()
Test.assert.spy(stopped_spy).was_called()

-- ⚠️ MINIMAL USE: Only when async operations need time to complete
-- nio.sleep(100)  -- Only use when spies aren't sufficient

-- ❌ LEGACY: Avoid vim.wait for event verification
-- vim.wait(15000, event.is_set)  -- Flaky, slow, unreliable
-- vim.wait(25000, event.is_set)  -- Even worse for complex scenarios
```

### Test Isolation
- Each test gets fresh manager, adapter, and API instances
- Automatic cleanup prevents test interference
- Skip session ID 1 to avoid initialization conflicts

## Debugging & Troubleshooting

### Common Issues & Solutions

#### Stack Caching Issue (RESOLVED)
- **Problem**: Stepping appeared stuck due to cached stack traces
- **Solution**: Stack caching disabled in `Thread:stack()` method
- **Pattern**: Always fetch fresh stack traces after stepping

#### Timing Issues
- **Symptoms**: Test failures with async operations, race conditions
- **Legacy Solution**: Increase `nio.sleep()` delays and `vim.wait()` timeouts (unreliable)
- **Modern Solution**: Use spies to verify events occurred rather than waiting for timeouts
- **Best Practice**: Minimize `nio.sleep()` usage - only use when async operations genuinely need time to complete
- **Pattern**: Replace timing-based tests with spy assertions for deterministic results

#### Session Management
- **Problem**: Multiple sessions interfering with each other
- **Solution**: Filter session IDs properly, handle termination events
- **Pattern**: Always check session state before operations

## Contributing Guidelines

### Code Style
- Follow existing Lua patterns in the codebase
- Use type annotations: `---@param api neodap.api`
- Maintain hierarchical event patterns
- Prefer lazy over eager resource creation

### Pull Request Process
1. Ensure all tests pass: `nix run .#test spec`
2. **Use snake_case test names for precise pattern matching**
3. Add tests for new functionality
4. Update documentation for API changes
5. Follow the lazy binding architecture for breakpoint-related changes

### Architecture Decisions
- Prefer lazy over eager binding creation
- Maintain event responsibility separation
- Use source-level DAP synchronization
- Follow the hierarchical cleanup pattern
- Keep reference-based object model consistency

## Related Documentation
- [Breakpoint Lazy Bindings Architecture](docs/architecture/breakpoints.md)
- [Test Specifications](spec/)