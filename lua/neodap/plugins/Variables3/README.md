# Variables3 Plugin - Simple Generic Class Mixing

Variables3 showcases the **generic ClassMixer** - a clean implementation where Variables and Scopes become NuiTree.Nodes without any complexity.

## Simple Goal

Variables and Scopes become NuiTree.Nodes using the generic ClassMixer. That's it.

## Core Innovation: Generic Class Mixing

```lua
-- Transform any class to return instances of any other class
ClassMixer.transformToClass(SourceClass, TargetClass, {
  map_data = function(source) 
    return { target_specific_data = source.original_data }
  end,
  copy_properties = true,    -- Copy source properties to target
  chain_methods = true,      -- Chain source methods to target  
  post_transform = function(target, source)
    -- Custom enhancement logic
  end,
})
```

## Plugin Structure

```
Variables3/
├── README.md                # This file
├── init.lua                # Main plugin with transformation modes
├── class_mixer.lua         # Generic class transformation utility
└── specs/                  # Visual verification tests
    └── class_mixing.spec.lua
```

## Key Innovations

### **1. Multiple Target Classes**
Variables3 demonstrates transforming to different existing classes:
- **NuiTree.Node**: Standard tree nodes (like Variables2)
- **NuiLine**: Formatted text lines with styling
- **Custom Classes**: Any user-defined class

### **2. Zero Conversion Overhead**
Variables ARE NuiTree.Nodes from construction - no conversion needed.

### **3. Generic Transformation Capability**
```lua
-- The ClassMixer can transform any class to any other class
ClassMixer.transformToClass(SourceClass, TargetClass, config)
ClassMixer.createNodeMixer(SourceClass, extensions, node_config)
```

## Usage Examples

### **Mode 1: NuiTree.Node (Standard)**
```lua
-- Variables become NuiTree.Nodes
:Variables3Nodes
local variable = Variable:instanciate(scope, ref)
print(variable:get_id())              -- Node method
print(variable.text)                  -- Node property
print(variable:evaluate("x + 1"))     -- Original Variable method
```

### **Mode 2: NuiLine (Text Formatting)**
```lua  
-- Variables become NuiLines with styling
:Variables3Lines
local variable = Variable:instanciate(scope, ref)
print(variable:get_id())              -- Custom method added
-- variable is a formatted line with colors and icons
```

### **Mode 3: Custom Class**
```lua
-- Variables become custom DebugInfo instances  
:Variables3Custom
local variable = Variable:instanciate(scope, ref)
print(variable:inspect())             -- Custom method
print(variable.debug_timestamp)       -- Custom property
print(variable:evaluate("x + 1"))     -- Original Variable method
```

## Benefits Over Previous Versions

| Feature | Variables1 | Variables2 | Variables3 |
|---------|------------|------------|------------|
| **Architecture** | Dual objects | Unified nodes | Generic mixing |
| **Target Types** | NuiTree only | NuiTree only | Any class |
| **Flexibility** | Low | Medium | Ultimate |
| **Composition** | No | Limited | Full |
| **Performance** | Poor | Good | Optimal |
| **Extensibility** | Hard | Medium | Unlimited |

## Advanced Patterns

### **1. Plugin Ecosystem**
Other plugins can define their own target classes and transformations:
```lua
-- InspectorPlugin defines InspectorWidget
ClassMixer.transformToClass(Variable, InspectorWidget, inspector_config)

-- ProfilerPlugin defines ProfilerNode  
ClassMixer.transformToClass(Variable, ProfilerNode, profiler_config)
```

### **2. Dynamic Reconfiguration**
```lua
-- Change transformations at runtime
Variables3:switchMode("debugging")    -- Variables → DebugNode
Variables3:switchMode("simple")       -- Variables → SimpleWidget
Variables3:switchMode("profiling")    // Variables → ProfilerNode
```

### **3. Multi-Target Instances**
```lua
-- Single Variable can be multiple types simultaneously
local var_as_node = variable:asNode()
local var_as_widget = variable:asWidget()  
local var_as_debug = variable:asDebug()
```

This represents the **ultimate evolution** of the Variables plugin architecture - from hardcoded object relationships to **completely generic class composition**.