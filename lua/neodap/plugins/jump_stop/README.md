# jump_stop Plugin

Automatically jumps to source location when a debug thread stops (breakpoint hit, step completed, etc.).

## Configuration

```lua
require("neodap.plugins.jump_stop")(debugger, {
  enabled = true,       -- Initial enabled state
  create_window = nil,  -- Fallback when no suitable window exists (default: vsplit)
  pick_window = nil,    -- Full override for window selection (see below)
})
```

## Commands

- `:DapJumpStop` - Toggle auto-jump on/off
- `:DapJumpStop on` - Enable auto-jump
- `:DapJumpStop off` - Disable auto-jump
- `:DapJumpStop status` - Show current state

## Navigation Architecture

This plugin is part of neodap's navigation system, which separates two concerns:

### 1. Logical Focus (`debugger.ctx`)

Tracks which debug entity is "active" - used by plugins to know which context to operate on:

- `debugger.ctx.session:get()` - Currently focused session
- `debugger.ctx.thread:get()` - Currently focused thread
- `debugger.ctx.frame:get()` - Currently focused frame
- `debugger.ctx:focus(uri)` - Set focus to an entity

### 2. Window Focus (Neovim windows)

Managed by `navigate.lua` - decides which window to open source files in and whether to steal focus.

## Window Selection Flow

```
Thread stops (breakpoint/step)
         │
         ▼
┌─────────────────────────────────────────────────┐
│  jump_stop plugin                               │
│  - Detects stop via thread:onStopped()          │
│  - Loads stack, gets top frame location         │
│  - Calls navigate.goto_frame(frame, pick_window)│
└─────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────┐
│  navigate.lua (default_pick_window)             │
│                                                 │
│  Decision tree:                                 │
│  1. Is file already open in a window? → use it │
│  2. Am I in a DAP window (tree/repl)?          │
│     YES → find non-DAP window, focus=false     │
│     NO  → use current window, focus=true       │
│  3. No suitable window? → create vsplit        │
└─────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────┐
│  goto_location()                                │
│  - Opens file in target window                  │
│  - Sets cursor to line/column                   │
│  - If focus=false, restores original window     │
└─────────────────────────────────────────────────┘
```

## Context-Aware Behavior

The default window picker respects the user's current context:

| If you're in...  | When thread stops...                | Rationale                          |
|------------------|-------------------------------------|------------------------------------|
| Source file      | Jump to location, stay there        | You're "code browsing"             |
| Tree buffer      | Update source, stay in tree         | You're "controlling the session"   |
| REPL             | Update source, stay in REPL         | You're "evaluating expressions"    |

This is why tree buffer keybinds have two variants:
- `n` / `s` / `S` - step and stay in tree (rapid stepping)
- `gn` / `gs` / `gS` - step and go to source (switch context)

## Customization

### `create_window` - Simple Fallback

Use `create_window` to customize how a new window is created when no suitable window exists.
This keeps the default DAP-aware logic but lets you integrate with window management plugins:

```lua
require("neodap.plugins.jump_stop")(debugger, {
  create_window = function()
    -- Use edgy.nvim, focus.nvim, or any window manager
    -- Must return a window ID
    vim.cmd("botright vsplit")
    return vim.api.nvim_get_current_win()
  end
})
```

### `pick_window` - Full Override

Use `pick_window` for complete control over window selection. This bypasses all default logic:

```lua
require("neodap.plugins.jump_stop")(debugger, {
  pick_window = function(path, line, column)
    -- Return window ID to jump there
    return vim.api.nvim_get_current_win()

    -- Or return table with focus control
    return { win = some_window_id, focus = false }

    -- Or return nil to skip the jump entirely
    return nil
  end
})
```

### Return Values

| Return value                  | Behavior                                      |
|-------------------------------|-----------------------------------------------|
| `number`                      | Open file in that window, focus it            |
| `{ win = id, focus = true }`  | Open file in window, focus it                 |
| `{ win = id, focus = false }` | Open file in window, stay in current window   |
| `nil`                         | Skip the jump entirely                        |

## DAP Window Detection

Windows are identified as "DAP windows" by their buffer filetype:

- `dap-tree` - Tree buffer
- `dap-repl` - REPL buffer
- `dap-var` - Variable inspection buffer
- `dap-input` - Input prompt buffer

The default picker avoids these windows when looking for a place to show source files.
