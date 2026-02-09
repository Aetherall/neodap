# Neodap Feature Roadmap

## Working Features

### Tree Views
- [x] `<leader>dv` - Frame variables/scopes (with eager expansion, Global collapsed)
- [x] `<leader>df` - Stack frames (`@thread/stacks[0]`)
- [x] `<leader>do` - Stdio output (`@session/stdios`)
- [x] `<leader>dB` - Breakpoints view
- [x] `<leader>dt` - Targets/sessions view

### Navigation
- [x] `gf` on frames - Jump to frame source location
- [x] `gf` on breakpoints - Jump to breakpoint location

### Visual Feedback
- [x] Inline values - Show variable values as virtual text
- [x] Function filtering - Skip function definitions in inline values
- [x] Breakpoint signs - Visual markers in sign column
- [x] Frame highlights - Current frame line highlighting

### Core
- [x] Breakpoint management (`:Dap breakpoint`)
- [x] Step controls (`:Dap step`, `:Dap continue`, etc.)
- [x] Session management

## Missing Features

### Hover & Preview
- [x] `K` hover preview - Show variable value in floating window (via in-process LSP)
  - Configurable keymaps for hover window actions
  - Respects focused frame context in call stack
- [ ] Expression preview - Hover over complex expressions

### Watch Expressions
- [ ] Watch panel - Add custom expressions to monitor
- [ ] Persistent watches across sessions
- [ ] Watch tree view (`<leader>dw`?)

### REPL / Console
- [x] Interactive REPL input buffer (`dap://input/@frame`, `:DapReplLine`)
- [x] Expression evaluation with history
- [x] Completion in REPL (`:DapCompleteEnable`)

### Advanced Breakpoints
- [ ] Conditional breakpoints - Break only when condition is true
- [ ] Hit count breakpoints - Break after N hits
- [ ] Logpoints - Log message without stopping
- [ ] Exception breakpoints - Break on thrown/uncaught exceptions

### Variable Manipulation
- [x] Edit variable values during debugging (`:DapEval`, `e` on Variable in tree)
- [ ] Copy variable value to clipboard

### Session Management
- [ ] Quick restart - Restart current debug config
- [ ] Debug configuration picker
- [ ] Multi-session management UI

### Keybind Suggestions
```lua
-- Step controls (currently use :Dap commands)
<leader>ds  -- step into
<leader>dn  -- step over (next)
<leader>do  -- step out (conflicts with output view)
<leader>dc  -- continue
<leader>dp  -- pause
<leader>dr  -- restart
<leader>dq  -- terminate

-- Views
<leader>dw  -- watch expressions
<leader>de  -- REPL/evaluate
```

## Notes

- Inline values require thread to be in "stopped" state
- Global scope is intentionally not eager-expanded (too many variables)
- Tree views support any entity type as root
