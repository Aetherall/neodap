# Neovim MCP Usage Guide

This document describes how to interact with Neovim through the MCP (Model Context Protocol) server.

## Starting a Session

Use `nvim_start` to initialize a Neovim session. This is idempotent - safe to call multiple times.

## Available Tools

| Tool | Purpose |
|------|---------|
| `nvim_start` | Initialize Neovim session |
| `nvim_reload` | Restart session (reloads all Lua) |
| `nvim_keys` | Send keystrokes (motions, special keys) |
| `nvim_cmd` | Execute Ex commands (`:command`) |
| `nvim_type` | Type literal text |
| `nvim_screen` | Capture current screen state |
| `nvim_edit` | Open a file at a specific line |

## Rules

**DO NOT use Lua directly in the MCP.**

Only use:
- **Vim motions** via `nvim_keys` (e.g., `j`, `k`, `gg`, `G`, `w`, `b`)
- **Ex commands** via `nvim_cmd` (e.g., `:DapLaunch`, `:DapStep over`)
- **Text input** via `nvim_type` for insert mode content

### Allowed

```
nvim_cmd("DapLaunch")
nvim_cmd("DapStep over")
nvim_cmd("DapBreakpoint")
nvim_keys(["j", "j", "k"])
nvim_keys(["G"])
nvim_type("hello world")
```

### Forbidden

```
nvim_cmd("lua print('hello')")
nvim_cmd("luafile script.lua")
nvim_source_lua("script.lua")
```

## Debug Commands

| Command | Description |
|---------|-------------|
| `:DapLaunch [name]` | Launch debug config from launch.json |
| `:DapBreakpoint` | Toggle breakpoint at cursor |
| `:DapStep [over\|into\|out]` | Step debugger |
| `:DapContinue` | Continue execution |
| `:DapJump <uri>` | Jump to a debug frame |
| `:DapContext <uri>` | Set debug context |
| `:DapJumpStop [on\|off]` | Toggle auto-jump on stop |

## Visual Indicators

| Indicator | Meaning |
|-----------|---------|
| Green highlight | Current context frame |
| Blue highlight | Stack frames in context session |
| Purple highlight | Stack frames in other sessions |
| **Red highlight + virtual text** | Exception stop (shows error message) |

## Workflow Example

1. Start session: `nvim_start`
2. Open file: `nvim_edit("src/main.py", 10)`
3. Set breakpoint: `nvim_cmd("DapBreakpoint")`
4. Launch debugger: `nvim_cmd("DapLaunch")`
5. Step through: `nvim_cmd("DapStep over")`
6. Continue execution: `nvim_cmd("DapContinue")`
7. Check screen: `nvim_screen`


Claude Session that understood neostate 6a12507a-1985-4464-8135-46ee0d072747
