-- Non-Invasive API Extension: Add methods to API classes without modifying their source
-- This enables library plugins that extend neodap capabilities for all plugins

local NuiTree = require("nui.tree")

-- ========================================
-- NON-INVASIVE CLASS EXTENSION SYSTEM
-- ========================================

local ApiExtender = {}

-- Add methods to an existing class without modifying its source
function ApiExtender.extend(TargetClass, extensions)
  -- Add each extension method to the class
  for method_name, method_func in pairs(extensions) do
    if TargetClass[method_name] then
      error("Method " .. method_name .. " already exists on " .. tostring(TargetClass))
    end
    TargetClass[method_name] = method_func
  end
  
  return TargetClass
end

-- Transform a class constructor to return NuiTree.Node instances
function ApiExtender.transformToNodeClass(TargetClass, node_config)
  -- Store original instanciate method
  local original_instanciate = TargetClass.instanciate
  
  -- Override instanciate to return NuiTree.Node instances
  function TargetClass:instanciate(...)
    -- Create the original API object
    local api_object = original_instanciate(self, ...)
    
    -- Generate node configuration
    local node_data = {}
    if node_config.id then
      node_data.id = node_config.id(api_object)
    end
    if node_config.text then
      node_data.text = node_config.text(api_object)
    end
    
    -- Create NuiTree.Node with the API object's data
    local node = NuiTree.Node(node_data)
    
    -- Copy all API object properties to the node
    for key, value in pairs(api_object) do
      node[key] = value
    end
    
    -- Chain the API class methods onto the node
    local node_mt = getmetatable(node)
    local api_mt = getmetatable(api_object)
    
    setmetatable(node, {
      __index = function(t, k)
        -- First check node methods
        local node_method = node_mt.__index[k]
        if node_method ~= nil then
          return node_method
        end
        
        -- Then check API class methods (including our extensions!)
        local api_method = TargetClass[k]
        if api_method ~= nil then
          return api_method
        end
        
        return nil
      end,
      __name = (api_mt and api_mt.__name or "Unknown") .. "Node",
      __tostring = api_object.__tostring or node_mt.__tostring,
    })
    
    return node
  end
  
  return TargetClass
end

-- ========================================
-- VARIABLE CLASS EXTENSIONS
-- ========================================

