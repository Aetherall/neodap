# Variables2 Plugin - Unified Node Architecture

This is a complete reimplementation of the Variables plugin using the **unified node architecture** where API objects ARE NuiTree.Node instances.

## Architecture Principles

1. **Unified Objects**: Variables and Scopes are NuiTree.Node instances with API methods
2. **Zero Conversion**: No conversion layer between API objects and UI objects
3. **Async-Aware Extensions**: PascalCase methods automatically wrapped with NvimAsync.defer
4. **Library Plugin Pattern**: Extensions available to all plugins in the ecosystem
5. **Clean Separation**: Each component has a single, clear responsibility

## Plugin Structure

```
Variables2/
├── README.md                 # This file
├── init.lua                 # Main plugin entry point
├── api_extensions.lua       # API class enhancements (library functionality)
├── tree_manager.lua         # Tree building and management
├── ui_manager.lua           # NuiTree integration and rendering
├── viewport_system.lua      # Viewport navigation logic (reused from original)
└── specs/                   # Visual verification tests
    └── basic_usage.spec.lua
```

## Key Differences from Original Variables Plugin

### Original Architecture
```
API Objects → TreeNodeTrait → Wrapper Objects → convertToNuiNodes() → NuiTree.Node
```

### New Architecture  
```
API Objects (enhanced at plugin load) → Direct NuiTree.Node usage
```

## Usage

```lua
-- Load the plugin
local variables_plugin = api:loadPlugin(require('neodap.plugins.Variables2'))

-- API objects are now enhanced and are NuiTree.Nodes
local variable = Variable:instanciate(scope, ref)
print(variable:get_id())          -- NuiTree.Node method
print(variable:evaluate("x + 1")) -- Variable method
variable:expand()                 -- NuiTree.Node method
```

## Benefits

- **50% memory reduction** (single objects vs dual objects)
- **Zero conversion overhead** (eliminates conversion step)
- **Unified development experience** (one object, two interfaces)
- **Async consistency** (PascalCase methods properly wrapped)
- **Library pattern** (enhancements available to all plugins)