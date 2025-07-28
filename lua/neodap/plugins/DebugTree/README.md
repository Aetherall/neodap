# DebugTree Plugin - Unified DAP Hierarchy Navigation

DebugTree generalizes Variables4's sophisticated features to the **entire DAP debugging hierarchy**. It provides a unified tree interface for navigating Sessions → Threads → Stacks → Frames → Scopes → Variables with Variables4-level sophistication throughout.

## Core Concept

Instead of separate interfaces for different debugging aspects, DebugTree provides **one unified tree** that can display any level of the DAP hierarchy with consistent, advanced navigation and rendering.

```
📡 Session 1 (1 child sessions, 2 threads)
├── 📡 Session 2 (1 threads)
│   └── ▶️ Thread 3 (stopped)
│       └── 📚 Call Stack (2 frames)
│           └── 📄 childProcess() @ worker.js:10
├── ▶️ Thread 1 (stopped)
│   └── 📚 Call Stack (3 frames)
│       ├── 📄 testVariables() @ complex.js:42
│       │   ├── 📁 Local: testVariables
│       │   │   ├── 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]
│       │   │   ├── ◐ booleanVar: true
│       │   │   └── 󰅩 objectVar: {name: 'Test Object'...}
│       │   └── 📁 Global
│       ├── 📄 main() @ app.js:15
│       └── 📄 <anonymous> @ index.js:1
└── ▶️ Thread 2 (running)
```

## Key Features

### **🌳 Unified Hierarchy Navigation**
- **Any Level Entry**: Start at Session, Thread, Stack, Frame, or Variable level
- **Hierarchical Sessions**: Full support for child debug sessions (DAP `startDebugging`)
- **Seamless Navigation**: Move between hierarchy levels with consistent vim-style keys
- **Smart Expansion**: Auto-expand to relevant depth based on context

### **🎨 Variables4-Level Sophistication**
- **Advanced Rendering**: UTF-8 tree characters, rich icons, smart highlighting
- **AsNode() Caching**: Efficient node creation and caching for all DAP entities
- **Lazy Resolution**: Intelligent loading of expensive DAP data
- **Focus Mode**: Variables4's sophisticated focus and viewport management

### **🔄 NUI Tree Integration**
- **Reactive Updates**: Leverages NUI Tree's built-in reactivity
- **Efficient Rendering**: Only re-renders changed portions
- **State Preservation**: Maintains expansion state, cursor position across updates

## Commands

### **Tree Commands**
```vim
:DebugTree          " Open at session level (auto-detect best starting point)
:DebugTreeSession   " Open at session level (see all threads)
:DebugTreeThread    " Open at thread level (see call stack)
:DebugTreeStack     " Open at stack level (see all frames)
:DebugTreeFrame     " Open at frame level (equivalent to Variables4Tree)
```

### **Navigation Keys**
```
h/j/k/l    " Vim-style navigation
<CR>/l     " Expand nodes
h          " Collapse or move to parent
f          " Focus mode (Variables4 feature)
r          " Refresh tree
q/Esc      " Close tree
?          " Help
```

## Architecture

### **AsNode() Extension Strategy**
DebugTree extends **all** DAP entities with `asNode()` methods:

```lua
-- Session level
session:asNode()  -- "📡 Session 1 (2 threads)"

-- Thread level  
thread:asNode()   -- "⏸️ Thread 1 (stopped)"

-- Stack level
stack:asNode()    -- "📚 Call Stack (3 frames)"

-- Frame level
frame:asNode()    -- "📄 testVariables() @ complex.js:42"

-- Scope/Variable level (preserves Variables4 sophistication)
scope:asNode()    -- "📁 Local: testVariables"
variable:asNode() -- "󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]"
```

### **Reactive Event Integration**
```lua
-- Automatically updates trees when DAP events occur
session:onThread(function(thread)
  debug_tree:updateTreesShowing(session)
end)

thread:onStopped(function()
  debug_tree:expandThread(thread) -- Auto-show stack when stopped
end)
```

### **Buffer-Composable Design**
```lua
-- Any DAP entity can be rendered to any buffer
local tree_handle = debug_tree:createTree(bufnr, session, options)
local tree_handle = debug_tree:createTree(bufnr, thread, options)  
local tree_handle = debug_tree:createTree(bufnr, frame, options)
```

