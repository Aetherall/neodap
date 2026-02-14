# Value Density Refactoring Tasks

Audit-driven refactoring to maximize code value density in neodap.
Track progress by checking boxes. Each task includes precise file locations
and code snippets to allow context-free implementation.

---

## P0 — Architecture Violations & Performance

### T1: Fix entities importing `plugins.dap.context` ✅ → [ ]

**Problem**: Core entities depend on plugin-layer code — an architecture violation.
Entities must never import plugins. Both `Config:terminate()` and `Session:restartRoot()`
reach into `plugins.dap.context` to get raw DapSession objects.

**Files**:
- `lua/neodap/entities/config.lua:63-75` — `Config:terminate()` calls `dap_context.dap_sessions[session]` and `dap_session:terminate()` directly
- `lua/neodap/entities/session.lua:171-178` — `Session:restartRoot()` calls `dap_context.dap_sessions[root]` and `dap_session:terminate()` directly

**Fix**: Both should call `session:terminate()` (the entity method defined in `plugins/dap/session.lua:29-39`).
That method already handles `mark_terminating` + `dap_session:terminate()` + state update.

**Config:terminate()** — Replace lines 63-75 with:
```lua
function Config:terminate()
  for session in self.sessions:iter() do
    if session.state:get() ~= "terminated" then
      pcall(function() session:terminate() end)
    end
  end
end
```

**Session:restartRoot()** — Replace lines 171-178 with:
```lua
pcall(function() root:terminate() end)
```

**Note**: `Session:terminate()` is an async function (wrapped with `a.fn`). When called from
a non-coroutine context, `a.fn` wraps it to run in a new coroutine, so `pcall` will catch
synchronous errors. The terminate itself runs async. This is fine for fire-and-forget termination.

---

### T2: Add `context` parameter to `Frame:evaluate()` ✅ → [ ]

**Problem**: `Frame:evaluate()` in `plugins/dap/frame.lua:95` hardcodes `context = "repl"`.
The hover plugin (`plugins/hover.lua:170-214`) can't use it, so it bypasses the entity layer
entirely with a raw `dap_session.client:request("evaluate", ...)`.

**Files**:
- `lua/neodap/plugins/dap/frame.lua:70-175` — `Frame:evaluate()` method
- `lua/neodap/plugins/hover.lua:121-214` — `evaluate_for_hover()` function

**Fix for frame.lua**:
1. Change the `@param opts` annotation to include `context`:
   ```lua
   ---@param opts? { silent?: boolean, context?: string }
   ```
2. At line 95, change `context = "repl"` to:
   ```lua
   context = opts and opts.context or "repl",
   ```
3. Also apply to `Frame:variable()` at lines 260 and 277 (both hardcode `context = "repl"`):
   ```lua
   context = "repl",  -- variable resolution always uses repl context
   ```
   (These stay as-is since variable resolution is always "repl".)

**Fix for hover.lua**:
Replace `evaluate_for_hover()` (lines 121-215) to use `Frame:evaluate()`:
```lua
local function evaluate_for_hover(expression, callback)
  local frame = debugger.ctx.frame:get()
  if not frame then
    -- fallback to top frame from focused thread
    local thread = debugger.ctx.thread:get()
    if not thread or not thread:isStopped() then callback(nil) return end
    local stack = thread.stack:get()
    if not stack then callback(nil) return end
    frame = stack.topFrame:get()
  end
  if not frame then callback(nil) return end

  -- Use Frame:evaluate with hover context (async, fire callback)
  local a = require("neodap.async")
  a.run(function()
    local result, _, vtype = frame:evaluate(expression, { context = "hover", silent = true })
    vim.schedule(function()
      if not result then callback(nil) return end
      local lines = {}
      if vtype and vtype ~= "" then
        table.insert(lines, string.format("**%s** `%s`", expression, vtype))
      else
        table.insert(lines, string.format("**%s**", expression))
      end
      table.insert(lines, "```")
      table.insert(lines, tostring(result))
      table.insert(lines, "```")
      callback(table.concat(lines, "\n"))
    end)
  end, function()
    vim.schedule(function() callback(nil) end)
  end)
