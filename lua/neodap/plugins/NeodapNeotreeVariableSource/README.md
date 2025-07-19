# NeodapNeotreeVariableSource

A focused plugin that provides a **Neo-tree source** for DAP (Debug Adapter Protocol) variables. This plugin allows you to browse debugging variables in a tree structure using Neo-tree's interface.

## Overview

This plugin does **one thing well**: it provides the data source for Neo-tree to display debugging variables. It doesn't manage UI, windows, or Neo-tree configuration - it simply makes variable data available to Neo-tree.

## Features

- **Tree structure** for debugging scopes and variables
- **Hierarchical expansion** of complex objects and arrays
- **Auto-expansion** of non-expensive scopes (Local, Closure)
- **Real-time updates** when debugging state changes
- **Clean integration** with Neo-tree's existing interface

## Installation & Setup

### 1. Install the Plugin

Add `NeodapNeotreeVariableSource` to your neodap plugin configuration:

```lua
-- In your neodap setup
api:getPluginInstance(require("neodap.plugins.NeodapNeotreeVariableSource"))
```

### 2. Configure Neo-tree

Add the source to your Neo-tree configuration:

```lua
require("neo-tree").setup({
  sources = { 
    "filesystem", 
    "buffers", 
    "git_status",
    "neodap-variable-tree"  -- Add our source
  },
  
  -- Configure the variable tree source
  ["neodap-variable-tree"] = {
    window = {
      position = "float",  -- or "left", "right", "current"
      mappings = {
        ["<cr>"] = "toggle_node",
        ["<space>"] = "toggle_node", 
        ["o"] = "toggle_node",
      },
    },
    -- For floating windows
    popup = {
      size = {
        height = "60%",
        width = "50%", 
      },
      position = "50%", -- center
    },
  },
})
```

## Usage

Once configured, use standard Neo-tree commands:

### Basic Commands

```vim
" Show variables in a floating window
:Neotree float neodap-variable-tree

" Show variables in sidebar
:Neotree show neodap-variable-tree

" Show variables in current window
:Neotree current neodap-variable-tree

" Close the variables window
:Neotree close neodap-variable-tree
```

### With Options

```vim
" Show with specific position
:Neotree left neodap-variable-tree
:Neotree right neodap-variable-tree

" Toggle (close if open, open if closed)
:Neotree toggle neodap-variable-tree
```

## Configuration Examples

### Floating Window (Recommended)

```lua
["neodap-variable-tree"] = {
  window = {
    position = "float",
    mappings = {
      ["<cr>"] = "toggle_node",
      ["<space>"] = "toggle_node",
      ["o"] = "toggle_node",
      ["q"] = "close_window",
    },
  },
  popup = {
    size = {
      height = "70%",
      width = "60%",
    },
    position = "50%",
  },
},
```

### Sidebar

```lua
["neodap-variable-tree"] = {
  window = {
    position = "right",
    width = 40,
    mappings = {
      ["<cr>"] = "toggle_node",
      ["<space>"] = "toggle_node",
    },
  },
},
```

### Split Window

```lua
["neodap-variable-tree"] = {
  window = {
    position = "current",
    mappings = {
      ["<cr>"] = "toggle_node",
      ["<space>"] = "toggle_node",
    },
  },
},
```

## Keymaps

You can add convenient keymaps for quick access:

```lua
-- In your init.lua or keymaps file
vim.keymap.set('n', '<leader>dv', ':Neotree float neodap-variable-tree<CR>', 
  { desc = "Show debug variables" })

vim.keymap.set('n', '<leader>dV', ':Neotree right neodap-variable-tree<CR>', 
  { desc = "Show debug variables in sidebar" })

vim.keymap.set('n', '<leader>dc', ':Neotree close neodap-variable-tree<CR>', 
  { desc = "Close debug variables" })
```

## Integration with Other Plugins

### Window Picker

If you have `nvim-window-picker` installed:

```lua
["neodap-variable-tree"] = {
  window = {
    mappings = {
      ["w"] = "open_with_window_picker",
      ["s"] = "split_with_window_picker", 
      ["v"] = "vsplit_with_window_picker",
    },
  },
},
```

### Custom Actions

```lua
["neodap-variable-tree"] = {
  window = {
    mappings = {
      ["y"] = function(state)
        local node = state.tree:get_node()
        if node.extra and node.extra.value then
          vim.fn.setreg("+", node.extra.value)
          vim.notify("Copied: " .. node.extra.value)
        end
      end,
    },
  },
},
```

## Behavior

### Auto-expansion

- **Local** and **Closure** scopes auto-expand (non-expensive)
- **Global** scope starts collapsed (expensive to load)
- Variables with children can be expanded/collapsed
- Neo-tree manages all expansion state automatically

### Real-time Updates

The plugin automatically updates when:
- Debugger stops at a breakpoint
- You step through code
- Variables change values
- Debugging session ends

### Data Structure

```
▼ Local
    variable1 = "value" : string
    ▶ complexObject = {...} : Object
▼ Closure  
    closureVar = 42 : number
▶ Global
```

## Troubleshooting

### Variables Not Showing

1. **Check if debugging is active**: Variables only show when stopped at a breakpoint
2. **Verify plugin is loaded**: Ensure `NeodapNeotreeVariableSource` is in your plugin list
3. **Check Neo-tree config**: Ensure `"neodap-variable-tree"` is in your sources list

### Tree Not Updating

- The tree updates automatically when debugging state changes
- If it seems stale, try `:Neotree refresh neodap-variable-tree`

### Performance Issues

- Large objects in the Global scope can be slow to expand
- Consider filtering or limiting scope expansion if needed

## Architecture

This plugin follows the **single responsibility principle**:

- **Only provides data** to Neo-tree
- **Does not manage UI** - that's Neo-tree's job  
- **Does not create commands** - use standard Neo-tree commands
- **Does not configure Neo-tree** - users control their own setup

This design ensures:
- ✅ **No conflicts** with existing Neo-tree setups
- ✅ **User control** over interface and behavior  
- ✅ **Standard patterns** that work like other Neo-tree sources
- ✅ **Simple maintenance** with focused responsibilities