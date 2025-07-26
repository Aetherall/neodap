# Variables4 Plugin - AsNode() Caching Strategy

Variables4 demonstrates an elegant approach to integrating neodap debug API objects with NUI tree components using an **asNode() caching strategy**. This implementation provides a complete interactive debugging UI with dynamic scope expansion and proper async handling.

## Core Strategy

Instead of transforming classes or converting on every access, Variables4 adds an `asNode()` method to each API class that:
1. **Creates a NuiTree.Node on first call**
2. **Caches the node in the object**
3. **Returns the cached instance on subsequent calls**

## Key Benefits

### ✅ **Non-Intrusive**
- Original API classes remain unchanged
- All existing methods work normally
- No metatable manipulation or class mixing

### ✅ **Efficient Caching**
- Each Variable/Scope creates exactly **one** NuiTree.Node
- Subsequent `asNode()` calls return the same cached instance
- No repeated conversion overhead

### ✅ **Clean API**
```lua
-- Simple, predictable usage
local variable = Variable:instanciate(scope, ref)
local node = variable:asNode()        -- Creates and caches node
local same_node = variable:asNode()   -- Returns cached instance
print(node == same_node)              -- true
```

## Implementation Details

### **Extension Method**
```lua
Variable.asNode = function(self)
  -- Check cache first
  if self._cached_node then
    return self._cached_node
  end
  
  -- Create and cache new node
  self._cached_node = NuiTree.Node({
    id = string.format("var:%s", self.ref.name),
    text = string.format("%s: %s", self.ref.name, self.ref.value or self.ref.type),
    -- ... other properties
  })
  
  return self._cached_node
end
```

### **Applied to All Classes**
- **Variable class**: Creates variable nodes
- **All 6 concrete scope classes**: ArgumentsScope, LocalsScope, GlobalsScope, etc.

### **Cache Storage**
- Uses `self._cached_node` property on each object
- Node contains `_variable` or `_scope` reference back to original object
- Enables bidirectional access between API objects and nodes

## Usage Commands

- `:Variables4Tree` - **Opens interactive NUI tree popup with debug variables**
- `:Variables4UpdateFrame` - Updates current frame to top of stack
- `:Variables4ClearFrame` - Clears the current frame reference

### **In Code**
```lua
-- Get scopes and variables
local scopes = frame:scopes()
local variables = scopes[1]:variables()

-- Convert to nodes (cached)
local scope_node = scopes[1]:asNode()
local var_nodes = {}
for _, var in ipairs(variables) do
  table.insert(var_nodes, var:asNode())  -- Each cached individually
end

-- Access original objects from nodes
local original_scope = scope_node._scope
local original_var = var_nodes[1]._variable
```

## Architecture Comparison

| Feature | Variables1 (Dual) | Variables2 (Mixed) | Variables3 (Transform) | Variables4 (AsNode) |
|---------|-------------------|-------------------|----------------------|-------------------|
| **Intrusiveness** | High | Medium | High | Low |
| **Caching** | Manual | Automatic | Automatic | Automatic |
| **API Preservation** | Partial | Full | Full | Full |
| **Memory Efficiency** | Poor | Good | Optimal | Good |
| **Complexity** | High | Medium | High | Low |

## Key Advantages Over Other Approaches

### **vs Variables1 (Dual Objects)**
- ✅ Single cached node per object (not dual objects)
- ✅ Automatic caching (no manual management)
- ✅ Clean conversion API

### **vs Variables2 (Node Trait)**
- ✅ Simpler implementation (no trait system)
- ✅ Explicit conversion (clear when nodes are created)
- ✅ Less complex metatable manipulation

