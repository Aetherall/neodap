# Plugin Composition Architecture

This document outlines the composable plugin architecture for neodap, designed to separate complex business logic from simple presentation layers.

## Architecture Overview

### Core Principle: Buffer-Centric Services

Services provide **fully functional buffers** with all logic included. Presentation plugins are **trivial wrappers** that just display the buffer in different UI contexts.

```
Service Plugin → Functional Buffer → Presentation Plugin → User Interface
    ↓                   ↓                    ↓                    ↓
Variables4          bufnr + nav         PopupVariables        Popup Window
BreakpointApi       bufnr + mgmt        SidebarBreakpoints    Split Window  
StackTrace          bufnr + frames      OverlayStack          Overlay Region
```

## Plugin Types

### 1. Service Providers (Complex Business Logic)
- **Purpose**: Provide fully functional buffers with complete feature sets
- **Responsibility**: Data fetching, rendering, navigation, state management
- **Examples**: Variables4, BreakpointApi, StackTrace, WatchExpressions

### 2. Presentation Plugins (Simple UI Wrappers)
- **Purpose**: Display service buffers in specific UI contexts
- **Responsibility**: Window creation, basic cleanup, UI-specific options
- **Examples**: PopupVariables, SidebarVariables, OverlayVariables

### 3. Orchestration Plugins (Workflow Coordination)
- **Purpose**: Coordinate multiple services for complete user workflows
- **Responsibility**: Service composition, context management, user commands
- **Examples**: DebugMode, DebugOverlay

## The Buffer Contract

All service providers must implement this interface:

```lua
-- Service Buffer Contract
local buffer_handle = service:createBuffer(context, options)

-- Returns:
-- {
--   bufnr = number,           -- Vim buffer number, ready to display
--   refresh = function(),     -- Update buffer content
--   close = function(),       -- Cleanup buffer and resources
--   metadata = table?         -- Optional state information
-- }
```

## Implementation Guide

### Creating a Service Provider

**File**: `lua/neodap/plugins/VariablesBuffer.lua`

```lua
local BasePlugin = require('neodap.plugins.BasePlugin')
local VariablesBuffer = BasePlugin:extend()

VariablesBuffer.name = "VariablesBuffer"

function VariablesBuffer:createBuffer(frame, options)
  local opts = vim.tbl_extend("force", {
    compact = false,      -- Compact rendering for small spaces
    auto_refresh = false, -- Auto-refresh on frame changes
  }, options or {})
  
  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  
  -- Render tree content
  self:renderTreeToBuffer(bufnr, frame, opts)
  
  -- Setup navigation
  self:setupBufferNavigation(bufnr, frame, opts)
  
  -- Return buffer handle
  return {
    bufnr = bufnr,
    refresh = function()
      self:renderTreeToBuffer(bufnr, frame, opts)
    end,
    close = function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end,
    metadata = {
      frame_id = frame.ref.id,
      compact = opts.compact
    }
  }
end

function VariablesBuffer:setupBufferNavigation(bufnr, frame, opts)
  local map_opts = { buffer = bufnr, noremap = true, silent = true }
  
  vim.keymap.set('n', 'j', function() self:navigateNext(bufnr) end, map_opts)
  vim.keymap.set('n', 'k', function() self:navigatePrev(bufnr) end, map_opts)
  vim.keymap.set('n', 'l', function() self:expandCurrent(bufnr, frame) end, map_opts)
  vim.keymap.set('n', 'h', function() self:collapseCurrent(bufnr, frame) end, map_opts)
  vim.keymap.set('n', '<CR>', function() self:expandCurrent(bufnr, frame) end, map_opts)
  
  -- All tree navigation logic implemented here
end

function VariablesBuffer:renderTreeToBuffer(bufnr, frame, opts)
  -- Implement tree rendering logic
  -- Handle expand/collapse states
  -- Apply compact mode if opts.compact
end

-- Implement navigation methods
function VariablesBuffer:navigateNext(bufnr) -- ... end
function VariablesBuffer:navigatePrev(bufnr) -- ... end  
function VariablesBuffer:expandCurrent(bufnr, frame) -- ... end
function VariablesBuffer:collapseCurrent(bufnr, frame) -- ... end

return VariablesBuffer
```

