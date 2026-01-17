# Testing Guide

## Commands

```bash
# Run all tests
make test

# Run a single test file
make test-file FILE=tree_buffer_output

# Update reference screenshots
make test-update-screenshots

# Clean test artifacts
make clean
```

## Test Runner

Tests run in parallel using `tests/parallel.lua`. Each test case runs in its own Neovim process with a 10-second timeout.

**NEVER truncate test output.** Do not pipe to `head`, `tail`, `grep`, or any filter. The runner provides progress updates and a final summary - truncating hides failures and makes debugging impossible. Always run tests with full output.

## Directory Structure

```
tests/
├── init.lua                    # Test initialization
├── parallel.lua                # Parallel test runner
├── helpers/
│   ├── test_harness.lua        # Integration test harness
│   └── dap/                    # DAP fixture helpers
│
├── unit/                       # Unit tests (no debug adapter)
│   ├── test_async.lua          # Async primitives
│   ├── test_scoped.lua         # Scoped reactivity
│   ├── test_neograph.lua       # Neograph-native integration
│   └── test_uri_parsing.lua    # URI parsing
│
├── integration/                # Integration tests (Python + JavaScript)
│   ├── core/                   # Entity behavior tests
│   │   ├── test_session.lua    # Session lifecycle
│   │   ├── test_thread.lua     # Thread/stack behavior
│   │   └── test_frame.lua      # Frame/scope/variables
│   │
│   ├── url/                    # URL/URI tests
│   │   ├── test_url_query.lua  # URL query spec compliance
│   │   └── test_uri.lua        # URI format/resolution
│   │
│   ├── context/                # Context and focus tests
│   │   ├── test_context.lua    # @frame/@thread/@session
│   │   └── test_focus.lua      # DapFocus behavior
│   │
│   ├── plugins/                # Plugin-specific tests
│   │   ├── test_auto_context.lua
│   │   ├── test_dap_jump.lua
│   │   ├── test_leaf_session.lua
│   │   └── test_tree_buffer.lua
│   │
│   └── multi_session/          # Multi-session behavior
│       └── test_multi_session.lua
│
├── dap-lua/                    # Transport layer tests
├── neodap/
│   ├── integration/            # Additional integration tests
│   └── plugins/                # Plugin tests with screenshots
└── screenshots/                # Reference screenshots
```

### Running Specific Test Groups

```bash
# Run only unit tests (fast, no adapter needed)
make test-unit

# Run only transport layer tests
make test-dap-lua

# Run a single test file
make test-file FILE=test_session
```

## Writing Tests

Tests use MiniTest format:

```lua
local T = MiniTest.new_set()

T["test name"] = function()
  MiniTest.expect.equality(actual, expected)
end

return T
```

## MiniTest Child Neovim

Tests run in an isolated child Neovim process. The `child` object provides direct proxies to vim namespaces, avoiding verbose `child.lua()` calls.

### Lifecycle Methods

| Method | Description |
|--------|-------------|
| `child.start()` | Initialize and connect |
| `child.stop()` | Terminate the process |
| `child.restart(args)` | Stop and start fresh |
| `child.is_running()` | Check if process is active |
| `child.is_blocked()` | Check if process is blocked |

### Execution Methods

| Method | Description |
|--------|-------------|
| `child.lua(code)` | Execute Lua code string |
| `child.lua_get(expr)` | Execute and return result |
| `child.lua_func(fn, ...)` | Call function with args |
| `child.lua_notify(code)` | Execute async (no wait) |
| `child.cmd(command)` | Execute Ex command |
| `child.cmd_capture(cmd)` | Execute and capture output |
| `child.type_keys(keys)` | Emulate typing keys |
| `child.ensure_normal_mode()` | Return to normal mode |
| `child.get_screenshot()` | Capture screen state |

### Vim Namespace Proxies

Direct access to vim namespaces without `child.lua()`:

