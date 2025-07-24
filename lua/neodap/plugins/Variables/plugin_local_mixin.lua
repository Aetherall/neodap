-- Plugin-Local Mixin: NuiTree.Node behavior without modifying API classes
-- This approach respects plugin boundaries while providing unified interfaces

local NuiTree = require("nui.tree")

-- ========================================
-- PLUGIN-LOCAL NODE FACTORY
-- ========================================

local NodeFactory = {}

-- Create a node-enhanced version of an API object without modifying the original
function NodeFactory.enhanceApiObject(api_object, node_data)
  -- Create a NuiTree.Node with the API object's data
  local node = NuiTree.Node(vim.tbl_extend("force", {
    -- Required node properties
    id = node_data.id or tostring(api_object),
    text = node_data.text or tostring(api_object),
  }, node_data or {}))
  
  -- Add all API object properties to the node
  for key, value in pairs(api_object) do
    if not rawget(node, key) then  -- Don't override node internals
      node[key] = value
    end
  end
  
  -- Create metatable that chains API methods onto the node
  local original_mt = getmetatable(node)
  local api_mt = getmetatable(api_object)
  
  setmetatable(node, {
    __index = function(t, k)
      -- First check if it's a node method
      local node_method = original_mt.__index[k]
      if node_method ~= nil then
        return node_method
      end
      
      -- Then check API object methods
      if api_mt and api_mt.__index then
        local api_method = api_mt.__index[k]
        if api_method ~= nil then
          return api_method
        end
      end
      
      -- Finally check API object class methods
      local api_class = getmetatable(api_object.class or {})
      if api_class and api_class.__index then
        return api_class.__index[k]
      end
      
      return nil
    end,
    
    __name = "Enhanced" .. (api_mt and api_mt.__name or "ApiObject"),
    __tostring = api_object.__tostring or original_mt.__tostring,
  })
  
  return node
end

-- ========================================
-- VARIABLE-SPECIFIC NODE FACTORY
-- ========================================

function NodeFactory.createVariableNode(variable)
  return NodeFactory.enhanceApiObject(variable, {
    id = string.format("var:%d:%s", 
      variable.scope and variable.scope.ref and variable.scope.ref.variablesReference or 0,
      variable.ref and variable.ref.name or "unknown"),
    text = variable.ref and string.format("%s: %s", 
      variable.ref.name, 
      variable.ref.value or variable.ref.type) or "Variable",
  })
end

-- ========================================
-- SCOPE-SPECIFIC NODE FACTORY  
-- ========================================

function NodeFactory.createScopeNode(scope)
  return NodeFactory.enhanceApiObject(scope, {
    id = string.format("scope:%s", scope.ref and scope.ref.name or "unknown"),
    text = scope.ref and scope.ref.name or "Scope",
  })
end

-- ========================================
-- PLUGIN-LOCAL ENHANCEMENT LAYER
-- ========================================

local VariablesNodeEnhancer = {}

-- Enhance a collection of API objects into nodes
function VariablesNodeEnhancer.enhanceCollection(api_objects, type_hint)
  local enhanced_nodes = {}
  
  for _, api_object in ipairs(api_objects) do
    local node
    
    -- Determine enhancement type
    if type_hint == "variable" or (api_object.ref and api_object.ref.variablesReference ~= nil) then
      node = NodeFactory.createVariableNode(api_object)
    elseif type_hint == "scope" or (api_object.ref and api_object.ref.name and not api_object.ref.value) then
      node = NodeFactory.createScopeNode(api_object)
    else
      -- Generic enhancement
      node = NodeFactory.enhanceApiObject(api_object, {
        id = tostring(api_object),
        text = tostring(api_object),
      })
    end
    
    table.insert(enhanced_nodes, node)
  end
  
  return enhanced_nodes
end

-- ========================================
-- USAGE IN VARIABLES PLUGIN
-- ========================================