### Creating a Presentation Plugin

**File**: `lua/neodap/plugins/VariablesPopup.lua`

```lua
local BasePlugin = require('neodap.plugins.BasePlugin')
local Popup = require("nui.popup")

local VariablesPopup = BasePlugin:extend()
VariablesPopup.name = "VariablesPopup"

function VariablesPopup:show(frame, options)
  local opts = vim.tbl_extend("force", {
    width = "80%",
    height = "70%",
    position = "50%",
    title = " Variables Debug Tree "
  }, options or {})
  
  -- Get functional buffer from service
  local variables_service = self.api:getPluginInstance(require('neodap.plugins.VariablesBuffer'))
  local buffer_handle = variables_service:createBuffer(frame, {
    compact = false,
    auto_refresh = opts.auto_refresh
  })
  
  -- Create popup with service buffer
  local popup = Popup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = { top = opts.title, top_align = "center" }
    },
    position = opts.position,
    size = { width = opts.width, height = opts.height },
    bufnr = buffer_handle.bufnr  -- Use service's buffer
  })
  
  popup:mount()
  
  -- Simple cleanup keybinding
  popup:map("n", "q", function()
    buffer_handle.close()
    popup:unmount()
  end, { noremap = true, silent = true })
  
  popup:map("n", "<Esc>", function()
    buffer_handle.close()
    popup:unmount()
  end, { noremap = true, silent = true })
  
  return {
    popup = popup,
    buffer = buffer_handle
  }
end

function VariablesPopup:setupCommands()
  self:registerCommands({
    { "VariablesPopup", function() self:openPopup() end, { desc = "Open variables in popup" } }
  })
end

function VariablesPopup:openPopup()
  -- Get current frame from session context
  local current_frame = self:getCurrentFrame() -- Implement based on your frame tracking
  if not current_frame then
    print("No current frame available")
    return
  end
  
  self:show(current_frame)
end

return VariablesPopup
```

### Creating an Orchestration Plugin

**File**: `lua/neodap/plugins/DebugMode.lua` (integration example)

```lua
local BasePlugin = require('neodap.plugins.BasePlugin')
local DebugMode = BasePlugin:extend()

DebugMode.name = "DebugMode"

function DebugMode:setupCommands()
  self:registerCommands({
    { "DebugModeEnter", function() self:enter() end, { desc = "Enter debug mode" } },
    { "DebugModeExit", function() self:exit() end, { desc = "Exit debug mode" } }
  })
end

function DebugMode:enter()
  -- Setup debug mode keybindings
  self:setupDebugKeybindings()
  print("Debug mode active - Press 'v' for variables, 'b' for breakpoints, 'q' to exit")
end

function DebugMode:setupDebugKeybindings()
  local opts = { noremap = true, silent = true }
  
  -- Variables integration
  vim.keymap.set('n', 'v', function()
    self:showVariables()
  end, opts)
  
  -- Breakpoints integration  
  vim.keymap.set('n', 'b', function()
    self:showBreakpoints()
  end, opts)
  
  -- Exit debug mode
  vim.keymap.set('n', 'q', function()
    self:exit()
  end, opts)
end

function DebugMode:showVariables()
  local current_frame = self:getCurrentFrame()
  if not current_frame then
    print("No current frame available")
    return
  end
  
  -- Choose presentation based on context
  if self.overlay_active then
    -- Show in overlay
    local overlay = self.api:getPluginInstance(require('neodap.plugins.DebugOverlay'))
    overlay:showVariablesInRegion(current_frame, overlay.regions.variables)
  else
    -- Show in popup
    local popup_vars = self.api:getPluginInstance(require('neodap.plugins.VariablesPopup'))
    popup_vars:show(current_frame, { auto_refresh = true })
  end
end

function DebugMode:showBreakpoints()
  -- Similar pattern for breakpoints
  local breakpoints_service = self.api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  -- ... compose with appropriate presentation
end

return DebugMode
```