```lua
-- Instead of: child.lua([[ vim.api.nvim_get_current_buf() ]])
child.api.nvim_get_current_buf()

-- Instead of: child.lua([[ vim.fn.line(".") ]])
child.fn.line(".")

-- Instead of: child.lua([[ vim.o.laststatus = 0 ]])
child.o.laststatus = 0
```

| Proxy | Vim Namespace |
|-------|---------------|
| `child.api` | `vim.api.*` |
| `child.fn` | `vim.fn.*` |
| `child.diagnostic` | `vim.diagnostic.*` |
| `child.treesitter` | `vim.treesitter.*` |
| `child.lsp` | `vim.lsp.*` |
| `child.ui` | `vim.ui.*` |
| `child.fs` | `vim.fs.*` |
| `child.json` | `vim.json.*` |
| `child.loop` | `vim.loop.*` |

### Variable Scope Proxies

| Proxy | Vim Scope |
|-------|-----------|
| `child.g` | `vim.g.*` (global) |
| `child.b` | `vim.b.*` (buffer) |
| `child.w` | `vim.w.*` (window) |
| `child.t` | `vim.t.*` (tab) |
| `child.v` | `vim.v.*` (vim vars) |
| `child.env` | `vim.env.*` (environment) |

### Option Scope Proxies

| Proxy | Vim Scope |
|-------|-----------|
| `child.o` | `vim.o.*` (global options) |
| `child.go` | `vim.go.*` (global-only) |
| `child.bo` | `vim.bo.*` (buffer options) |
| `child.wo` | `vim.wo.*` (window options) |

### When to Use `child.lua()`

Use proxies for simple API calls. Use `child.lua()` for:
- Multi-statement logic with local variables
- Plugin-specific state that requires method chaining
- Complex setup that can't be expressed as single calls

```lua
-- Good: Use proxies for simple operations
local bufnr = child.api.nvim_get_current_buf()
child.o.laststatus = 0
child.cmd("edit " .. path)

-- Good: Use child.lua() for complex logic
child.lua([[
  local bufnr = vim.api.nvim_get_current_buf()
  _G.has_frame = _G.debugger.ctx.frame:get(bufnr) ~= nil
]])
```

## Integration Tests

Use the test harness for DAP integration tests:

```lua
local harness = require("helpers.test_harness")

local T = harness.integration("my_tests", function(T, ctx)
  T["test with debugger"] = function()
    local h = ctx.create()
    local path = h:create_file(h:programs().simple_vars)

    -- Launch via DapLaunch command (uses code-workspace config resolution)
    h.child.g.debug_file = path
    h:cmd("DapLaunch " .. ctx.config_stop)
    h:wait_url("/sessions/threads/stacks(seq=1)[0]/frames[0]")
    h:cmd("DapFocus /sessions/threads/stacks(seq=1)[0]/frames[0]")

    -- Now @session, @thread, @frame are available
    local line = h:query_field("@frame", "line")
    MiniTest.expect.equality(line, 1)
  end
end)

return T
```

Integration tests run against both Python (debugpy) and JavaScript (js-debug) adapters automatically.

## URL-Based Test Philosophy

Tests use **declarative URL patterns** to express what they're waiting for, rather than imperative fetch sequences. This makes tests:
- **Explicit**: The URL shows exactly what state is expected
- **Readable**: URLs are self-documenting
- **Robust**: No hidden state management or race conditions

### Core Pattern

Every debug interaction follows this pattern:

```lua
-- 1. Trigger an action
h:cmd("DapStep over")

-- 2. Wait for the expected state (URL declares what we need)
h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")

-- 3. Set focus context for subsequent queries
h:cmd("DapFocus /sessions/threads(state=stopped)/stacks[0]/frames[0]")

-- 4. Query using context shortcuts
local value = h:query_field("@frame/scopes[0]/variables(name=x)[0]", "value")
```

### Sequence-Based Waits After Stepping (Recommended)

