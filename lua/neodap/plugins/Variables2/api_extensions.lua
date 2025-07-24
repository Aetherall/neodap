-- API Extensions: Non-invasive enhancements to neodap API classes
-- Uses the generic ClassMixer for maximum flexibility

local ClassMixer = require('neodap.plugins.Variables2.class_mixer')
local NuiTree = require("nui.tree")

-- ========================================
-- API EXTENSIONS USING GENERIC CLASS MIXER
-- ========================================

-- For backwards compatibility, expose the generic mixer methods
local AsyncAwareApiExtender = {
  extend = ClassMixer.extendClass,
  transformToNodeClass = function(TargetClass, node_config, options)
    return ClassMixer.createNodeMixer(TargetClass, nil, node_config, options)
  end,
  transformToClass = ClassMixer.transformToClass,
  mixClasses = ClassMixer.mixClasses,
}

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
  local logger = require("neodap.tools.logger").get("Variables2:AsyncWrap")

  logger:debug("Auto-wrapping PascalCase method '" .. method_name .. "' with NvimAsync.defer")

  return NvimAsync.defer(function(...)
    return method_func(...)
  end)
end

-- Add methods to an existing class with proper async wrapping
function AsyncAwareApiExtender.extend(TargetClass, extensions)
  for method_name, method_func in pairs(extensions) do
    if TargetClass[method_name] then
      local logger = require("neodap.tools.logger").get("Variables2:ApiExtender")
      logger:warn("Method " .. method_name .. " already exists on " .. tostring(TargetClass) .. ", skipping")
      goto continue
    end

    -- Apply async wrapping if needed
    local wrapped_method = wrapMethodIfNeeded(method_name, method_func)
    TargetClass[method_name] = wrapped_method

    ::continue::
  end

  return TargetClass
end

-- Transform a class constructor to return NuiTree.Node instances
function AsyncAwareApiExtender.transformToNodeClass(TargetClass, node_config)
  -- Store original instanciate method
  local original_instanciate = TargetClass.new
  if not original_instanciate then
    error("Class " .. tostring(TargetClass) .. " does not have instanciate method")
  end

  function TargetClass:new(...)
    -- Create the original API object
    local api_object = original_instanciate(self, ...)

    -- Generate node configuration
    local node_data = {}
    if node_config.id then
      node_data.id = node_config.id(api_object)
    else
      node_data.id = tostring(api_object)
    end

    if node_config.text then
      node_data.text = node_config.text(api_object)
    else
      node_data.text = tostring(api_object)
    end

    -- Create NuiTree.Node with the computed data
    local node = NuiTree.Node(node_data)

    -- Copy all API object properties to the node
    for key, value in pairs(api_object) do
      if not rawget(node, key) then -- Don't override node internals
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

        -- Then check API class methods (including our extensions)
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

    return node
  end

  return TargetClass
end

-- ========================================
-- VARIABLE CLASS EXTENSIONS
-- ========================================

