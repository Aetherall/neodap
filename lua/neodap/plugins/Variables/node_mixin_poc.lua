-- Proof of Concept: API Objects as NuiTree.Node Mixins
-- This demonstrates how neodap API objects can BE tree nodes directly

local NuiTree = require("nui.tree")

-- ========================================
-- MIXIN APPROACH 1: Direct Node Creation
-- ========================================

-- Example of making a Variable directly be a NuiTree.Node
local function createVariableNode(variable_ref, scope)
  -- Create a node that has all the variable data
  local node = NuiTree.Node({
    -- Node-specific data
    name = variable_ref.name,
    value = variable_ref.value,
    type = variable_ref.type,
    variablesReference = variable_ref.variablesReference,
    
    -- Keep the original ref
    ref = variable_ref,
    scope = scope,
    
    -- Variable methods can be added here
    evaluate = function(self, expression)
      -- Variable-specific logic
      return self.scope.frame:evaluate(expression)
    end,
  })
  
  return node
end

-- ========================================
-- MIXIN APPROACH 2: Metatable Chain
-- ========================================

-- More sophisticated: Make Variable class produce NuiTree.Node instances
local Variable = {}
Variable.__index = Variable

-- Variable constructor that creates a NuiTree.Node
function Variable:new(scope, ref)
  -- Create base node with variable data
  local node = NuiTree.Node({
    name = ref.name,
    value = ref.value,
    type = ref.type,
    variablesReference = ref.variablesReference,
    ref = ref,
    scope = scope,
  })
  
  -- Chain metatables: node -> Variable -> TreeNode
  local original_mt = getmetatable(node)
  setmetatable(node, {
    __index = function(t, k)
      -- First check Variable methods
      local v = Variable[k]
      if v ~= nil then return v end
      -- Then fallback to TreeNode methods
      return original_mt.__index[k]
    end,
    __name = "Variable",
  })
  
  return node
end

-- Variable-specific methods
function Variable:getChildren()
  if self.variablesReference and self.variablesReference > 0 then
    local children = self.scope.frame:variables(self.variablesReference)
    -- Return Variable nodes directly
    local child_nodes = {}
    for _, child_ref in ipairs(children) do
      table.insert(child_nodes, Variable:new(self.scope, child_ref))
    end
    return child_nodes
  end
  return nil
end

function Variable:formatDisplay()
  return string.format("%s: %s", self.name, self.value or self.type)
end

-- ========================================
-- MIXIN APPROACH 3: Class Factory
-- ========================================

-- Most elegant: Factory that creates node-based classes
local function createNodeClass(className, methods)
  local Class = {}
  
  -- Constructor creates NuiTree.Node instances
  function Class:new(data, children)
    local node = NuiTree.Node(data, children)
    
    -- Inject class methods into the node's metatable chain
    local original_mt = getmetatable(node)
    setmetatable(node, {
      __index = function(t, k)
        local v = methods[k]
        if v ~= nil then return v end
        return original_mt.__index[k]
      end,
      __name = className,
    })
    
    return node
  end
  
  return Class
end

-- Create Variable class using the factory
local VariableNode = createNodeClass("Variable", {
  getChildren = function(self)
    -- Variable-specific child logic
    if self.variablesReference > 0 then
      -- Return child nodes...
    end
  end,
  
  formatDisplay = function(self)
    return self.name .. ": " .. (self.value or self.type)
  end,
  
  evaluate = function(self, expr)
    return self.scope.frame:evaluate(expr)
  end,
})

-- ========================================
-- USAGE EXAMPLES
-- ========================================

-- Example 1: Direct usage in tree
local tree = NuiTree({
  nodes = {
    VariableNode:new({
      name = "foo",
      value = "42",
      type = "number",
    }),
    VariableNode:new({
      name = "bar",
      value = '{ x: 1, y: 2 }',
      type = "object",
      variablesReference = 1001,
    }),
  },
})

-- Example 2: Variable is both API object and tree node
local var = VariableNode:new({
  name = "myVar",
  value = "hello",
  scope = { frame = { evaluate = function() return "result" end } },
})

-- Can use as tree node
print(var:get_id())  -- TreeNode method
print(var:is_expanded())  -- TreeNode method

-- Can use as Variable
print(var:formatDisplay())  -- Variable method
print(var:evaluate("expr"))  -- Variable method

-- ========================================
-- BENEFITS OF THIS APPROACH
-- ========================================

-- 1. Zero conversion: Variables ARE nodes, no wrapper needed
-- 2. Direct tree usage: Can pass Variables directly to NuiTree
-- 3. Unified interface: One object with both behaviors
-- 4. Memory efficient: No duplicate objects
-- 5. Natural Lua patterns: Uses metatables elegantly

print("Mixin approach demonstration complete!")