**Problem:** `DapStep` returns immediately after the DAP request is acknowledged, NOT after the step completes. The old stack/frame still exists until the `stopped` event arrives and creates a new stack. A generic `wait_url` matches the **stale** frame immediately.

**Solution:** Use the stack's `seq` property, which increments on each stop:

```lua
-- Launch creates first stop (seq=1)
h:cmd("DapLaunch " .. ctx.config_stop)
h:wait_url("/sessions/threads/stacks(seq=1)[0]/frames[0]")
h:cmd("DapFocus /sessions/threads/stacks(seq=1)[0]/frames[0]")

-- Step creates second stop (seq=2)
h:cmd("DapStep over")
h:wait_url("/sessions/threads/stacks(seq=2)[0]/frames[0]")  -- Waits for NEW stack
h:cmd("DapFocus /sessions/threads/stacks(seq=2)[0]/frames[0]")

-- Another step creates third stop (seq=3)
h:cmd("DapStep over")
h:wait_url("/sessions/threads/stacks(seq=3)[0]/frames[0]")
h:cmd("DapFocus /sessions/threads/stacks(seq=3)[0]/frames[0]")
```

**Why this works:**
1. Each `stopped` event increments the thread's `stops`
2. A new stack is created with `seq = stops`
3. Waiting for `stacks(seq=N)` ensures we get the stack from the Nth stop
4. No race condition - the old stack has `seq=N-1`, not `seq=N`

This pattern is deterministic and works reliably across both Python and JavaScript adapters.

### Line-Specific Waits (Alternative)

When you know the expected line number, you can also filter by line:

```lua
-- GOOD: Waits until frame is at expected line
h:cmd("DapStep over")
h:wait_url("/sessions/threads/stacks[0]/frames(line=2)[0]")
h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
```

However, line numbers vary between adapters and programs. The seq-based approach is more portable.

### Multi-Session Waits

When launching multiple sessions, use **session index** to avoid matching the already-stopped first session:

```lua
-- Launch first session
h:launch({ program = path1, stopOnEntry = true })
h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames[0]")
h:cmd("DapFocus /sessions/threads(state=stopped)/stacks[0]/frames[0]")
local session1_uri = h:query_field("@session", "uri")

-- Launch second session - use index to wait for the NEW session
h:launch({ program = path2, stopOnEntry = true })
h:wait_url("/sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")
h:cmd("DapFocus /sessions[1]/threads(state=stopped)/stacks[0]/frames[0]")
local session2_uri = h:query_field("@session", "uri")
```

### Save URIs Before Termination

Focus context is cleared when a session terminates. Save URIs before continuing to completion:

```lua
-- Save session URI before termination
local session_uri = h:query_field("@session", "uri")

h:cmd("DapContinue")
h:wait_terminated(5000)

-- Use saved URI (not @session which is now cleared)
h:wait_url(session_uri .. "/outputs[0]")
h:open_tree(session_uri, 0)
```

### Adapter-Specific Line Numbers

Python and JavaScript programs have different line structures. When tests step through code, use adapter-specific skips or line numbers:

```lua
T["multiple steps through logging"] = function()
  -- Skip for JavaScript - different line numbers for logging_steps program
  if ctx.adapter_name == "javascript" then
    return
  end

  -- Python logging_steps: line 1 -> 5 -> 6 -> 7
  h:cmd("DapStep over")
  h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=5)[0]")
  -- ...
end
```

## Harness Methods

### Setup and Lifecycle

| Method | Description |
|--------|-------------|
| `h:create_file(code)` | Create temp file with program code |
| `h:programs()` | Get language-specific test programs |
| `h:cmd("DapLaunch " .. ctx.config_stop)` | Launch debug session (set `h.child.g.debug_file` first) |
| `h:cleanup()` | Cleanup sessions and temp files |
| `h:dispose()` | Dispose the debugger |

### URL Queries

