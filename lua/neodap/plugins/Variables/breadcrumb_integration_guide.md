# Breadcrumb Integration Guide

## How to Enable Breadcrumb Navigation

### Step 1: Add to Variables Plugin Constructor

```lua
-- In VariablesTreeNui.plugin()
function VariablesTreeNui.plugin(api)
  local instance = VariablesTreeNui:new({
    api = api,
    current_frame = nil,
    windows = {},
  })

  -- Add breadcrumb navigation
  local BreadcrumbNav = require('neodap.plugins.Variables.breadcrumb_prototype')
  instance.breadcrumb = BreadcrumbNav:new(instance)
  instance.breadcrumb:integrateWithParent()

  instance:setupEventHandlers()
  instance:setupCommands()
  return instance
end
```

### Step 2: Add Toggle Command

```lua
-- Add to setupCommands()
vim.api.nvim_create_user_command("VariablesBreadcrumb", function()
  self.breadcrumb_mode = not self.breadcrumb_mode
  if self.breadcrumb_mode then
    self.breadcrumb:refreshView()
  else
    self:RefreshAllWindows() -- Return to normal tree view
  end
end, { desc = "Toggle breadcrumb navigation mode" })
```

### Step 3: Keybinding Reference

When in breadcrumb mode, users get these additional navigation options:

```
Basic Navigation:
- <CR>, o  : Navigate into node (instead of just expanding)
- u, <BS>  : Go up one level
- b        : Go back to previous location
- r        : Return to root

Quick Jump:
- 1-9      : Jump to nth breadcrumb segment
- /        : Search within current level

Standard:
- q        : Close variables window
```

## Visual Comparison

### Before (Traditional Tree):
```
▾ 󰌾 Local: testDeepNesting
├─▾ 󰆩 complexObject
│ ├─ 󰀫 description: 'Root level'
│ └─▾ 󰆩 level1
│   ├─ 󰀫 data: 'Level 1 data'
│   └─▾ 󰆩 nested1
│     ├─ 󰀫 info: 'Level 2 info'
│     └─▾ 󰆩 nested2
│       ├─▾ 󰅪 array [5 items]  <- Getting cramped
│       └─▸ 󰆩 nested3
```

### After (Breadcrumb Mode):
```
📍 Local > complexObject > level1 > nested1 > nested2
────────────────────────────────────────────────────
▾ 󰆩 nested2
├─▾ 󰅪 array [5 items]
│ ├─ [0]: 10
│ ├─ [1]: 20
│ ├─ [2]: 30
│ ├─ [3]: 40
│ └─ [4]: 50
└─▸ 󰆩 nested3 {2 properties}
```

## Implementation Benefits

1. **Clean View**: No horizontal scrolling at any depth
2. **Context Awareness**: Always know your location
3. **Quick Navigation**: Jump to any ancestor instantly
4. **Familiar UX**: Breadcrumbs are universally understood
5. **Keyboard Friendly**: Efficient hotkeys for power users

## Advanced Features (Future Enhancements)

### Clickable Breadcrumbs
```lua
-- Make breadcrumb segments clickable
local function create_clickable_breadcrumb()
  for i, segment in ipairs(self.current_path) do
    local start_col = -- calculate column position
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "Underlined", 0, start_col, end_col)
    -- Add click handler
  end
end
```

### Search Integration
```lua
-- Global search across all levels
function BreadcrumbVariables:globalSearch(pattern)
  -- Search all variables at all levels
  -- Show results with their full paths
  -- Allow direct navigation to matches
end
```

### Breadcrumb History/Bookmarks
```lua
-- Save favorite locations
function BreadcrumbVariables:addBookmark(name)
  self.bookmarks[name] = vim.deepcopy(self.current_path)
end

function BreadcrumbVariables:goToBookmark(name)
  if self.bookmarks[name] then
    self:navigateToPath(self.bookmarks[name])
  end
end
```

### Smart Previews
```lua
-- Show preview of collapsed nodes
function BreadcrumbVariables:showPreview(node)
  -- Display floating window with node contents
  -- Useful for quick inspection without navigation
end
```

## Migration Strategy

1. **Phase 1**: Add breadcrumb as optional mode (toggle with command)
2. **Phase 2**: Make breadcrumb the default for deep structures (auto-enable at depth > 4)
3. **Phase 3**: Add advanced features (search, bookmarks, previews)
4. **Phase 4**: Consider replacing traditional tree entirely

The breadcrumb approach fundamentally solves the deep nesting readability problem while maintaining all the functionality of the traditional tree view.