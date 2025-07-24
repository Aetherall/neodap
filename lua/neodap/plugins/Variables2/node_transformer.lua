-- Node Transformer: Generic tool to transform any class to return NuiTree.Node instances
-- This is a reusable utility that can work with any class, not just Variables/Scopes

local NuiTree = require("nui.tree")

-- ========================================
-- GENERIC NODE TRANSFORMER
-- ========================================

local NodeTransformer = {}

-- Helper function to check if method should be async-wrapped
local function shouldWrapAsync(method_name)
  if type(method_name) ~= "string" then
    return false
  end
  
  local first_char = method_name:sub(1, 1)
  return first_char == first_char:upper() and first_char ~= first_char:lower()
end

-- Wrap a method with NvimAsync.defer if it's PascalCase
local function wrapMethodIfNeeded(method_name, method_func)
  if not shouldWrapAsync(method_name) then
    return method_func
  end
  
  local NvimAsync = require("neodap.tools.async")
  local logger = require("neodap.tools.logger").get("NodeTransformer:AsyncWrap")
  
  logger:debug("Auto-wrapping PascalCase method '" .. method_name .. "' with NvimAsync.defer")
  
  return NvimAsync.defer(function(...)
    return method_func(...)
  end)
end

-- ========================================
-- GENERIC CLASS EXTENSION
-- ========================================

-- Add methods to any class with proper async wrapping
function NodeTransformer.extendClass(TargetClass, extensions, options)
  options = options or {}
  local logger_name = options.logger_name or "NodeTransformer:Extend"
  local logger = require("neodap.tools.logger").get(logger_name)
  
  for method_name, method_func in pairs(extensions) do
    if TargetClass[method_name] then
      if options.skip_existing then
        logger:warn("Method " .. method_name .. " already exists on " .. tostring(TargetClass) .. ", skipping")
        goto continue
      else
        error("Method " .. method_name .. " already exists on " .. tostring(TargetClass))
      end
    end
    
    -- Apply async wrapping if needed
    local wrapped_method = wrapMethodIfNeeded(method_name, method_func)
    TargetClass[method_name] = wrapped_method
    
    logger:debug("Added method '" .. method_name .. "' to " .. tostring(TargetClass))
    
    ::continue::
  end
  
  return TargetClass
end

-- ========================================
-- GENERIC NODE TRANSFORMATION
-- ========================================

-- Transform any class constructor to return NuiTree.Node instances
function NodeTransformer.transformToNodeClass(TargetClass, node_config, options)
  options = options or {}
  local logger_name = options.logger_name or "NodeTransformer:Transform"
  local logger = require("neodap.tools.logger").get(logger_name)
  
  -- Determine which constructor method to override
  local constructor_method = options.constructor_method or "instanciate"
  if constructor_method == "instanciate" and not TargetClass.instanciate then
    constructor_method = "new"
  end
  
  local original_constructor = TargetClass[constructor_method]
  if not original_constructor then
    error("Class " .. tostring(TargetClass) .. " does not have '" .. constructor_method .. "' method")
  end
  
  logger:info("Transforming " .. tostring(TargetClass) .. " to return NuiTree.Node instances via " .. constructor_method)
  
  -- Override the constructor
  TargetClass[constructor_method] = function(self, ...)
    -- Create the original object
    local api_object = original_constructor(self, ...)
    
    -- Generate node configuration
    local node_data = {}
    
    -- Handle ID generation
    if node_config.id then
      if type(node_config.id) == "function" then
        node_data.id = node_config.id(api_object)
      else
        node_data.id = tostring(node_config.id)
      end
    elseif api_object.getTreeNodeId then
      node_data.id = api_object:getTreeNodeId()
    else
      node_data.id = tostring(api_object)
    end
    
    -- Handle text generation
    if node_config.text then
      if type(node_config.text) == "function" then
        node_data.text = node_config.text(api_object)
      else
        node_data.text = tostring(node_config.text)
      end
    elseif api_object.formatTreeNodeDisplay then
      node_data.text = api_object:formatTreeNodeDisplay()
    else
      node_data.text = tostring(api_object)
    end
    
    -- Add any additional node data
    if node_config.extra then
      for key, value in pairs(node_config.extra) do
        if type(value) == "function" then
          node_data[key] = value(api_object)
        else
          node_data[key] = value
        end
      end
    end
    
    -- Create NuiTree.Node with the computed data
    local node = NuiTree.Node(node_data)
    
    -- Copy all API object properties to the node
    for key, value in pairs(api_object) do
      if not rawget(node, key) then  -- Don't override node internals
        node[key] = value
      end
    end
    
    -- Create enhanced metatable that chains API methods
    local node_mt = getmetatable(node)
    local api_mt = getmetatable(api_object)
    
    setmetatable(node, {
      __index = function(t, k)
        -- First check node methods
        local node_method = node_mt.__index[k]
        if node_method ~= nil then
          return node_method
        end
        
        -- Then check API class methods (including extensions)
        local api_method = TargetClass[k]
        if api_method ~= nil then
          return api_method
        end
        
        return nil
      end,
      
      -- Support dynamic method addition with async wrapping
      __newindex = function(t, k, v)
        if type(v) == "function" and type(k) == "string" then
          local wrapped_method = wrapMethodIfNeeded(k, v)
          rawset(t, k, wrapped_method)
        else
          rawset(t, k, v)
        end
      end,
      
      __name = (api_mt and api_mt.__name or "Unknown") .. "Node",
      __tostring = api_object.__tostring or node_mt.__tostring,
    })
    
    logger:debug("Created enhanced node for " .. tostring(TargetClass) .. " with ID: " .. node_data.id)
    
    return node
  end
  
  return TargetClass