end
```
Remove the `require("neodap.plugins.dap.context")` import from hover.lua.

---

### T3: Use `by_threadId` index in `Session:findThreadById()` ✅ → [ ]

**Problem**: `entities/session.lua:42-47` does O(n) linear scan. Schema defines `by_threadId` index
at `schema.lua:458`. Called 7+ times per stop/continue event across the codebase.

**File**: `lua/neodap/entities/session.lua:42-48`

**Current**:
```lua
function Session:findThreadById(threadId)
  for thread in self.threads:iter() do
    if thread.threadId:get() == threadId then
      return thread
    end
  end
end
```

**Fix**:
```lua
function Session:findThreadById(threadId)
  for thread in self.threads:filter({
    filters = {{ field = "threadId", op = "eq", value = threadId }}
  }):iter() do
    return thread
  end
end
```

---

## P1 — Duplicated Code Extraction

### T4: Extract `utils/expression.lua` from hover + expression_edit ✅ → [ ]

**Problem**: Near-identical treesitter expression extraction in two files.

**Files**:
- `lua/neodap/plugins/hover.lua:56-116` — `get_expression_at_position(bufnr, row, col)`
- `lua/neodap/plugins/expression_edit.lua:18-98` — `get_expression_at_cursor()`

**Create**: `lua/neodap/plugins/utils/expression.lua`

The shared module should expose:
- `M.get_expression_at_position(bufnr, row, col, opts)` — treesitter + fallback, returns `string?`
  - `opts.include_calls` — include `call_expression` (expression_edit needs it, hover doesn't)
  - `opts.dotted_fallback` — use dotted expression scanning vs simple word scanning
- `M.get_expression_at_cursor(opts)` — convenience wrapper using current buf/cursor
- `M.get_visual_selection()` — moved from expression_edit.lua:102-119

Then update both consumers to use the shared module.

---

### T5: Extract edit buffer helpers from variable_edit + expression_edit ✅ → [ ]

**Problem**: `update_indicator()`, submit pattern, keymaps, and TextChanged autocmds
are character-for-character identical across both files.

**Files**:
- `lua/neodap/plugins/variable_edit.lua:35-60` — `update_indicator()`
- `lua/neodap/plugins/expression_edit.lua:140-163` — `update_indicator()`
- Both: keymaps `<CR>`, `<C-s>`, `u`, `q` + TextChanged autocmd + submit with saved/error indicator

**Create**: `lua/neodap/plugins/utils/edit_buffer.lua`

The shared module should expose:
- `M.update_indicator(bufnr, ns_id, debugger, entity, status)` — virtual text indicator
- `M.setup_keymaps(bufnr, opts)` — `<CR>`, `<C-s>` → submit, `u` → reset, `q` → close
- `M.setup_dirty_tracking(bufnr, ns_id, debugger, get_entity_fn)` — TextChanged autocmd
- `M.async_submit(bufnr, ns_id, debugger, fn)` — wraps a.run + indicator update pattern

Then rewrite both plugins to use these shared helpers.

---

### T6: Collapse `gd`/`gf` copy-paste in keybinds.lua → use actions ✅ → [ ]

**Problem**: `tree_buffer/keybinds.lua:101-141` has 4 identical copies of the "go to source" handler.
The existing `focus_and_jump` action in `presentation/actions.lua:99-118` does the same thing.

**Files**:
- `lua/neodap/plugins/tree_buffer/keybinds.lua:101-141`
- `lua/neodap/presentation/actions.lua:99-118` — `focus_and_jump` for Frame

**Fix**:
1. Register a `goto_source` action for Frame and Breakpoint in `actions.lua`:
   ```lua
   ra(debugger, "goto_source", "Frame", function(frame, ctx)
     local src = frame.source:get()
     if src then
       navigate.goto_location(src, { line = frame.line:get() or 1 }, ctx and ctx.opts)
     end
   end)

   ra(debugger, "goto_source", "Breakpoint", function(bp, ctx)
     local src = bp.source:get()
     if src then
       navigate.goto_location(src, { line = bp.line:get() or 1 }, ctx and ctx.opts)
     end
   end)
   ```
2. Replace the 4 identical handlers in keybinds.lua with:
   ```lua
   ["gd"] = function(ctx)
     if ctx.entity then ctx.debugger:action("goto_source", ctx.entity, { opts = { pick_window = true } }) end
   end,
   ["gf"] = function(ctx)
     if ctx.entity then ctx.debugger:action("goto_source", ctx.entity, { opts = { pick_window = true } }) end
   end,
   ```

**Note**: Check what `navigate.goto_location` expects vs `src:open()`. If they have different
signatures, the action handler should use `src:open()` since that's what the current code uses.
Alternatively, check `utils/navigate.lua` for `goto_location` or `goto_frame`.

---

### T7: Register lifecycle actions in the action registry ✅ → [ ]

**Problem**: Thread lifecycle (continue, pause, step*), session lifecycle (terminate, disconnect),
and scope refresh are inline in keybinds.lua, unreachable by other UI surfaces.

**Files**:
- `lua/neodap/plugins/tree_buffer/keybinds.lua:159-234` — inline Thread/Session keybinds
- `lua/neodap/presentation/actions.lua` — action registry (missing these)

**Add to `actions.lua`**:
```lua
-- Thread lifecycle
ra(debugger, "continue", "Thread", function(thread) thread:continue() end)
ra(debugger, "pause", "Thread", function(thread) thread:pause() end)
ra(debugger, "step_over", "Thread", function(thread) thread:stepOver() end)
ra(debugger, "step_in", "Thread", function(thread) thread:stepIn() end)
ra(debugger, "step_out", "Thread", function(thread) thread:stepOut() end)