### **vs Variables3 (Class Transform)**
- ✅ Non-intrusive (doesn't change class constructors)
- ✅ No inheritance chain issues
- ✅ Easier to debug and understand
- ✅ Original objects remain original type

## Use Cases

### **Perfect For:**
- Libraries that need occasional node conversion
- Systems where you want explicit control over when nodes are created
- Codebases that prefer composition over inheritance
- Situations where you need to maintain clear separation between API and UI objects

### **Consider Alternatives When:**
- You need Variables to literally BE nodes (use Variables3)
- You're doing heavy UI work with many conversions (Variables3 might be better)
- You want completely automatic conversion (Variables2/3 handle this)

## Interactive NUI Tree Implementation

### **Complete Debugging UI**

Variables4 includes a fully functional interactive debugging interface:

```lua
-- Opens a NUI popup with tree view of debug scopes and variables
:Variables4Tree
```

**Features:**
- **Dynamic scope expansion**: Scopes start collapsed, variables loaded on-demand
- **Interactive navigation**: j/k to navigate, Enter/Space to expand/collapse
- **Async-safe operations**: Proper handling of `scope:variables()` calls
- **Rich variable display**: Shows names, values, and expandable indicators
- **Clean popup management**: q/Esc to close, ? for help
- **Lazy variable resolution**: Automatically resolves lazy variables when toggled

### **Critical Technical Solutions**

#### **1. Async Context Handling**
```lua
-- ❌ WRONG - causes "Cannot call async function from non-async context"
local variables = node._scope:variables()

-- ✅ CORRECT - wraps async call properly  
NvimAsync.run(function()
  local variables = node._scope:variables()
  -- ... handle variables
end)
```

#### **2. NUI Tree Dynamic Children API**
```lua
-- ❌ WRONG - NUI Tree doesn't recognize manual children
node.children = var_children

-- ✅ CORRECT - Use NUI Tree API for dynamic addition
tree:add_node(variable:asNode(), parent_node_id)
```

#### **3. BaseScope Inheritance Fix**
```lua
-- Concrete scope classes need manual inheritance fix
for _, ScopeClass in ipairs(scope_classes) do
  if not ScopeClass.variables and BaseScope.variables then
    ScopeClass.variables = BaseScope.variables
  end
end
```

#### **4. Lazy Variable Resolution**
Variables4 now supports DAP lazy variables through the standard protocol:
```lua
-- When a variable has presentationHint.lazy = true
-- Variables4 automatically calls variable:resolve() on toggle
-- This fetches the single child variable containing the actual value
-- The UI updates seamlessly without extra nodes
```

## Testing Results

The visual verification tests demonstrate successful implementation:

### **Interactive Scope Expansion Test**

- **Session ready**: Debug session hits breakpoint in `complex.js`
- **Popup opened**: Shows collapsed scopes (`▶ 📁 Local: testVariables`, `▶ 📁 Global`)
- **Local expanded**: Shows 14 variables with actual values and expandable indicators:
  - `▶ arrayVar: (5) [1, 2, 3, 'four', {…}]` (expandable array)
  - `booleanVar: true` (primitive value)
  - `numberVar: 42` (primitive value)
  - `▶ objectVar: {name: 'Test Object', count: 100, nested: {…}, method: ƒ}` (expandable object)
- **Navigation works**: Cursor moves properly through tree items
- **Clean closure**: Popup closes and returns to normal editing

## File Structure

```
lua/neodap/plugins/Variables4/
├── README.md              # This documentation
├── init.lua              # Main implementation with asNode() caching
└── specs/
    ├── asnode_caching.spec.lua        # Tests caching strategy
    ├── tree_rendering.spec.lua        # Tests NUI tree rendering  
    ├── interactive_expansion.spec.lua # Tests dynamic scope expansion
    ├── recursive_reference_test.spec.lua # Tests recursive variable handling
    └── complete_tree_demo.spec.lua    # Complete demo of tree functionality
```

## Conclusion

Variables4's asNode() caching strategy provides the optimal balance of:

- **Simplicity**: Direct method addition without complex transformations
- **Performance**: Efficient caching with minimal overhead
- **Integration**: Seamless NUI Tree compatibility  
- **Maintainability**: Clear, understandable code without indirection
- **Functionality**: **Full-featured interactive debugging UI**

This approach should be the **preferred pattern** for integrating neodap API objects with UI libraries in future plugins.