-- Get the Variable class (doesn't modify its source!)
local Variable = require('neodap.api.Session.Variable')

-- Add tree-related methods to Variable class
ApiExtender.extend(Variable, {
  -- Tree node identification
  getTreeNodeId = function(self)
    if self.scope and self.scope.ref then
      return string.format("var:%d:%s", 
        self.scope.ref.variablesReference or 0,
        self.ref.name)
    end
    return string.format("var:0:%s", self.ref.name)
  end,
  
  -- Tree node display
  formatTreeNodeDisplay = function(self)
    return string.format("%s: %s", 
      self.ref.name, 
      self.ref.value or self.ref.type or "unknown")
  end,
  
  -- Tree node children
  getTreeNodeChildren = function(self)
    if self.ref.variablesReference and self.ref.variablesReference > 0 then
      local frame = self.scope and self.scope.frame
      if frame then
        return frame:variables(self.ref.variablesReference)
      end
    end
    return nil
  end,
  
  -- Tree node expandability
  isTreeNodeExpandable = function(self)
    return self.ref.variablesReference and self.ref.variablesReference > 0
  end,
  
  -- Node-specific utility methods
  asTreeNode = function(self)
    return NuiTree.Node({
      id = self:getTreeNodeId(),
      text = self:formatTreeNodeDisplay(),
      api_object = self,  -- For backwards compatibility
    })
  end,
})

-- ========================================
-- SCOPE CLASS EXTENSIONS
-- ========================================

local BaseScope = require('neodap.api.Session.Scope.BaseScope')

ApiExtender.extend(BaseScope, {
  getTreeNodeId = function(self)
    return string.format("scope:%s", self.ref.name)
  end,
  
  formatTreeNodeDisplay = function(self)
    return self.ref.name
  end,
  
  getTreeNodeChildren = function(self)
    -- Scopes get children through the variables() method
    return self:variables()
  end,
  
  isTreeNodeExpandable = function(self)
    return true  -- Scopes are always expandable
  end,
  
  asTreeNode = function(self)
    return NuiTree.Node({
      id = self:getTreeNodeId(),
      text = self:formatTreeNodeDisplay(),
      api_object = self,
    })
  end,
})

-- ========================================
-- TRANSFORM CLASSES TO RETURN NODES
-- ========================================

-- Transform Variable to return NuiTree.Node instances
ApiExtender.transformToNodeClass(Variable, {
  id = function(api_object) 
    return api_object:getTreeNodeId() 
  end,
  text = function(api_object) 
    return api_object:formatTreeNodeDisplay() 
  end,
})

-- Transform BaseScope to return NuiTree.Node instances
ApiExtender.transformToNodeClass(BaseScope, {
  id = function(api_object) 
    return api_object:getTreeNodeId() 
  end,
  text = function(api_object) 
    return api_object:formatTreeNodeDisplay() 
  end,
})

-- ========================================
-- USAGE DEMONSTRATION
-- ========================================

local function demonstrateNonInvasiveExtension()
  -- Now ALL Variable instances have the new methods!
  -- This works for any plugin that creates Variables
  
  local function buildDirectTree(frame)
    local scopes = frame:scopes()  -- Returns Scope nodes!
    local all_nodes = {}
    
    for _, scope in ipairs(scopes) do
      -- scope is now a NuiTree.Node with Scope methods!
      table.insert(all_nodes, scope)
      
      -- Can use Scope methods
      print("Scope name:", scope.ref.name)
      
      -- Can use Node methods  
      print("Node ID:", scope:get_id())
      
      -- Can use our extensions
      print("Display:", scope:formatTreeNodeDisplay())
      
      -- Get variables - they're also nodes now!
      local variables = scope:variables()  -- Returns Variable nodes!
      
      for _, variable in ipairs(variables) do
        -- variable is a NuiTree.Node with Variable methods!
        table.insert(all_nodes, variable)
        
        -- Can use Variable methods
        if variable:isTreeNodeExpandable() then
          local children = variable:getTreeNodeChildren()
        end
        
        -- Can use Node methods
        variable:expand()
        print("Expanded:", variable:is_expanded())
      end
    end
    
    -- Create tree directly - no conversion needed!
    local tree = NuiTree({
      nodes = all_nodes,  -- They're already nodes!
    })
    
    return tree
  end
  
  -- Example of library plugin pattern
  -- Other plugins can now use our extensions:
  
  local function otherPluginCanUse()
    local variable = Variable:instanciate(scope, ref)
    
    -- Our extensions are available to ALL plugins!
    print(variable:getTreeNodeId())        -- Our extension
    print(variable:formatTreeNodeDisplay()) -- Our extension
    print(variable:get_id())               -- Node method
    variable:expand()                      -- Node method
  end
end

-- ========================================
-- VARIABLES PLUGIN INTEGRATION
-- ========================================

-- The Variables plugin can now eliminate convertToNuiNodes entirely!
local function integrateWithVariablesPlugin()
  -- In Variables plugin init.lua, replace this:
  -- local nui_nodes = self:convertToNuiNodes(tree_nodes)
  
  -- With this:
  local function getDirectNodes(frame)
    local tree_nodes = {}
    local scopes = frame:scopes()  -- Already NuiTree.Nodes!
    
    for _, scope in ipairs(scopes) do
      table.insert(tree_nodes, scope)
      
      local variables = scope:variables()  -- Already NuiTree.Nodes!
      for _, variable in ipairs(variables) do
        table.insert(tree_nodes, variable)
      end
    end
    
    return tree_nodes  -- No conversion needed!
  end
  
  -- Update tree directly
  local nodes = getDirectNodes(self.current_frame)
  tree:set_nodes(nodes)  -- Done!
end

-- ========================================
-- BENEFITS OF NON-INVASIVE EXTENSION
-- ========================================

--[[
1. **Library Plugin Pattern**: Extensions become available to ALL plugins
2. **Zero Source Modification**: API classes remain untouched in their files
3. **Unified Objects**: Variables and Scopes ARE NuiTree.Nodes
4. **Backwards Compatible**: Existing usage still works
5. **Extensible**: Other plugins can add their own extensions
6. **Performance**: Eliminates conversion overhead entirely
7. **Clean Architecture**: API objects and UI objects are unified

This approach transforms neodap into an extensible ecosystem where plugins
can enhance the core API for everyone's benefit!
--]]

return {
  ApiExtender = ApiExtender,
  demonstrateNonInvasiveExtension = demonstrateNonInvasiveExtension,
  integrateWithVariablesPlugin = integrateWithVariablesPlugin,
}