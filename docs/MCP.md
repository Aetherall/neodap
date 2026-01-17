# MCP.md

Guide for using the Neovim MCP (Model Context Protocol) to test and demo neodap.

## Overview

The nvim MCP allows Claude Code to control a headless Neovim instance. It simulates real user interaction for testing the debugger UI and workflows.

## Configuration

The `.nvimmcp` file in the project root configures the session:

```json
{
  "session": "nvim_<unique_id>",
  "width": 60,
  "height": 25
}
```

- **session**: Unique identifier linking to the Neovim instance
- **width/height**: Terminal dimensions for screen captures

## Auto-Loading

When `nvim_start` connects, `run.lua` is automatically loaded. This script:

- Adds neodap and neograph to runtimepath
- Creates demo files at `/tmp/neodap-demo/` (demo.js, demo.py, launch.json)
- Configures debug adapters (pwa-node, python)
- Loads all neodap plugins
- Opens the demo file with a breakpoint on line 12

No manual sourcing required.

## Available Commands

| Command | Description |
|---------|-------------|
| `nvim_start` | Initialize/connect to the Neovim session |
| `nvim_reload` | Restart session to reload changed Lua files |
| `nvim_screen` | Capture current screen with ANSI colors |
| `nvim_keys` | Send keystrokes |
| `nvim_cmd` | Execute Ex commands (`:command`) |
| `nvim_edit` | Open a file at a specific line |
| `nvim_type` | Type literal text in insert mode |

### nvim_keys Examples

```
["Escape"]           -- Exit insert mode
["i"]                -- Enter insert mode
["d", "d"]           -- Delete line
["g", "g"]           -- Go to top
["G"]                -- Go to bottom
[" ", "b"]           -- <leader>b (toggle breakpoint, if leader=space)
["F5"]               -- Continue debugging
["F10"]              -- Step over
["F11"]              -- Step into
["F12"]              -- Step out
["C-w", "l"]         -- Window right
["C-w", "h"]         -- Window left
["Enter"]            -- Confirm/newline
["Tab"]              -- Tab key
```

### nvim_cmd Examples

```
:DapLaunch                    -- Pick and launch debug config
:DapLaunch Debug JS File      -- Launch specific config by name
:DapBreakpoint                -- Toggle breakpoint at cursor
:DapBreakpoint clear          -- Clear all breakpoints
:edit /path/to/file.lua       -- Open a file
:w                            -- Save
:q                            -- Quit
```

## Usage Principles

### DO: Interact Like a User

- Use `nvim_screen` to observe visual state
- Use `nvim_keys` to simulate keypresses
- Use `nvim_cmd` for Ex commands the user would type
- Use `nvim_edit` to navigate to files
- Use `nvim_type` to enter text

### DON'T: Access Internals

- Never use `:lua ...` commands to inspect state
- Never run arbitrary Lua to query entities
- Never bypass the UI to check internal data

The goal is to validate the **user experience**, not internal implementation.

## Workflow

### Starting a Demo Session

1. **Connect to session**
   ```
   nvim_start
   ```
   Session is ready with run.lua loaded, demo file open, breakpoint set.

2. **View initial state**
   ```
   nvim_screen
   ```

3. **Launch debugger**
   ```
   nvim_cmd: ":DapLaunch"
   ```
   Or with specific config:
   ```
   nvim_cmd: ":DapLaunch Debug JS File"
   ```

4. **Interact with debugger**
   ```
   nvim_keys: ["F5"]      -- Continue
   nvim_keys: ["F10"]     -- Step over
   nvim_keys: ["F11"]     -- Step into
   ```

5. **Check visual feedback**
   ```
   nvim_screen
   ```

### After Code Changes

When you modify neodap Lua files:

```
nvim_reload
```

This restarts the session and re-runs run.lua to pick up your changes.

### Testing Breakpoints

```
nvim_edit: file="/tmp/neodap-demo/demo-files/demo.js", line=15
nvim_keys: [" ", "b"]     -- Toggle breakpoint (leader + b)
nvim_screen               -- Verify breakpoint sign appears
```

### Testing Variable Inspection

During a debug session, after hitting a breakpoint:

```
nvim_screen               -- See variables in tree buffer
nvim_keys: ["j", "j"]     -- Navigate down
nvim_keys: ["Enter"]      -- Expand/collapse
nvim_screen               -- Verify expansion
```

## Environment Variables

Configure run.lua behavior:

| Variable | Default | Description |
|----------|---------|-------------|
| `DEMO_LANG` | `node` | Default language (`node` or `python`) |
| `JSDBG_PATH` | `js-debug` | Path to js-debug adapter |
| `DEBUGPY_PATH` | (none) | Path to debugpy for Python debugging |

## Troubleshooting

### Session not responding

```
nvim_reload
```

### Screen looks wrong

Check dimensions in `.nvimmcp` match your expectations.

### Changes not reflected

After editing any Lua file in neodap:

```
nvim_reload
```

### Debug adapter not starting

Check environment variables `JSDBG_PATH` or `DEBUGPY_PATH` are set correctly for the demo environment.