local function extendVariableClass()
  local Variable = require('neodap.api.Session.Variable')

  AsyncAwareApiExtender.extend(Variable, {
    -- Sync tree methods (camelCase)
    getTreeNodeId = function(self)
      if self.scope and self.scope.ref then
        return string.format("var:%d:%s",
          self.scope.ref.variablesReference or 0,
          self.ref.name)
      end
      return string.format("var:0:%s", self.ref.name)
    end,

    formatTreeNodeDisplay = function(self)
      return string.format("%s: %s",
        self.ref.name,
        self.ref.value or self.ref.type or "unknown")
    end,

    isTreeNodeExpandable = function(self)
      return self.ref.variablesReference and self.ref.variablesReference > 0
    end,

    getTreeNodePath = function(self)
      local path = {}
      if self.scope and self.scope.ref then
        table.insert(path, self.scope.ref.name)
      end
      table.insert(path, self.ref.name)
      return path
    end,

    -- Async tree methods (PascalCase) - automatically wrapped!
    GetTreeNodeChildren = function(self)
      if self.ref.variablesReference and self.ref.variablesReference > 0 then
        local frame = self.scope and self.scope.frame
        if frame then
          -- This can make DAP calls safely in async context
          return frame:variables(self.ref.variablesReference)
        end
      end
      return nil
    end,

    RefreshValue = function(self)
      -- Refresh this variable's value from the debugger
      local frame = self.scope and self.scope.frame
      if frame then
        local parent_ref = self.scope.ref.variablesReference
        local updated_vars = frame:variables(parent_ref)

        for _, var in ipairs(updated_vars) do
          if var.ref.name == self.ref.name then
            self.ref.value = var.ref.value
            self.ref.type = var.ref.type
            self.ref.variablesReference = var.ref.variablesReference
            break
          end
        end
      end
    end,

    EvaluateExpression = function(self, expression)
      -- Evaluate an expression in this variable's context
      local frame = self.scope and self.scope.frame
      if frame then
        return frame:evaluate(expression)
      end
      return nil
    end,
  })

  -- Transform Variable to return NuiTree.Node instances
  ClassMixer.createNodeMixer(Variable, nil, {
    id = function(api_object)
      return api_object:getTreeNodeId()
    end,
    text = function(api_object)
      return api_object:formatTreeNodeDisplay()
    end,
  })

  return Variable
end

-- ========================================
-- SCOPE CLASS EXTENSIONS
-- ========================================

local function extendScopeClasses()
  local BaseScope = require('neodap.api.Session.Scope.BaseScope')

  AsyncAwareApiExtender.extend(BaseScope, {
    -- Sync tree methods
    getTreeNodeId = function(self)
      return string.format("scope:%s", self.ref.name)
    end,

    formatTreeNodeDisplay = function(self)
      return self.ref.name
    end,

    isTreeNodeExpandable = function(self)
      return true -- Scopes are always expandable
    end,

    getTreeNodePath = function(self)
      return { self.ref.name }
    end,

    -- Async tree methods (PascalCase)
    GetTreeNodeChildren = function(self)
      -- Get variables in this scope
      return self:variables()
    end,

    RefreshVariables = function(self)
      -- Refresh all variables in this scope
      return self:variables()
    end,
  })

  -- Transform BaseScope to return NuiTree.Node instances
  ClassMixer.createNodeMixer(BaseScope, nil, {
    id = function(api_object)
      return api_object:getTreeNodeId()
    end,
    text = function(api_object)
      return api_object:formatTreeNodeDisplay()
    end,
  })

  -- Also extend specific scope types
  local scope_types = {
    'LocalsScope',
    'GlobalsScope',
    'ArgumentsScope',
    'RegistersScope'
  }

  for _, scope_type in ipairs(scope_types) do
    local ok, ScopeClass = pcall(require, 'neodap.api.Session.Scope.' .. scope_type)
    if ok then
      ClassMixer.createNodeMixer(ScopeClass, nil, {
        id = function(api_object)
          return api_object:getTreeNodeId()
        end,
        text = function(api_object)
          return api_object:formatTreeNodeDisplay()
        end,
      })
    end
  end

  return BaseScope
end

-- ========================================
-- INITIALIZATION
-- ========================================

local function initializeApiExtensions()
  local logger = require("neodap.tools.logger").get("Variables2:ApiExtensions")
  logger:info("Initializing API extensions for Variables2 plugin")

  -- Extend the API classes
  local Variable = extendVariableClass()
  local BaseScope = extendScopeClasses()

  logger:info("API extensions loaded - Variables and Scopes are now NuiTree.Nodes")

  return {
    Variable = Variable,
    BaseScope = BaseScope,
    AsyncAwareApiExtender = AsyncAwareApiExtender,
  }
end

-- ========================================
-- MODULE EXPORTS
-- ========================================

return {
  initializeApiExtensions = initializeApiExtensions,
  AsyncAwareApiExtender = AsyncAwareApiExtender,
  extendVariableClass = extendVariableClass,
  extendScopeClasses = extendScopeClasses,
}