### Creating an Overlay Integration

**File**: `lua/neodap/plugins/DebugOverlay.lua` (integration example)

```lua
local DebugOverlay = BasePlugin:extend()

DebugOverlay.name = "DebugOverlay"

-- Define overlay regions
DebugOverlay.regions = {
  variables = { row = 2, col = 2, width = 40, height = 20 },
  stack = { row = 2, col = 44, width = 30, height = 15 },
  breakpoints = { row = 18, col = 44, width = 30, height = 8 }
}

function DebugOverlay:showVariablesInRegion(frame, region)
  -- Get functional buffer from service
  local variables_service = self.api:getPluginInstance(require('neodap.plugins.VariablesBuffer'))
  local buffer_handle = variables_service:createBuffer(frame, {
    compact = true  -- Use compact mode for overlay
  })
  
  -- Open window in specific region
  local win = vim.api.nvim_open_win(buffer_handle.bufnr, false, {
    relative = 'editor',
    row = region.row,
    col = region.col,
    width = region.width,
    height = region.height,
    style = 'minimal',
    border = 'rounded'
  })
  
  -- Store for cleanup
  self.active_windows = self.active_windows or {}
  self.active_windows.variables = {
    win = win,
    buffer = buffer_handle
  }
  
  return { win = win, buffer = buffer_handle }
end

function DebugOverlay:show(frame)
  -- Show multiple panels
  self:showVariablesInRegion(frame, self.regions.variables)
  self:showStackInRegion(frame, self.regions.stack)
  self:showBreakpointsInRegion(self.regions.breakpoints)
end

function DebugOverlay:close()
  if not self.active_windows then return end
  
  for name, window_info in pairs(self.active_windows) do
    if window_info.buffer then
      window_info.buffer.close()
    end
    if vim.api.nvim_win_is_valid(window_info.win) then
      vim.api.nvim_win_close(window_info.win, true)
    end
  end
  
  self.active_windows = {}
end

return DebugOverlay
```

## Key Implementation Rules

### ✅ DO

1. **Service owns all complexity**
   - Tree navigation, rendering, state management
   - All keybindings for buffer interaction
   - Data fetching and caching

2. **Presentation stays simple**  
   - Just window/popup creation
   - Basic cleanup on close
   - UI-specific options (size, position)

3. **Use existing plugin system**
   - `api:getPluginInstance(require('path'))` for service access
   - No custom service registries

4. **Pass context explicitly**
   - Services receive frame/context as parameters
   - No shared global state between plugins

### ❌ AVOID

1. **Event-driven communication** - Use direct plugin calls instead
2. **Splitting navigation from service** - Service provides complete experience  
3. **vim.tbl_map with async operations** - Use manual loops for async code
4. **Complex service discovery** - Leverage existing plugin manager

## Migration from Current Variables4

The current Variables4 plugin should be split into:

1. **VariablesBuffer** (service) - Extract all tree logic, keep navigation
2. **VariablesPopup** (presentation) - Move popup creation, use VariablesBuffer 
3. **Update integrations** - DebugMode, DebugOverlay use new split architecture

This preserves all current functionality while enabling new presentation modes and better plugin composition.

## Benefits

- **Clean separation of concerns** - Complex logic isolated in services
- **Consistent user experience** - Same navigation across all UI modes  
- **Easy testing** - Services and presentations can be tested independently
- **Plugin ecosystem growth** - New presentations require minimal code
- **Flexible user workflows** - Mix and match services + presentations via orchestration