-- Session lifecycle
ra(debugger, "terminate", "Session", function(session) session:terminate() end)
ra(debugger, "disconnect", "Session", function(session) session:disconnect() end)

-- Scope refresh
ra(debugger, "refresh", "Scope", function(scope) scope:fetchVariables() end)

-- Config
ra(debugger, "toggle_view_mode", "Config", function(cfg)
  local new_mode = cfg:toggleViewMode()
  vim.notify("View mode: " .. new_mode)
end)
```

Then update `keybinds.lua` to use `debugger:action()` calls instead of inline method calls.

---

## P2 — Missing Entity Methods & Shared Utils

### T8: Add `Session:clearHitBreakpoints()` entity method ✅ → [ ]

**Problem**: The pattern of iterating `session.sourceBindings → breakpointBindings` to clear
`hit = false` is duplicated inline at `dap/init.lua:56-62` and `:116-122`.

**Files**:
- `lua/neodap/plugins/dap/init.lua:56-62` (stopped handler)
- `lua/neodap/plugins/dap/init.lua:116-122` (continued handler)

**Fix**: Add method to `lua/neodap/plugins/dap/session.lua`:
```lua
function Session:clearHitBreakpoints()
  for source_binding in self.sourceBindings:iter() do
    for bp_binding in source_binding.breakpointBindings:iter() do
      if bp_binding.hit:get() then
        bp_binding:update({ hit = false })
      end
    end
  end
end
```
Then call `session:clearHitBreakpoints()` at both sites in `dap/init.lua`.

---

### T9: Add `ExceptionFilter:syncAllSessions()` entity method ✅ → [ ]

**Problem**: The pattern "toggle EF, then sync all session bindings" is duplicated in
`exception_cmd.lua:67-74` and `actions.lua:37-43`.

**Files**:
- `lua/neodap/plugins/exception_cmd.lua:67-74`
- `lua/neodap/presentation/actions.lua:37-43`

**Fix**: Add to either `entities/exception_filter.lua` (if it exists) or inline in
the DAP plugin module where other entity methods are attached.

Since ExceptionFilter methods aren't currently in a separate file, add the method in
a natural location. Check if `entities/exception_filter.lua` has methods or just the entity def.

```lua
function ExceptionFilter:syncAllSessions()
  for binding in self.bindings:iter() do
    local session = binding.session and binding.session:get()
    if session then session:syncExceptionFilters() end
  end
