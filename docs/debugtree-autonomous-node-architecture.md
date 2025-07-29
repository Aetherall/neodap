# DebugTree Autonomous Node Architecture

## Core Philosophy: Self-Managing Reactive Nodes

Each DAP entity (Session, Thread, Stack, Frame, Scope, Variable) creates an **autonomous tree node** that manages its own lifecycle, state, and children. No central registry or orchestration needed - pure distributed responsibility.

## The Pattern

### 1. Each Node is Self-Contained

```lua
-- Each DAP entity gets an asNode() method that returns a self-managing node
Entity.asNode = function(self)
  local node = NuiTree.Node({
    id = "entity:" .. self.id,
    text = self:getDisplayText(),
    expandable = self:canExpand()
  })
  
  -- Node subscribes to its own entity's events
  self:onStateChange(function()
    node.text = self:getDisplayText()
    node.expandable = self:canExpand()
  end)
  
  -- Node creates children when appropriate
  self:onChildAvailable(function(child)
    local child_node = child:asNode()
    node:add_child(child_node)
  end)
  
  -- Node cleans up after itself
  self:onDestroyed(function()
    node:remove()
  end)
  
  return node
end
```

### 2. Hierarchical Self-Organization

```
Session Node
├── Creates Thread nodes when session:onThread() fires
├── Thread Node (autonomous)
    ├── Updates own state on thread:onStopped/onContinued/onExited
    ├── Creates Stack node when stopped
    ├── Stack Node (autonomous)
        ├── Creates Frame nodes when expanded
        ├── Frame Node (autonomous)
            ├── Creates Scope nodes when expanded  
            ├── Scope Node (autonomous)
                └── Creates Variable nodes when expanded
```

## Implementation Examples

### Session Node
```lua
Session.asNode = function(self)
  local node = NuiTree.Node({
    text = "📡 Session " .. self.id,
    expandable = true
  })
  
  -- Session only handles thread creation
  self:onThread(function(thread)
    local thread_node = thread:asNode() -- Thread manages itself!
    node:add_child(thread_node)
  end)
  
  -- Session handles its own termination
  self:onTerminated(function()
    node:remove()
  end)
  
  return node
end
```

### Thread Node
```lua
Thread.asNode = function(self)
  local function getDisplayText()
    local status = self.stopped and "⏸️ stopped" or "▶️ running"
    return "Thread " .. self.id .. " (" .. status .. ")"
  end

  local node = NuiTree.Node({
    text = getDisplayText(),
    expandable = self.stopped
  })
  
  -- Thread manages its own state changes
  self:onStopped(function(body)
    node.text = getDisplayText()
    node.expandable = true
    
    -- Create stack child when stopped
    local stack = self:stack()
    if stack then
      local stack_node = stack:asNode()
      node:add_child(stack_node)
    end
  end)
  
  self:onContinued(function(body)
    node.text = getDisplayText()
    node.expandable = false
    node:remove_children() -- Clear stack when running
  end)
  
  self:onExited(function(body)
    node:remove() -- Remove self from tree
  end)
  
  return node
end
```

### Frame Node with Variables
```lua
Frame.asNode = function(self)
  local node = NuiTree.Node({
    text = "📄 " .. (self.ref.name or "Frame " .. self.ref.id),
    expandable = true
  })
  
  -- Lazy load scopes when expanded
  node.on_expand = function()
    if node:has_children() then return end
    
    local scopes = self:scopes()
    if not scopes then return end
    
    for _, scope in ipairs(scopes) do
      local scope_node = scope:asNode()
      node:add_child(scope_node)
    end
  end
  
  return node
end
```

## Key Benefits

### 1. **No Registry Complexity**
- No DebugTreeRegistry tracking nodes across trees
- No multi-tree synchronization logic
- No centralized state management

### 2. **Direct Tree Operations**
```lua
-- Simple, direct NUI Tree API usage
node:add_child(child_node)
node:remove_children()
node:remove()
node.text = "updated text"
```

### 3. **Perfect Locality**
- Each node only knows about its immediate children
- No global state or cross-references
- Self-contained reactive behavior

### 4. **Natural Composition**
- Tree structure directly mirrors DAP hierarchy
- Each level handles what it knows best
- Emergent behavior from simple local rules

## Architecture Comparison

### Before: Centralized Registry
```lua
-- Complex registry tracking nodes across multiple trees
DebugTreeRegistry:addThreadToSessionNode(session_node, thread)
DebugTreeRegistry:removeThreadFromSessionNode(session_node, thread)
DebugTreeRegistry:refreshNodeInAllTrees(node)

// Multiple trees need synchronization
registry.node_trees = {} -- node_id → [tree1, tree2, ...]
```

### After: Autonomous Nodes
```lua
// Each node manages itself
session_node = session:asNode() // Creates self-managing session node
thread_node = thread:asNode()   // Creates self-managing thread node

// No registry, no synchronization - just pure reactive nodes
```

## Implementation Guidelines

### 1. **Each Entity Gets asNode()**
Add `asNode()` method to all DAP entities:
- Session, Thread, Stack, Frame, Scope, Variable

### 2. **Subscribe to Own Events Only**
```lua
// ✅ Node listens to its own entity
self:onStopped(function() ... end)

// ❌ Node doesn't listen to other entities  
other_entity:onStopped(function() ... end)
```

### 3. **Direct Tree Manipulation**
```lua
// ✅ Use NUI Tree API directly
node:add_child(child_node)
node:remove()

// ❌ No custom registry layer
Registry:addChild(parent, child)
```

### 4. **Lazy Child Creation**
Create children only when needed:
- On expansion for UI trees
- On state changes for reactive updates
- On demand for specific operations

## Result: Self-Organizing Reactive Tree

The debug tree becomes a **living representation** of the DAP state:
- Nodes appear when entities are created
- Nodes update when entities change state  
- Nodes disappear when entities are destroyed
- No central coordination required

**Pure reactive architecture** where each component manages itself and composes naturally with others.