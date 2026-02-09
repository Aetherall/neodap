# Claude Code Instructions

## Project Structure

```
lua/
  neodap/           # Debug adapter plugin
    entities/       # Entity definitions (Session, Thread, Frame, etc.)
    plugins/        # UI plugins (tree_buffer, breakpoint_signs, etc.)
    schema.lua      # Entity schema with edges and indexes
  neograph/         # Reactive graph library (standalone)
    init.lua        # Graph, View, Signal, EdgeHandle
    compliance.lua  # Spec compliance tests (255 tests)
tests/
  unit/             # Fast unit tests (no adapter needed)
  integration/      # Integration tests (require debug adapters)
  neodap/           # Plugin-specific tests
```

## Running Tests

Use the Makefile commands:

```bash
make test              # Run all tests
make test "pattern"    # Run tests matching pattern
```

The full test suite (`make test`) is slow. Iterate using pattern filtering during development, and only run the full suite once everything seems in order.

**IMPORTANT**: Never truncate or pipe test output. Always capture the full test output to see all failures and context.

**FORBIDDEN** patterns when running tests:
- `make test ... | grep` - FORBIDDEN, don't truncate test output
- `make test ... | head` - FORBIDDEN, don't truncate test output
- `make test ... | tail` - FORBIDDEN, don't truncate test output
- `make test ... 2>&1 | grep` - FORBIDDEN, don't truncate test output
- `make test ... 2>&1 | head` - FORBIDDEN, don't truncate test output
- `make test ... 2>&1 | tail` - FORBIDDEN, don't truncate test output

Always run `make test ...` or `make test ... 2>&1` without any pipes.

For changes to neograph (the graph library), also run the compliance suite:

```bash
make test-compliance   # 255 tests covering the full neograph spec
```

## Using Neovim

**FORBIDDEN**: Never invoke `nvim` directly from the command line.

Always use one of:
- `make test` commands for running tests
- The nvim MCP tools (`nvim_init`, `nvim_input`, `nvim_output`) for interactive debugging

The nvim MCP provides a controlled environment with proper plugin loading and state management.

### MCP Hanging / Unresponsive

The MCP may hang when nvim enters a blocking state (e.g., "Press ENTER to continue", confirmation prompts, or error dialogs). This manifests as MCP tool calls appearing to take a long time with no response.

When this happens, kill nvim and remove the socket file:

```bash
tmux kill-session -t nvim_pibub 2>/dev/null
rm -f /tmp/nvim_pibub.sock
```

Then reinitialize with `nvim_init`.

## Logging

**FORBIDDEN**: Never use `print()` or `vim.notify()` for debugging.

Use the neodap logger:

```lua
local log = require("neodap.logger")

log:trace("detailed tracing")
log:debug("debug info", { key = "value" })
log:info("something happened")
log:warn("warning")
log:error("error occurred", { details = "..." })
```

Logs are written to `~/.local/state/nvim/neodap.log`. Use debug/trace logging liberally during development - it doesn't pollute the UI and helps diagnose issues.

View logs:
```bash
tail -f ~/.local/state/nvim/neodap.log
```

## Performance

See `PERF.md` for the profiling procedure. Use `repro.lua` scripts to profile real workloads with the sampling profiler.

## Common Pitfalls

### O(n²) from linear searches

Never iterate through edges to find an entity by property:

```lua
-- BAD: O(n) per lookup, becomes O(n²) when called repeatedly
for source in self.sources:iter() do
  if source.key:get() == key then return source end
end
```

Instead, add an index to the schema and use edge filtering:

```lua
-- In schema.lua: add index
sources = {
  type = "edge",
  target = "Source",
  __indexes = {
    { name = "by_key", fields = { { name = "key" } } },
  }
}

-- GOOD: O(1) lookup via index
for source in self.sources:filter({ filters = {{ field = "key", op = "eq", value = key }} }):iter() do
  return source
end
```