## Usage Examples

### **Session Overview**
```lua
-- See all debug activity at once
:DebugTree
```
Shows complete session state - all threads, their status, call stacks, and current frames.

### **Thread Deep Dive**  
```lua
-- Focus on specific thread
:DebugTreeThread
```
Shows call stack detail, frame navigation, perfect for understanding execution flow.

### **Variable Investigation**
```lua
-- Equivalent to Variables4Tree
:DebugTreeFrame
```
Frame-level view with full Variables4 sophistication - scopes, variables, lazy resolution.

### **Programmatic Usage**
```lua
local debug_tree = api:getPluginInstance(require('neodap.plugins.DebugTree'))

-- Create session overview in sidebar
local session_tree = debug_tree:createTree(sidebar_bufnr, current_session, {
  max_depth = 2,  -- Session -> Thread -> Stack
  auto_expand = true
})

-- Create variable detail in main area
local frame_tree = debug_tree:createTree(main_bufnr, current_frame, {
  sophisticated_rendering = true,
  enable_lazy = true,
  max_depth = 3  -- Frame -> Scope -> Variable
})
```

## Integration with Other Plugins

### **Variables4 Compatibility**
DebugTree **preserves all Variables4 features** at the frame level:
```lua
-- These are equivalent:
:Variables4Tree    -- Variables4's frame-level view
:DebugTreeFrame    -- DebugTree's frame-level view
```

### **DebugOverlay Integration**
```lua
-- Multi-panel debugging with different tree levels
overlay:addPane("session", debug_tree:createTree(buf1, session))
overlay:addPane("variables", debug_tree:createTree(buf2, current_frame))
overlay:addPane("stack", debug_tree:createTree(buf3, current_thread))
```

### **Custom Integration**
```lua
-- Embed any DAP level in your custom UI
local my_custom_ui = {
  session_panel = debug_tree:createTree(buf1, session, { max_depth = 1 }),
  detail_panel = debug_tree:createTree(buf2, selected_entity, { sophisticated_rendering = true })
}
```

## Advanced Features

### **Smart Context Detection**
```lua
:DebugTree  -- Automatically opens at the most useful level:
            -- - Session level if multiple threads
            -- - Thread level if single stopped thread  
            -- - Frame level if debugging specific function
```

### **Focus Mode (from Variables4)**
- Press `f` to focus on current node and its siblings
- Dynamic popup titles showing navigation path
- Smart viewport management for large trees

### **Lazy Loading**
- Expensive DAP data loaded only when expanded
- Variables4's lazy variable resolution preserved
- Smart caching prevents redundant DAP calls

### **Sophisticated Rendering**
- UTF-8 tree characters: `╰─`, `▼`, `▶`
- Rich entity-specific icons: `📡`, `🧵`, `📚`, `📄`, `📁`
- Smart highlighting based on entity type and state
- Variables4's advanced variable formatting preserved

## File Structure

```
lua/neodap/plugins/DebugTree/
├── README.md              # This documentation  
├── init.lua              # Main DebugTree implementation
└── specs/
    └── DebugTree.spec.lua # Comprehensive visual tests
```

## Benefits Over Separate Tools

### **Before: Multiple Separate Views**
```
Variables4     → Frame variables only
StackNav       → Call stack only  
SessionViewer  → Session overview only
ThreadViewer   → Thread status only
```

### **After: Unified DebugTree**
```
DebugTree → Everything, any level, consistent navigation
```

### **Advantages**
1. **🧠 Consistent Mental Model**: Same navigation everywhere
2. **⚡ Efficient Workflow**: No context switching between tools
3. **🎯 Complete Picture**: See relationships between hierarchy levels
4. **🔧 Composable**: Embed any level in any UI
5. **📚 Variables4 Quality**: Sophisticated features at every level

## Conclusion

DebugTree represents the **evolution of Variables4's sophistication** applied to the entire DAP debugging experience. It provides a unified, powerful, and elegant way to navigate and understand complex debugging scenarios while maintaining the excellent user experience that Variables4 pioneered.

Perfect for developers who want **one tool that does debugging navigation right** across all levels of the debugging hierarchy.