local function demonstratePluginLocalUsage()
  -- This would be inside the Variables plugin
  
  local function buildEnhancedTree(frame)
    -- Get API objects normally (doesn't modify them!)
    local scopes = frame:scopes()  -- Returns normal Scope objects
    local all_nodes = {}
    
    for _, scope in ipairs(scopes) do
      -- Enhance scope for plugin-local use
      local scope_node = NodeFactory.createScopeNode(scope)
      table.insert(all_nodes, scope_node)
      
      -- Get variables normally
      local variables = scope:variables()  -- Returns normal Variable objects
      
      -- Enhance variables for plugin-local use
      local variable_nodes = VariablesNodeEnhancer.enhanceCollection(variables, "variable")
      
      for _, var_node in ipairs(variable_nodes) do
        table.insert(all_nodes, var_node)
      end
    end
    
    -- Now we have nodes that ARE both API objects and NuiTree.Nodes!
    local tree = NuiTree({
      nodes = all_nodes,  -- Direct usage!
      prepare_node = function(node)
        local line = NuiLine()
        
        -- Can use as NuiTree.Node
        line:append(node:get_id() .. ": ")
        
        -- Can use as API object
        if node.ref then
          line:append(node.ref.name)
        end
        
        -- Can use API methods
        if node.evaluate then
          -- This calls the original Variable:evaluate method!
          local result = node:evaluate("someExpr")
        end
        
        return line
      end
    })
    
    return tree
  end
  
  -- Example: Enhanced node has both interfaces
  local variable = Variable:instanciate(scope, ref)  -- Normal API object
  local var_node = NodeFactory.createVariableNode(variable)  -- Enhanced version
  
  -- Original variable is unchanged
  print(variable)  -- Still just a Variable
  
  -- Enhanced node has both interfaces
  print(var_node:get_id())        -- NuiTree.Node method
  print(var_node:is_expanded())   -- NuiTree.Node method
  print(var_node:evaluate("x"))   -- Variable method (from original!)
  print(var_node.ref.name)        -- Direct property access
end

-- ========================================
-- INTEGRATION WITH CURRENT PLUGIN
-- ========================================

-- Drop-in replacement for convertToNuiNodes
function VariablesNodeEnhancer.replaceConvertToNuiNodes(tree_nodes)
  local enhanced_nodes = {}
  
  for _, tree_node in ipairs(tree_nodes) do
    if tree_node.api_object then
      -- Create enhanced version
      local enhanced = NodeFactory.enhanceApiObject(tree_node.api_object, {
        id = tree_node.api_object:getTreeNodeId and 
             tree_node.api_object:getTreeNodeId() or 
             tostring(tree_node.api_object),
        text = tree_node.api_object:formatTreeNodeDisplay and
               tree_node.api_object:formatTreeNodeDisplay() or
               tostring(tree_node.api_object),
        
        -- Preserve viewport data
        viewport_geometry = tree_node.geometry,
        viewport_path = tree_node.path,
      })
      
      table.insert(enhanced_nodes, enhanced)
    end
  end
  
  return enhanced_nodes
end

-- ========================================
-- BENEFITS OF THIS APPROACH
-- ========================================

--[[
1. **Plugin Isolation**: Original API objects remain unmodified
2. **Zero Global Impact**: Other plugins see unchanged API behavior
3. **Unified Interface**: Plugin gets both API and Node methods on same object
4. **Memory Efficient**: Still reduces object count vs current approach
5. **Drop-in Compatible**: Can replace convertToNuiNodes with minimal changes
6. **Backwards Compatible**: Existing API usage patterns still work
7. **Scoped Enhancement**: Node behavior only exists within the plugin

This gives us 90% of the mixin benefits while respecting plugin boundaries!
--]]

return {
  NodeFactory = NodeFactory,
  VariablesNodeEnhancer = VariablesNodeEnhancer,
  demonstratePluginLocalUsage = demonstratePluginLocalUsage,
}