end

-- ========================================
-- CONVENIENCE FUNCTIONS
-- ========================================

-- Transform a class in one step (extend + transform)
function NodeTransformer.enhanceClassAsNodes(TargetClass, extensions, node_config, options)
  options = options or {}
  
  -- First extend with new methods
  if extensions then
    NodeTransformer.extendClass(TargetClass, extensions, options)
  end
  
  -- Then transform to return nodes
  NodeTransformer.transformToNodeClass(TargetClass, node_config, options)
  
  return TargetClass
end

-- Create a node transformation preset for tree-like classes
function NodeTransformer.createTreeNodePreset()
  return {
    extensions = {
      -- Common tree methods that many classes might want
      getTreeNodeId = function(self)
        return tostring(self)
      end,
      
      formatTreeNodeDisplay = function(self)
        return tostring(self)
      end,
      
      isTreeNodeExpandable = function(self)
        return false
      end,
      
      getTreeNodePath = function(self)
        return {}
      end,
      
      -- Async methods
      GetTreeNodeChildren = function(self)
        return nil
      end,
    },
    
    node_config = {
      id = function(obj) return obj:getTreeNodeId() end,
      text = function(obj) return obj:formatTreeNodeDisplay() end,
    }
  }
end

-- ========================================
-- EXAMPLES OF USAGE
-- ========================================

-- Example: Transform any class to work with trees
local function demonstrateGenericUsage()
  -- Example 1: Transform a custom class
  local MyClass = {}
  MyClass.__index = MyClass
  
  function MyClass:new(data)
    return setmetatable(data or {}, self)
  end
  
  -- Enhance it with tree capabilities
  NodeTransformer.enhanceClassAsNodes(MyClass, {
    getTreeNodeId = function(self)
      return "custom:" .. (self.name or "unknown")
    end,
    
    formatTreeNodeDisplay = function(self)
      return self.name or "Custom Object"
    end,
  }, {
    id = function(obj) return obj:getTreeNodeId() end,
    text = function(obj) return obj:formatTreeNodeDisplay() end,
  })
  
  -- Now MyClass:new() returns NuiTree.Node instances!
  local instance = MyClass:new({ name = "test" })
  print(instance:get_id())  -- Node method
  print(instance.name)      -- Original property
  
  -- Example 2: Use preset for common tree behavior
  local preset = NodeTransformer.createTreeNodePreset()
  NodeTransformer.enhanceClassAsNodes(MyClass, preset.extensions, preset.node_config)
  
  return MyClass
end

-- ========================================
-- MODULE EXPORTS
-- ========================================

return {
  NodeTransformer = NodeTransformer,
  extendClass = NodeTransformer.extendClass,
  transformToNodeClass = NodeTransformer.transformToNodeClass,
  enhanceClassAsNodes = NodeTransformer.enhanceClassAsNodes,
  createTreeNodePreset = NodeTransformer.createTreeNodePreset,
  demonstrateGenericUsage = demonstrateGenericUsage,
}