end
```

Then update both call sites to use `ef:syncAllSessions()`.

---

### T10: Use `by_filterId` index in exception filter lookup ✅ → [ ]

**Problem**: `dap/utils.lua:106-111` does O(n) linear scan when `by_filterId` index exists.

**File**: `lua/neodap/plugins/dap/utils.lua:106-111`

**Current**:
```lua
for existing in debugger.exceptionFilters:iter() do
  if existing.filterId:get() == filter.filter then
    ef = existing
    break
  end
end
```

**Fix**:
```lua
for existing in debugger.exceptionFilters:filter({
  filters = {{ field = "filterId", op = "eq", value = filter.filter }}
}):iter() do
  ef = existing
  break
end
```

---

### T11: Extract `utils/open.lua` for split dispatch ✅ → [ ]

**Problem**: The split dispatch pattern (`split`→`split`, `vertical`→`vsplit`, `tab`→`tabedit`,
default→`edit`) is duplicated across 3+ plugins.

**Files**:
- `lua/neodap/plugins/console_buffer.lua` — look for split dispatch
- `lua/neodap/plugins/stdio_buffers.lua:42-53` — if/elseif chain
- `lua/neodap/plugins/preview_handler.lua` — look for split dispatch

**Create**: `lua/neodap/plugins/utils/open.lua`
```lua
local M = {}

local split_cmds = {
  horizontal = "split",
  vertical = "vsplit",
  tab = "tabedit",
}

function M.open(uri, opts)
  opts = opts or {}
  local cmd = split_cmds[opts.split] or "edit"
  vim.cmd(cmd .. " " .. vim.fn.fnameescape(uri))
end

return M
```

Then update consumers.

---

## P3 — Cleanup & Minor Issues

### T12: Add missing cleanup functions ✅ → [ ]

**Problem**: Several plugins create user commands but don't clean them up.

**Files to check and fix**:
- `lua/neodap/plugins/dap_log.lua` — creates `DapLog` (~line 209), no cleanup
- `lua/neodap/plugins/console_buffer.lua` — creates `DapConsole`/`DapTerminal`, no cleanup
- `lua/neodap/plugins/stdio_buffers.lua` — creates `DapOutput`, no cleanup

**Fix**: Add `cleanup()` function to the returned API in each plugin that
does `pcall(vim.api.nvim_del_user_command, "CommandName")` for each command.

---

## Implementation Notes

### Running tests
After each change, run targeted tests:
```bash
make test "pattern"    # pattern-filtered run during development
make test              # full suite after all changes
```

### Key file cross-reference
| Module | Path | Purpose |
|--------|------|---------|
| Entity buffer framework | `lua/neodap/plugins/utils/entity_buffer.lua` | Buffer lifecycle for entity data |
| Presentation system | `lua/neodap/presentation/{init,components,actions}.lua` | Component/action registry |
| URI system | `lua/neodap/uri.lua` | Entity identity + resolution |
| DAP context | `lua/neodap/plugins/dap/context.lua` | Session↔DapSession mapping |
| DAP session methods | `lua/neodap/plugins/dap/session.lua` | `Session:terminate()`, `:disconnect()`, etc. |
| DAP frame methods | `lua/neodap/plugins/dap/frame.lua` | `Frame:evaluate()`, `:fetchScopes()`, etc. |
| Schema | `lua/neodap/schema.lua` | All entity types, edges, indexes |
| Navigate utils | `lua/neodap/plugins/utils/navigate.lua` | `goto_frame`, `goto_location` |
| Tree keybinds | `lua/neodap/plugins/tree_buffer/keybinds.lua` | Tree buffer key handlers |
| Exception cmd | `lua/neodap/plugins/exception_cmd.lua` | Exception filter commands |
| Hover plugin | `lua/neodap/plugins/hover.lua` | LSP hover for DAP values |
| Expression edit | `lua/neodap/plugins/expression_edit.lua` | Edit expression values |
| Variable edit | `lua/neodap/plugins/variable_edit.lua` | Edit variable values |

### Dependency order
Tasks can be done in any order, but some logical groupings:
- T1, T2, T3 are independent P0 fixes
- T4, T5 are extractions that T6 may reference
- T6, T7 both modify keybinds.lua and actions.lua — do together
- T8, T9, T10 are independent entity method additions
- T11, T12 are independent minor improvements
