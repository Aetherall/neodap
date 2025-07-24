-- Class Mixer: Generic tool to transform any class to return instances of any other class
-- This is a completely generic utility for class composition and transformation

-- ========================================
-- GENERIC CLASS MIXER
-- ========================================

local ClassMixer = {}

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
  local logger = require("neodap.tools.logger").get("ClassMixer:AsyncWrap")
  
  logger:debug("Auto-wrapping PascalCase method '" .. method_name .. "' with NvimAsync.defer")
  
  return NvimAsync.defer(function(...)
    return method_func(...)
  end)
end

-- ========================================
-- GENERIC CLASS EXTENSION
-- ========================================

-- Add methods to any class with proper async wrapping
function ClassMixer.extendClass(TargetClass, extensions, options)
  options = options or {}
  local logger_name = options.logger_name or "ClassMixer:Extend"
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
-- GENERIC CLASS TRANSFORMATION
-- ========================================

-- Transform any class constructor to return instances of any other class
function ClassMixer.transformToClass(SourceClass, TargetClass, transformation_config, options)
  options = options or {}
  local logger_name = options.logger_name or "ClassMixer:Transform"
  local logger = require("neodap.tools.logger").get(logger_name)
  
  -- Determine which constructor method to override
  local source_constructor = options.source_constructor or "instanciate"
  if source_constructor == "instanciate" and not SourceClass.instanciate then
    source_constructor = "new"
  end
  
  local original_constructor = SourceClass[source_constructor]
  if not original_constructor then
    error("Class " .. tostring(SourceClass) .. " does not have '" .. source_constructor .. "' method")
  end
  
  logger:info("Transforming " .. tostring(SourceClass) .. " to return " .. tostring(TargetClass) .. " instances")
  
  -- Override the constructor
  SourceClass[source_constructor] = function(self, ...)
    -- Create the original source object
    local source_object = original_constructor(self, ...)
    
    -- Generate target class constructor data
    local target_data = {}
    
    -- Apply transformation config
    if transformation_config.map_data then
      target_data = transformation_config.map_data(source_object)
    end
    
    -- Create instance of target class
    local target_constructor = options.target_constructor or "new"
    local target_object
    
    -- Handle both function and string target_constructor
    if type(target_constructor) == "function" then
      target_object = target_constructor(TargetClass, target_data)
    elseif TargetClass[target_constructor] then
      target_object = TargetClass[target_constructor](TargetClass, target_data)
    else
      -- Fallback: create with setmetatable
      target_object = setmetatable(target_data, TargetClass)
    end
    
    -- Copy source object properties to target object
    if transformation_config.copy_properties ~= false then
      for key, value in pairs(source_object) do
        if transformation_config.property_filter then
          if transformation_config.property_filter(key, value, source_object) then
            if not rawget(target_object, key) then  -- Don't override target internals
              target_object[key] = value
            end
          end
        else
          if not rawget(target_object, key) then  -- Don't override target internals
            target_object[key] = value
          end
        end
      end
    end
    
    -- Create enhanced metatable that chains source methods
    local target_mt = getmetatable(target_object)
    local source_mt = getmetatable(source_object)
    
    -- Debug: Check what source_object actually has (removed for clean output)
    
    if transformation_config.chain_methods ~= false then
      setmetatable(target_object, {
        __index = function(t, k)
          -- First check target class methods
          if target_mt and target_mt.__index then
            local target_method
            if type(target_mt.__index) == "function" then
              target_method = target_mt.__index(t, k)
            else
              target_method = target_mt.__index[k]
            end
            if target_method ~= nil then
              return target_method
            end
          end
          
          -- Then check source class methods (including extensions)
          local source_method = SourceClass[k]
          if source_method ~= nil then
            return source_method
          end
          
          -- Finally check source object methods (including inherited methods)
          if source_mt and source_mt.__index then
            local source_instance_method
            if type(source_mt.__index) == "function" then
              source_instance_method = source_mt.__index(source_object, k)
            else
              source_instance_method = source_mt.__index[k]
            end
            if source_instance_method ~= nil then
              return source_instance_method
            end
          end
          
          -- Special handling for neodap scope classes - check BaseScope inheritance
          local scope_classes = {
            'neodap.api.Session.Scope.ArgumentsScope',
            'neodap.api.Session.Scope.LocalsScope', 
            'neodap.api.Session.Scope.GlobalsScope',
            'neodap.api.Session.Scope.ReturnValueScope',
            'neodap.api.Session.Scope.RegistersScope',
            'neodap.api.Session.Scope.GenericScope'
          }
          
          -- Check if this is a scope transformation by checking if SourceClass is one of the scope classes
          for _, scope_class_name in ipairs(scope_classes) do
            local success, scope_class = pcall(require, scope_class_name)
            if success and SourceClass == scope_class then
              -- This is a scope class, check BaseScope for inherited methods
              local BaseScope = require('neodap.api.Session.Scope.BaseScope')
              if BaseScope[k] ~= nil then
                return BaseScope[k]
              end
              break
            end
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
        
        __name = (source_mt and source_mt.__name or "Unknown") .. "As" .. (target_mt and target_mt.__name or "Target"),
        __tostring = source_object.__tostring or (target_mt and target_mt.__tostring),
      })
    end
    
    -- Apply post-transformation hook
    if transformation_config.post_transform then
      transformation_config.post_transform(target_object, source_object)
    end
    
    logger:debug("Created " .. tostring(TargetClass) .. " instance from " .. tostring(SourceClass))
    
    return target_object
  end
  
  return SourceClass
