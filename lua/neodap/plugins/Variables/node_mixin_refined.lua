-- Refined Mixin Approach for neodap API Objects as NuiTree.Node
-- This shows how to modify existing API classes to BE tree nodes

local NuiTree = require("nui.tree")
local Class = require('neodap.tools.class')

-- ========================================
-- CORE MIXIN IMPLEMENTATION
-- ========================================

local NodeMixin = {}

-- Transform a neodap Class to produce NuiTree.Node instances
function NodeMixin.transformClass(TargetClass)
  -- Store original new method
  local original_new = TargetClass.new
  
  -- Override the constructor
  function TargetClass:new(props)
    -- Create the node with the properties
    local node = NuiTree.Node(props)
    
    -- Get original metatable from NuiTree.Node
    local node_mt = getmetatable(node)
    
    -- Create enhanced metatable that includes class methods
    local enhanced_mt = {
      __index = function(t, k)
        -- First check TargetClass methods
        local class_value = TargetClass[k]
        if class_value ~= nil then
          return class_value
        end
        -- Then check node methods
        return node_mt.__index[k]
      end,
      __name = TargetClass.name or "NodeMixin",
      __tostring = TargetClass.__tostring,
    }
    
    -- Apply the enhanced metatable
    setmetatable(node, enhanced_mt)
    
    -- Call any initialization if the class has one
    if TargetClass.initialize then
      TargetClass.initialize(node)
    end
    
    return node
  end
  
  -- Also provide factory method for compatibility
  if TargetClass.instanciate then
    local original_instanciate = TargetClass.instanciate
    function TargetClass:instanciate(...)
      local instance = original_instanciate(self, ...)
      -- Transform to node
      return TargetClass:new(instance)
    end
  end
  
  return TargetClass
end

-- ========================================
-- APPLYING TO NEODAP API CLASSES
-- ========================================

-- Enhanced Variable class that IS a NuiTree.Node
local function enhanceVariableClass()
  local Variable = require('neodap.api.Session.Variable')
  
  -- Add tree-specific methods to Variable
  function Variable:getNodeText()
    if self.ref then
      return string.format("%s: %s", self.ref.name, self.ref.value or self.ref.type)
    end
    return self.name or "Variable"
  end
  
  function Variable:getNodeChildren()
    if self.ref and self.ref.variablesReference and self.ref.variablesReference > 0 then
      -- This would fetch children using DAP
      local frame = self.scope and self.scope.frame
      if frame then
        local children = frame:variables(self.ref.variablesReference)
        -- Each child is already a Variable node!
        return children
      end
    end
    return nil
  end
  
  function Variable:canExpand()
    return self.ref and self.ref.variablesReference and self.ref.variablesReference > 0
  end
  
  -- Transform the class
  NodeMixin.transformClass(Variable)
  
  -- Override instanciate to create nodes
  local original_instanciate = Variable.instanciate
  function Variable:instanciate(scope, ref)
    -- Create node with all the data
    local node = NuiTree.Node({
      -- Tree node data
      text = string.format("%s: %s", ref.name, ref.value or ref.type),
      
      -- Variable data
      ref = ref,
      scope = scope,
      name = ref.name,
      value = ref.value,
      type = ref.type,
      variablesReference = ref.variablesReference,
    })
    
    -- Apply Variable methods
    local variable_mt = {
      __index = function(t, k)
        local v = Variable[k]
        if v ~= nil then return v end
        return getmetatable(node).__index[k]
      end,
      __name = "Variable",
      __tostring = Variable.__tostring,
    }
    
    setmetatable(node, variable_mt)
    return node
  end
  
  return Variable
end

-- ========================================
-- USAGE IN VARIABLES PLUGIN
-- ========================================

local function demonstrateUsage()
  -- Enhance the classes once at plugin init
  local Variable = enhanceVariableClass()
  
  -- Now when we get variables from DAP, they're already nodes!
  local function buildVariableTree(frame)
    local scopes = frame:scopes()
    local nodes = {}
    
    for _, scope in ipairs(scopes) do
      -- Get variables - they come back as Variable nodes
      local variables = scope:variables()
      
      -- Can use directly in NuiTree!
      for _, var in ipairs(variables) do
        -- var is both a Variable AND a NuiTree.Node
        table.insert(nodes, var)
      end
    end
    
    -- Create tree with Variable nodes directly
    local tree = NuiTree({
      nodes = nodes,
      prepare_node = function(node)
        -- node has both Variable methods and TreeNode methods!
        local line = NuiLine()
        
        -- Use Variable method
        line:append(node:getNodeText())
        
        -- Use TreeNode method
        if node:has_children() then
          line:append(node:is_expanded() and " ▼" or " ▶")
        end
        
        return line
      end,
    })
    
    return tree
  end
  
  -- Example: Variable is both API object and tree node
  local var = Variable:instanciate(scope, {
    name = "myArray",
    type = "Array",
    value = "[1, 2, 3]",
    variablesReference = 1001,
  })
  
  -- Can use Variable methods
  print(var:getNodeText())  -- "myArray: [1, 2, 3]"
  print(var.type)  -- "Array"
  
  -- Can use TreeNode methods
  print(var:get_id())  -- Node ID
  print(var:is_expanded())  -- false
  var:expand()  -- Expand the node
  
  -- Can pass directly to tree
  local tree = NuiTree({
    nodes = { var },  -- No conversion needed!
  })
end

-- ========================================
-- BENEFITS SUMMARY
-- ========================================

--[[
1. **Zero Conversion Overhead**: Variables ARE nodes, no wrapper objects
2. **Unified Interface**: One object has both Variable and TreeNode methods
3. **Direct Tree Usage**: Pass Variables directly to NuiTree
4. **Memory Efficient**: No duplicate objects or ID mappings
5. **Natural Integration**: Works seamlessly with existing neodap patterns
6. **Type Safety**: Variables still have their typed properties
7. **Backwards Compatible**: Existing Variable usage still works

The key insight: Instead of creating a trait that adds tree-like behavior,
we make the API objects literally BE tree nodes with domain methods added.
This is the ultimate expression of "Integrate, Don't Re-implement"!
--]]

return {
  NodeMixin = NodeMixin,
  enhanceVariableClass = enhanceVariableClass,
  demonstrateUsage = demonstrateUsage,
}