| Method | Description |
|--------|-------------|
| `h:wait_url(url, timeout)` | Wait for URL to resolve to non-nil |
| `h:wait_field(url, field, value, timeout)` | Wait for field to equal value |
| `h:query_field(url, field)` | Get field value from entity |
| `h:query_uri(url)` | Get entity's URI |
| `h:query_count(url)` | Count results |
| `h:query_is_nil(url)` | Check if result is nil |
| `h:query_call(url, method)` | Call method on entity |

### Commands and Focus

| Method | Description |
|--------|-------------|
| `h:cmd(command)` | Execute vim command |
| `h:focus(url, wait_ms)` | Focus entity via DapFocus |
| `h:unfocus(wait_ms)` | Clear focus |

### Waiting

| Method | Description |
|--------|-------------|
| `h:wait(ms)` | Wait with event processing |
| `h:wait_terminated(timeout)` | Wait for session termination |

### Visual Tests

| Method | Description |
|--------|-------------|
| `h:setup_visual()` | Enable visual mode (80x24) |
| `h:take_screenshot()` | Capture sanitized screenshot |
| `h:open_tree(path)` | Open dap://tree buffer |

## Screenshot Tests

For visual plugin tests:

```lua
T["renders correctly"] = function()
  local h = ctx.create()
  h:setup_visual()  -- Enable visual mode (80x24 terminal)
  h:use_plugin("neodap.plugins.tree_buffer")

  -- setup...

  MiniTest.expect.reference_screenshot(h:take_screenshot())
end
```

Screenshots are saved to `tests/screenshots/`. On first run, reference screenshots are created. Subsequent runs compare against references.

### Screenshot Sanitization

Dynamic values are sanitized for deterministic comparisons:
- Thread IDs -> `NNNN`
- Session IDs -> `NNNNN`
- File paths -> basename with `NN` for numbers
- PIDs -> `NNNNNN`

## Test Programs

The harness provides test programs for each language:

| Program | Description |
|---------|-------------|
| `simple_vars` | Basic variable assignments (3 lines) |
| `simple_loop` | For loop with print |
| `with_function` | Nested function calls |
| `recursive` | Recursive function (countdown) |
| `logging_steps` | Produces stdout on each step |
| `typed_vars` | Various types (int, float, string, bool, list) |

Access via `h:programs().simple_vars`.

### Program Line Numbers

Know your program's line structure for stepping tests:

**Python simple_vars:**
```
Line 1: x = 1
Line 2: y = 2
Line 3: print(x + y)
```

**Python logging_steps:**
```
Line 1: def log_step(n):
Line 2:     print(f'Step {n}', flush=True)
Line 3:     return n
Line 4: (empty)
Line 5: a = log_step(1)
Line 6: b = log_step(2)
Line 7: c = log_step(3)
Line 8: print('Done', flush=True)
```

**JavaScript logging_steps:**
```
Line 1: function logStep(n) {
Line 2:   console.log(`Step ${n}`);
Line 3:   return n;
Line 4: }
Line 5: (empty)
Line 6: const a = logStep(1);
Line 7: const b = logStep(2);
Line 8: const c = logStep(3);
Line 9: console.log('Done');
```

## Best Practices

### URLs Express Intent

Write URLs that declare what you're waiting for. The URL is documentation:

```lua
-- Good: URL shows exactly what state we expect
h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames(line=2)[0]")
h:wait_url("@frame/scopes[0]/variables(name=counter)[0]")
h:wait_url("/breakpoints(line=5)/bindings(verified=true)")

-- Avoid: Generic waits that don't express intent
h:wait_url("/sessions/threads/stacks/frames")
h:wait(500)  -- arbitrary sleep
```

### Prefer Screenshots Over Assertions

Screenshots catch visual regressions that programmatic assertions miss. If a test verifies UI behavior, use a screenshot.

```lua
-- Good: Screenshot captures the full visual state
MiniTest.expect.reference_screenshot(h:take_screenshot())

-- Avoid: Assertions only check specific values, miss layout/styling issues
MiniTest.expect.equality(line_count, 5)
```