end

-- ========================================
-- CONVENIENCE FUNCTIONS
-- ========================================

-- Mix a class in one step (extend + transform)
function ClassMixer.mixClasses(SourceClass, TargetClass, extensions, transformation_config, options)
  options = options or {}
  
  -- First extend source with new methods
  if extensions then
    ClassMixer.extendClass(SourceClass, extensions, options)
  end
  
  -- Then transform to return target instances
  ClassMixer.transformToClass(SourceClass, TargetClass, transformation_config, options)
  
  return SourceClass
end

-- ========================================
-- SPECIALIZED MIXERS
-- ========================================

-- Create a mixer for NuiTree.Node (common use case)
function ClassMixer.createNodeMixer(SourceClass, extensions, node_config, options)
  local NuiTree = require("nui.tree")
  
  local transformation_config = {
    map_data = function(source_object)
      local node_data = {}
      
      -- Handle ID generation
      if node_config.id then
        if type(node_config.id) == "function" then
          node_data.id = node_config.id(source_object)
        else
          node_data.id = tostring(node_config.id)
        end
      elseif source_object.getTreeNodeId then
        node_data.id = source_object:getTreeNodeId()
      else
        node_data.id = tostring(source_object)
      end
      
      -- Handle text generation
      if node_config.text then
        if type(node_config.text) == "function" then
          node_data.text = node_config.text(source_object)
        else
          node_data.text = tostring(node_config.text)
        end
      elseif source_object.formatTreeNodeDisplay then
        node_data.text = source_object:formatTreeNodeDisplay()
      else
        node_data.text = tostring(source_object)
      end
      
      -- Add any additional node data
      if node_config.extra then
        for key, value in pairs(node_config.extra) do
          if type(value) == "function" then
            node_data[key] = value(source_object)
          else
            node_data[key] = value
          end
        end
      end
      
      return node_data
    end,
    
    target_constructor = function(TargetClass, data)
      return NuiTree.Node(data)
    end,
  }
  
  return ClassMixer.mixClasses(SourceClass, NuiTree, extensions, transformation_config, options)
end

-- Create a mixer for any custom class combination
function ClassMixer.createCustomMixer(SourceClass, TargetClass, config)
  local transformation_config = {
    map_data = config.map_data or function(obj) return obj end,
    copy_properties = config.copy_properties,
    property_filter = config.property_filter,
    chain_methods = config.chain_methods,
    post_transform = config.post_transform,
  }
  
  return ClassMixer.mixClasses(
    SourceClass, 
    TargetClass, 
    config.extensions, 
    transformation_config, 
    config.options
  )
end

-- ========================================
-- EXAMPLES OF USAGE
-- ========================================

-- Example: Mix any class with any other class
local function demonstrateGenericMixing()
  -- Example 1: Variable + NuiTree.Node
  local NuiTree = require("nui.tree")
  local Variable = require('neodap.api.Session.Variable')
  
  ClassMixer.createNodeMixer(Variable, {
    getTreeNodeId = function(self)
      return "var:" .. self.ref.name
    end,
    formatTreeNodeDisplay = function(self)
      return self.ref.name .. ": " .. (self.ref.value or self.ref.type)
    end,
  }, {
    id = function(obj) return obj:getTreeNodeId() end,
    text = function(obj) return obj:formatTreeNodeDisplay() end,
  })
  
  -- Example 2: Any class + any other class
  local MySourceClass = {}
  local MyTargetClass = {}
  
  ClassMixer.transformToClass(MySourceClass, MyTargetClass, {
    map_data = function(source_obj)
      return {
        transformed_prop = source_obj.original_prop,
        computed_value = source_obj.value * 2,
      }
    end,
    
    post_transform = function(target_obj, source_obj)
      target_obj.source_reference = source_obj
    end,
  })
  
  -- Example 3: Chain multiple classes
  local BaseClass = {}
  local MiddleClass = {}  
  local FinalClass = {}
  
  -- BaseClass -> MiddleClass
  ClassMixer.transformToClass(BaseClass, MiddleClass, {
    map_data = function(obj) return { middle_data = obj.base_data } end
  })
  
  -- MiddleClass -> FinalClass  
  ClassMixer.transformToClass(MiddleClass, FinalClass, {
    map_data = function(obj) return { final_data = obj.middle_data } end
  })
  
  -- Now BaseClass:new() returns FinalClass instances!
end

-- ========================================
-- MODULE EXPORTS
-- ========================================

return {
  ClassMixer = ClassMixer,
  extendClass = ClassMixer.extendClass,
  transformToClass = ClassMixer.transformToClass,
  mixClasses = ClassMixer.mixClasses,
  createNodeMixer = ClassMixer.createNodeMixer,
  createCustomMixer = ClassMixer.createCustomMixer,
  demonstrateGenericMixing = demonstrateGenericMixing,
}