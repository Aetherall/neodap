# Neodap Plugins

Neodap provides a rich set of built-in plugins that add user-facing functionality to the debugging SDK. Each plugin is optional and can be loaded individually based on your needs.

## Table of Contents

- [Loading Plugins](#loading-plugins)
- [Core Plugins](#core-plugins)
  - [auto_context](#auto_context)
  - [auto_stack](#auto_stack)
- [Visual Plugins](#visual-plugins)
  - [breakpoint_signs](#breakpoint_signs)
  - [frame_highlights](#frame_highlights)
  - [exception_highlight](#exception_highlight)
- [Command Plugins](#command-plugins)
  - [dap_breakpoint](#dap_breakpoint)
  - [dap_step](#dap_step)
  - [dap_continue](#dap_continue)
  - [dap_jump](#dap_jump)
  - [dap_context](#dap_context)
  - [dap_variable](#dap_variable)
  - [code_workspace](#code_workspace)
- [Behavior Plugins](#behavior-plugins)
  - [jump_stop](#jump_stop)
- [UI Plugins](#ui-plugins)
  - [tree_buffer](#tree_buffer)
  - [eval_buffer](#eval_buffer)
  - [replline](#replline)
  - [variable_edit](#variable_edit)
  - [variable_completion](#variable_completion)
- [Utility Plugins](#utility-plugins)
  - [output_files](#output_files)
  - [source_buffer](#source_buffer)
  - [neotest](#neotest)
- [Writing Plugins](#writing-plugins)

## Loading Plugins

Plugins are functions that receive the debugger and optional config:

```lua
local debugger = require("neodap")

-- Load with default config
require("neodap.plugins.auto_context")(debugger)

-- Load with custom config
require("neodap.plugins.breakpoint_signs")(debugger, {
  icons = {
    unbound = "○",
    bound = "●",
  },
})
```

### Recommended Plugin Set

For a complete debugging experience:

```lua
-- Core behavior
require("neodap.plugins.auto_context")(debugger)
require("neodap.plugins.auto_stack")(debugger)

-- Visual feedback
require("neodap.plugins.breakpoint_signs")(debugger)
require("neodap.plugins.frame_highlights")(debugger)
require("neodap.plugins.exception_highlight")(debugger)

-- Commands
require("neodap.plugins.dap_breakpoint")(debugger)
require("neodap.plugins.dap_step")(debugger)
require("neodap.plugins.dap_continue")(debugger)
require("neodap.plugins.dap_jump")(debugger)
require("neodap.plugins.jump_stop")(debugger)

-- VSCode integration
require("neodap.plugins.code_workspace")(debugger)
```

---

## Core Plugins

### auto_context

Automatically manages debug context as you navigate between files. The context "follows you" - switching files restores the appropriate debug frame.

**Features:**
- Automatic context tracking via buffer-local context
- Sticky frame behavior for recursive calls
- Updates context when moving to lines with frames
- Stays sticky on same line

**Configuration:**

```lua
require("neodap.plugins.auto_context")(debugger, {
  debounce_ms = 100,  -- Cursor movement debounce (default: 100)
})
```

**Behavior:**
- When you switch to a buffer with debug frames, context updates to the top frame at cursor
- When you move the cursor to a line with frames, context updates
- Context stays pinned when cursor moves on the same line

---

### auto_stack

Automatically fetches stack trace when a thread stops. Ensures frame data is available immediately after breakpoints or stepping.

**Features:**
- Implicit - triggers when any thread stops
- Automatically sets global context to top frame
- No configuration needed

**Usage:**

```lua
require("neodap.plugins.auto_stack")(debugger)
```

---

## Visual Plugins

### breakpoint_signs

Displays breakpoints as inline virtual text icons showing their lifecycle state.

**Features:**
- Inline virtual text icons at breakpoint locations
- Different icons for each state:
  - `●` Unbound (blue) - not yet sent to adapter
  - `◉` Bound/verified (blue) - confirmed by adapter
  - `◐` Adjusted (blue) - adapter moved to different line
  - `◆` Hit (yellow) - currently stopped here
  - `○` Disabled (gray) - breakpoint is disabled
- Respects actual debugger-adjusted positions

**Configuration:**

```lua
require("neodap.plugins.breakpoint_signs")(debugger, {
  icons = {
    unbound = "●",
    bound = "◉",
    adjusted = "◐",
    hit = "◆",
    disabled = "○",
  },
  colors = {
    unbound = "DiagnosticInfo",
    bound = "DiagnosticInfo",
    adjusted = "DiagnosticInfo",
    hit = "DiagnosticWarn",
    disabled = "Comment",
  },
  priority = 20,
  namespace = "dap_breakpoints",
})
```

---

### frame_highlights

Highlights stack frames in source buffers with color-coding by context and stack depth.

**Features:**
- Green highlight for current context frame
- Blue highlights for context session frames (brighter = top of stack)
- Purple highlights for other session frames
- Reactive updates based on context and frame index

**Configuration:**

```lua
require("neodap.plugins.frame_highlights")(debugger, {
  priority = 15,
  namespace = "dap_frame_highlights",
  max_index = 4,  -- Number of gradient levels
})
```

**Highlight Groups:**
- `DapFrameContext` - Current context frame (green)
- `DapFrameSessionTop0-4` - Context session frames (blue gradient)
- `DapFrameOther0-4` - Other session frames (purple gradient)

---

### exception_highlight

Highlights exception locations with red background and shows error message as virtual text.

**Features:**
- Red background highlight on exception line
- Virtual text showing exception message
- Automatic cleanup when thread resumes

**Configuration:**

```lua
require("neodap.plugins.exception_highlight")(debugger, {
  priority = 20,
  namespace = "dap_exception_highlight",
})
```

**Highlight Groups:**
- `DapException` - Red background for exception line
- `DapExceptionText` - Italic text for exception message

---

## Command Plugins

### dap_breakpoint

Provides the `:DapBreakpoint` command for managing breakpoints with column-aware targeting.

**Commands:**

```vim
:DapBreakpoint                    " Toggle breakpoint at cursor
:DapBreakpoint toggle [line:col]  " Explicit toggle with position
:DapBreakpoint condition <expr>   " Set/update condition
:DapBreakpoint log <message>      " Set/update log point
:DapBreakpoint enable             " Enable breakpoint
:DapBreakpoint disable            " Disable breakpoint
```

**Features:**
- Uses `breakpointLocations` DAP request to snap to nearest valid position
- Column-aware targeting for inline breakpoints
- Supports conditions, log messages, and hit conditions

**Configuration:**

```lua
require("neodap.plugins.dap_breakpoint")(debugger, {
  -- Custom selection when multiple breakpoints at location
  select_breakpoint = function(breakpoints, callback)
    -- Default uses vim.ui.select
  end,
  -- Custom position adjustment
  adjust = function(source, pos, callback)
    -- Called to find nearest valid breakpoint location
  end,
})
```

---

### dap_step

Provides the `:DapStep` command with flexible argument order.

**Commands:**

```vim
:DapStep                  " Step over (default)
:DapStep over             " Step over
:DapStep into             " Step into
:DapStep out              " Step out
:DapStep over statement   " Step over by statement
:DapStep into line        " Step into by line
:DapStep instruction      " Step over by instruction
```

**Arguments:**
- **Method**: `over`, `into`, `out`
- **Granularity**: `statement`, `line`, `instruction`
- **URI**: Optional target thread/frame

Arguments can be in any order: `:DapStep line into` works the same as `:DapStep into line`.

**Configuration:**

```lua
require("neodap.plugins.dap_step")(debugger, {
  multi_thread = "context",  -- "context" uses context thread, "pick" shows picker
})
```

---

### dap_continue

Provides the `:DapContinue` command to resume execution.

**Commands:**

```vim
:DapContinue    " Continue execution of context session
```

**Usage:**

```lua
require("neodap.plugins.dap_continue")(debugger)
```

---

### dap_jump

Jump to a debug frame's source location with configurable window selection.

**Commands:**

```vim
:DapJump <uri>    " Jump to frame location
```

**Features:**
- Respects `winfixbuf` setting
- Handles both local files and virtual sources
- Configurable window selection strategy

**Configuration:**

```lua
require("neodap.plugins.dap_jump")(debugger, {
  -- Custom window picker
  select_jump_window = function(callback)
    -- callback(winnr)
  end,
  -- Strategy for winfixbuf windows
  strategy = "error",  -- "always_ask", "ask_on_winfixbuf", "silent", "error"
})
```

---

### dap_context

Manually set debug context via URI picker.

**Commands:**

```vim
:DapContext          " Show session picker
:DapContext <uri>    " Set context to specific entity
```

**Usage:**

```lua
require("neodap.plugins.dap_context")(debugger)
```

---

### dap_variable

Pick and edit variables from current frame.

**Commands:**

```vim
:DapVariable                     " Pick from current frame's variables
:DapVariable @frame/scope:Locals " Pick from specific scope
```

**Usage:**

```lua
require("neodap.plugins.dap_variable")(debugger)
```

---

### code_workspace

Integration with VSCode `.code-workspace` files and `launch.json`.

**Commands:**

```vim
:DapLaunch              " Pick configuration from launch.json
:DapLaunch <name>       " Launch specific configuration by name
```

**Features:**
- Parses VSCode `launch.json` configurations
- Supports compound configurations
- Tab completion for config names
- Variable interpolation (`${file}`, `${workspaceFolder}`, etc.)

**Configuration:**

```lua
require("neodap.plugins.code_workspace")(debugger, {
  path = nil,  -- File path for context (defaults to current buffer)
})
```

---

## Behavior Plugins

### jump_stop

Automatically jump to source location when a thread stops.

**Commands:**

```vim
:DapJumpStop          " Toggle auto-jump
:DapJumpStop on       " Enable
:DapJumpStop off      " Disable
:DapJumpStop status   " Show current state
```

**Configuration:**

```lua
require("neodap.plugins.jump_stop")(debugger, {
  enabled = true,
  scope = "context",  -- "context" or "all" sessions
})
```

---

## UI Plugins

### tree_buffer

Interactive tree exploration buffer for debug entities. Provides a reactive, lazy-loading tree view of sessions, threads, frames, variables, and more.

#### URI Patterns

The tree buffer uses URIs in the format `dap-tree:<pattern>?<options>`.

**Contextual Patterns** (follow global debug context):

```vim
" Session tree - shows threads, breakpoints, outputs, REPL
:vsplit | edit dap-tree:@session

" Frame tree - shows scopes and variables of context frame
:vsplit | edit dap-tree:@frame

" Thread tree - shows stacks and frames
:edit dap-tree:@thread

" Variable tree - shows children of context variable
:edit dap-tree:@variable
```

**Path Navigation** (access nested groups directly):

```vim
" REPL - outputs + evaluations combined, newest first
:vsplit | edit dap-tree:@session/~repl

" Threads only
:edit dap-tree:@session/~threads

" Outputs only (stdout, stderr, console)
:edit dap-tree:@session/~outputs

" Evaluations only
:edit dap-tree:@session/~evaluations

" Breakpoint bindings
:edit dap-tree:@session/~bindings
```

**Explicit URIs** (fixed, don't follow context):

```vim
" Specific session by ID
:edit dap-tree:session:abc123

" Specific variable by URI
:edit dap-tree:variable:dap:session:123/frame:0/scope:Locals/var:myVar
```

**Query Options:**

```vim
" Start with all nodes collapsed
:edit dap-tree:@frame?collapsed

" Preserve focus position when context changes
:edit dap-tree:@session?focus=true

" Combine options
:edit dap-tree:@session/~repl?collapsed&focus=true
```

#### Virtual Groups

Sessions automatically contain virtual group nodes that organize child entities:

| Group | Key | Contents |
|-------|-----|----------|
| **Threads** | `~threads` | All threads in the session |
| **Outputs** | `~outputs` | stdout, stderr, console output (excludes telemetry) |
| **Evaluations** | `~evaluations` | Expression evaluation results |
| **REPL** | `~repl` | Combined outputs + evaluations, newest first |
| **Breakpoints** | `~bindings` | Breakpoint bindings for this session |

#### Node Types

Each entity type has a distinct renderer:

| Type | Icon | Display |
|------|------|---------|
| `debugger` | `` | Root node with session count |
| `session` | `` | Name + state (running/stopped) |
| `thread` | `` | Thread ID, name, state |
| `stack` | `` | Stack index, `*` for current |
| `frame` | `` | Frame ID, function name, source:line |
| `scope` | `` | Scope name (Locals, Globals, etc.) |
| `variable` | `` | name: type = value |
| `source` | `` | Source file name or path |
| `output` | `` | [category] truncated output |
| `evaluate_result` | `` | expression = result : type |
| `binding` | `` | Breakpoint location |
| `group` | `` | Group name + item count |

#### Keybindings

**Navigation:**

| Key | Action |
|-----|--------|
| `j`/`k` | Move up/down (supports counts: `5j`, `10k`) |
| `gg`/`G` | Jump to top/bottom |
| `L` | Move into first child |
| `H` | Move to parent |

**Expand/Collapse:**

| Key | Action |
|-----|--------|
| `Enter`/`Tab`/`o` | Toggle expand/collapse |
| `l` | Expand and move into (fetches lazy children) |
| `h` | Collapse if expanded, else move to parent |

**Actions:**

| Key | Action |
|-----|--------|
| `gd` | Jump to source location (frames, sources) |
| `R` | Refresh tree |
| `q` | Close buffer |
| `?` | Print debug info for focused node |

**Node-Specific Actions:**

| Key | Node Type | Action |
|-----|-----------|--------|
| `i` | `~repl` group | Open floating REPL input (`:DapReplLine`) |

#### Custom Keybinds

Override or add keybindings via configuration. Handlers receive a context object:

```lua
require("neodap.plugins.tree_buffer")(debugger, {
  keybinds = {
    -- Simple function handler (all node types)
    ["<C-r>"] = function(ctx)
      ctx.window:refresh()
      print("Refreshed!")
    end,

    -- Type dispatch table (different action per node type)
    ["<CR>"] = {
      frame = function(entity, ctx)
        -- Jump to frame source on Enter
        if entity.source and entity.source.path then
          vim.cmd("edit " .. vim.fn.fnameescape(entity.source.path))
          vim.api.nvim_win_set_cursor(0, { entity.line or 1, 0 })
        end
      end,
      variable = function(entity, ctx)
        -- Copy variable value on Enter
        vim.fn.setreg("+", entity.value or "")
        print("Copied: " .. (entity.value or ""))
      end,
      default = function(entity, ctx)
        -- Fallback: toggle expand/collapse
        ctx.window:toggle()
      end,
    },

    -- Add yank binding for variables
    ["y"] = {
      variable = function(entity, ctx)
        vim.fn.setreg("+", entity.value or "")
        vim.notify("Yanked: " .. (entity.name or "?"))
      end,
    },
  },
})
```

**Keybind Context:**

```lua
ctx.entity    -- The actual entity from store (has methods like :children())
ctx.wrapper   -- Entity wrapper with _virtual metadata (vuri, depth, path)
ctx.window    -- TreeWindow instance (focus, expand, collapse, etc.)
ctx.debugger  -- Debugger instance
```

#### Configuration

```lua
require("neodap.plugins.tree_buffer")(debugger, {
  -- Indentation per level
  indent = 2,

  -- Icons for entity types and tree structure
  icons = {
    -- Entity types
    debugger = "",
    session = "",
    thread = "",
    stack = "",
    frame = "",
    scope = "",
    variable = "",
    source = "",
    breakpoint = "",
    output = "",
    eval = "",
    binding = "",
    group = "",
    -- Tree structure
    collapsed = "▶",
    expanded = "▼",
    leaf = " ",
    gutter_branch = "├─",
    gutter_last = "╰─",
    gutter_vertical = "│ ",
    gutter_blank = "  ",
  },

  -- Viewport size (items above/below focus)
  above = 50,
  below = 50,

  -- Highlight group definitions
  highlight_defs = {
    DapTreeSession = { link = "Type" },
    DapTreeVariable = { link = "Identifier" },
    DapTreeValue = { link = "String" },
    DapTreeFocused = { link = "CursorLine" },
    -- See source for all highlight groups
  },

  -- Custom keybinds (see above)
  keybinds = {},

  -- Custom renderers per entity type
  renderers = {
    variable = function(entity, ctx)
      return {
        line = {
          { entity.name, "DapTreeVariable" },
          { " = ", "DapTreePunctuation" },
          { entity.value or "", "DapTreeValue" },
        },
        deps = { entity.value },  -- Reactive deps (Signals)
      }
    end,
  },
})
```

#### Example Workflows

**Debug Variable Inspection:**

```vim
" Open frame tree in vertical split
:vsplit | edit dap-tree:@frame?collapsed

" Navigate with j/k, expand with l or Enter
" Variables are lazy-loaded - expand a scope to fetch them
```

**Live REPL View:**

```vim
" Open REPL in horizontal split at bottom
:botright split | edit dap-tree:@session/~repl

" Press 'i' on the REPL group to open floating input
" New evaluations appear at the top automatically
```

**Multi-Session Overview:**

```vim
" Open debugger root to see all sessions
:edit dap-tree:

" Expand sessions to see threads, navigate with H/L
```

**Pinned Session View:**

```vim
" Open specific session that won't change with context
:vsplit | edit dap-tree:session:abc123
```

---

### eval_buffer

Evaluation input buffer with DAP completions.

**URI Formats:**

```vim
:edit dap-eval:@frame                  " Use context frame
:edit dap-eval:session:<id>/frame:<fid> " Explicit frame
:edit dap-eval:@frame?closeonsubmit    " Close after submit
```

**Features:**
- DAP-powered auto-completion
- Trigger characters: `.`, `[`, `(`
- Expression history (Up/Down)
- Multi-line support (Ctrl-Enter)
- Auto-close option

**Configuration:**

```lua
require("neodap.plugins.eval_buffer")(debugger, {
  trigger_chars = {".", "[", "("},
  history_size = 100,
  on_submit = function(expression, frame, result, err)
    -- Called after evaluation
  end,
})
```

---

### replline

Floating 1-line REPL at cursor position.

**Commands:**

```vim
:DapReplLine    " Open floating REPL
```

**Features:**
- Floats at cursor position
- Auto-resizes for multi-line input
- Closes on Escape or window loss
- Uses `dap-eval:` system internally

**Configuration:**

```lua
require("neodap.plugins.replline")(debugger, {
  border = "rounded",
  width = nil,  -- nil = current window width
})
```

**Public API:**

```lua
local replline = require("neodap.plugins.replline")(debugger)
replline.open()
replline.close()
```

---

### variable_edit

Edit variable values in Neovim buffers with state tracking.

**URI Format:**

```vim
:edit dap:@frame/scope:Locals/var:myVar
```

**Features:**
- Buffer states: dirty, detached, expired, diverged
- Warning styles: virtual_text, notify, both, none
- Auto-reload on context change (if clean)
- Save with `:w` to set variable value

**Buffer States:**
- **dirty**: Unsaved local edits
- **detached**: Context changed, URI resolves elsewhere
- **expired**: Original frame no longer exists
- **diverged**: External value changed since edit started

**Configuration:**

```lua
require("neodap.plugins.variable_edit")(debugger, {
  notify_on_save = true,
  notify_on_error = true,
  warning_style = "virtual_text",  -- "virtual_text", "notify", "both", "none"
  on_diverged = function(bufnr, state) end,
  on_expired = function(bufnr, state) end,
  on_detached = function(bufnr, state) end,
  on_save = function(bufnr, variable, new_value) end,
})
```

---

### variable_completion

DAP-powered completions for variable edit buffers.

**Features:**
- Auto-triggered on `.`, `[`, `(`
- Manual trigger via `<C-x><C-u>`
- Maps DAP completion types to vim kinds

**Configuration:**

```lua
require("neodap.plugins.variable_completion")(debugger, {
  trigger_chars = {".", "[", "("},
})
```

---

## Utility Plugins

### output_files

Writes session output to temporary files.

**Features:**
- Writes to `/tmp/dap/session/<id>/stdout` and `stderr`
- Stores paths in `session.output_files`

**Configuration:**

```lua
require("neodap.plugins.output_files")(debugger, {
  base_dir = "/tmp/dap/session",
})
```

---

### source_buffer

URI handler for virtual source files.

**URI Format:**

```vim
:edit dap:source:<correlation_key>
```

**Features:**
- Opens virtual sources from debugger
- Automatic content fetching
- Read-only with syntax highlighting
- Loaded automatically with the debugger singleton

---

### neotest

Integration with [neotest](https://github.com/nvim-neotest/neotest) for debugging tests.

**Features:**
- Implements neotest Process interface
- Captures stdout/stderr to temp files
- Supports before/after hooks

**Configuration in neotest:**

```lua
require("neotest").setup({
  strategies = {
    neodap = require("neodap.plugins.neotest").strategy(debugger)
  }
})
```

---

## Writing Plugins

Plugins are functions that receive the debugger and optional config:

```lua
-- my_plugin.lua
return function(debugger, config)
  config = vim.tbl_extend("force", {
    -- Default config
    enabled = true,
  }, config or {})

  -- Setup resources
  local ns = vim.api.nvim_create_namespace("my_plugin")

  -- React to SDK events
  local unsub_session = debugger:onSession(function(session)
    session:onThread(function(thread)
      thread:onStopped(function(reason)
        if config.enabled then
          -- Do something when thread stops
        end
      end)
    end)
  end)

  -- Create commands
  vim.api.nvim_create_user_command("MyPluginCommand", function(opts)
    -- Command implementation
  end, { nargs = "*" })

  -- Return cleanup function (called on debugger:dispose())
  return function()
    unsub_session()
    vim.api.nvim_del_user_command("MyPluginCommand")
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
  end
end
```

### Plugin Patterns

**Reacting to State Changes:**

```lua
session.state:use(function(state)
  if state == "stopped" then
    -- Handle stopped state
  end
end)
```

**Creating Buffer-Local Features:**

```lua
vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*.py",
  callback = function(args)
    local bufnr = args.buf
    -- Setup buffer-local features
  end,
})
```

**Using the Context System:**

```lua
local ctx = debugger:context(bufnr)
ctx.frame_uri:use(function(uri)
  if uri then
    local frame = debugger:resolve_one(uri)
    -- React to context frame changes
  end
end)
```

**Creating Special Buffer Types:**

```lua
vim.api.nvim_create_autocmd("BufReadCmd", {
  pattern = "myscheme:*",
  callback = function(args)
    local bufnr = args.buf
    vim.bo[bufnr].buftype = "acwrite"
    vim.bo[bufnr].swapfile = false
    -- Populate buffer content
  end,
})
```