### Wait for State, Don't Sleep

Use explicit wait methods instead of arbitrary sleeps.

```lua
-- Good: Wait for specific state
h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames[0]")
h:wait_field("/sessions[0]", "state", "terminated")

-- Avoid: Arbitrary sleeps are flaky
h:wait(500)
```

### One Behavior Per Test

Each test should verify a single behavior. This makes failures easier to diagnose.

```lua
-- Good: Focused tests
T["shows breakpoint sign when added"] = function() ... end
T["removes breakpoint sign when deleted"] = function() ... end

-- Avoid: Multiple behaviors in one test
T["breakpoint signs work"] = function()
  -- add, verify, delete, verify again...
end
```

## Common Pitfalls

### Forgetting DapFocus After wait_url

`wait_url` only waits - it doesn't set focus context. Always follow with `DapFocus`:

```lua
-- WRONG: @frame won't resolve
h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames[0]")
local line = h:query_field("@frame", "line")  -- nil!

-- RIGHT: Focus sets the context
h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames[0]")
h:cmd("DapFocus /sessions/threads(state=stopped)/stacks[0]/frames[0]")
local line = h:query_field("@frame", "line")  -- works
```

### Generic Waits After Steps

`DapStep` returns after the DAP request response, NOT after the step completes. The old frame still exists until the `stopped` event creates a new stack. A generic wait matches the stale frame:

```lua
-- WRONG: Matches stale frame immediately, step hasn't completed
h:cmd("DapStep over")
h:wait_url("/sessions/threads/stacks[0]/frames[0]")

-- RIGHT: Use seq to wait for the NEW stack (see "Sequence-Based Waits" section)
h:cmd("DapStep over")
h:wait_url("/sessions/threads/stacks(seq=2)[0]/frames[0]")  -- After first step

-- ALSO OK: Wait for specific line if you know it
h:cmd("DapStep over")
h:wait_url("/sessions/threads/stacks[0]/frames(line=2)[0]")
```

### Using @session After Termination

Focus context is cleared when sessions terminate:

```lua
-- WRONG: @session is nil after termination
h:cmd("DapContinue")
h:wait_terminated(5000)
h:wait_url("@session/outputs[0]")  -- fails!

-- RIGHT: Save URI before termination
local uri = h:query_field("@session", "uri")
h:cmd("DapContinue")
h:wait_terminated(5000)
h:wait_url(uri .. "/outputs[0]")  -- works
```

### Failures Are More Valuable Than Passes

A failing test is a discovery. It reveals unexpected behavior, edge cases, or bugs. Don't dismiss failures or work around them - investigate why they happen.

If a test fails intermittently, that's a signal about timing, state, or non-determinism in the code under test. Fix the root cause, don't add retries or sleeps.

### Complex Tests Signal Design Problems

If a test is hard to write, the code under test is probably hard to use. Don't simplify the test - simplify the API.

### Don't Hide Flakiness

If a test is flaky, don't skip it or add tolerance. A flaky test indicates:
- Race conditions in the code
- Missing synchronization
- Non-deterministic external dependencies

Write the test to expose the flakiness, then fix the underlying issue.

## Combinatorial Testing

When a feature has multiple independent dimensions (e.g., session state x thread count x breakpoint type), testing all combinations explodes exponentially. Pairwise testing solves this: instead of testing every combination, test every pair of values at least once. Research shows most bugs are triggered by interactions between two factors, not three or more.

For complexity hotspots where interactions matter more, use n-wise testing (3-wise, 4-wise) to cover higher-order combinations. This gives confidence without exhaustive enumeration.

Example: A feature with 4 parameters, each having 3 values, has 81 combinations. Pairwise coverage requires only ~9-12 test cases while catching most interaction bugs. Reserve exhaustive testing for critical paths where every combination must work.
