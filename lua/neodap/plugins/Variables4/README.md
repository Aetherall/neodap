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

- `:Variables4Demo` - Demonstrates asNode() caching with console output
- `:Variables4Status` - Shows plugin status and current frame info  
- `:Variables4TreeDemo` - **Opens interactive NUI tree popup (main feature)**
- `:Variables4TreeInteract` - Shows interaction help for open popup

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

## Files

```
Variables4/
├── README.md                      # This documentation
├── init.lua                       # Main plugin with asNode() strategy
└── specs/
    └── asnode_caching.spec.lua    # Visual verification tests
```

The asNode() approach provides an elegant middle ground - maintaining API purity while providing efficient, cached node conversion when needed.