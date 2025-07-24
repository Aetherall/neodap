-- Async-Aware API Extension: Properly handle PascalCase methods with NvimAsync
-- Ensures our extensions follow neodap's async conventions

local NuiTree = require("nui.tree")

-- ========================================
-- ASYNC-AWARE API EXTENDER  
-- ========================================

local AsyncAwareApiExtender = {}

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
  local logger = require("neodap.tools.logger").get("ApiExtender:AsyncWrap")
  
  logger:debug("Auto-wrapping PascalCase method '" .. method_name .. "' with NvimAsync.defer - returns are fire-and-forget!")
  
  return NvimAsync.defer(function(...)
    return method_func(...)
  end)
end

-- Add methods to an existing class with proper async wrapping
function AsyncAwareApiExtender.extend(TargetClass, extensions)
  for method_name, method_func in pairs(extensions) do
    if TargetClass[method_name] then
      error("Method " .. method_name .. " already exists on " .. tostring(TargetClass))
    end
    
    -- Apply async wrapping if needed
    local wrapped_method = wrapMethodIfNeeded(method_name, method_func)
    TargetClass[method_name] = wrapped_method
  end
  
  return TargetClass
end

-- Transform a class constructor to return NuiTree.Node instances (with async support)
function AsyncAwareApiExtender.transformToNodeClass(TargetClass, node_config)
  local original_instanciate = TargetClass.instanciate
  
  function TargetClass:instanciate(...)
    local api_object = original_instanciate(self, ...)
    
    -- Generate node configuration
    local node_data = {}
    if node_config.id then
      node_data.id = node_config.id(api_object)
    end
    if node_config.text then
      node_data.text = node_config.text(api_object)
    end
    
    local node = NuiTree.Node(node_data)
    
    -- Copy all API object properties to the node
    for key, value in pairs(api_object) do
      node[key] = value
    end
    
    -- Create enhanced metatable that handles async wrapping
    local node_mt = getmetatable(node)
    local api_mt = getmetatable(api_object)
    
    setmetatable(node, {
      __index = function(t, k)
        -- Check node methods first
        local node_method = node_mt.__index[k]
        if node_method ~= nil then
          return node_method
        end
        
        -- Check API class methods (including our extensions)
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
-- VARIABLE CLASS EXTENSIONS WITH ASYNC SUPPORT
-- ========================================

local Variable = require('neodap.api.Session.Variable')

AsyncAwareApiExtender.extend(Variable, {
  -- Sync methods (camelCase)
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
  
  -- Async methods (PascalCase) - automatically wrapped!
  GetTreeNodeChildren = function(self)
    if self.ref.variablesReference and self.ref.variablesReference > 0 then
      local frame = self.scope and self.scope.frame
      if frame then
        -- This is async - can make DAP calls
        return frame:variables(self.ref.variablesReference)
      end
    end
    return nil
  end,
  
  RefreshValue = function(self)
    -- Async method to refresh variable value from debugger
    local frame = self.scope and self.scope.frame
    if frame then
      local updated_vars = frame:variables(self.scope.ref.variablesReference)
      for _, var in ipairs(updated_vars) do
        if var.ref.name == self.ref.name then
          self.ref.value = var.ref.value
          self.ref.type = var.ref.type
          break
        end
      end
    end
  end,
  
  EvaluateExpression = function(self, expression)
    -- Async method for evaluating expressions in variable context
    local frame = self.scope and self.scope.frame
    if frame then
      return frame:evaluate(expression)
    end
    return nil
  end,
})

-- ========================================
-- SCOPE CLASS EXTENSIONS WITH ASYNC SUPPORT
-- ========================================

local BaseScope = require('neodap.api.Session.Scope.BaseScope') 

AsyncAwareApiExtender.extend(BaseScope, {
  -- Sync methods
  getTreeNodeId = function(self)
    return string.format("scope:%s", self.ref.name)
  end,
  
  formatTreeNodeDisplay = function(self)
    return self.ref.name
  end,
  
  isTreeNodeExpandable = function(self)
    return true
  end,
  
  -- Async methods (PascalCase) - automatically wrapped!
  GetTreeNodeChildren = function(self)
    -- This is async - can make DAP calls
    return self:variables()
  end,
  
  RefreshVariables = function(self)
    -- Refresh all variables in this scope
    local updated_vars = self:variables()
    -- Could trigger UI updates, cache invalidation, etc.
    return updated_vars
  end,
})

-- ========================================
-- TRANSFORM CLASSES WITH ASYNC SUPPORT
-- ========================================

AsyncAwareApiExtender.transformToNodeClass(Variable, {
  id = function(api_object) 
    return api_object:getTreeNodeId() 
  end,
  text = function(api_object) 
    return api_object:formatTreeNodeDisplay() 
  end,
})

AsyncAwareApiExtender.transformToNodeClass(BaseScope, {
  id = function(api_object) 
    return api_object:getTreeNodeId() 
  end,
  text = function(api_object) 
    return api_object:formatTreeNodeDisplay() 
  end,
})

-- ========================================
-- USAGE WITH ASYNC METHODS
-- ========================================

local function demonstrateAsyncUsage()
  -- Get a variable node (it's already a NuiTree.Node!)
  local variable = Variable:instanciate(scope, ref)
  
  -- Sync methods work normally
  print(variable:getTreeNodeId())        -- Sync
  print(variable:formatTreeNodeDisplay()) // Sync
  print(variable:get_id())               -- Node method (sync)
  
  -- PascalCase methods are async-wrapped!
  -- From sync context (keymap, command):
  vim.keymap.set('n', '<F5>', function()
    variable:RefreshValue()  -- Fire-and-forget, returns poison value
    variable:GetTreeNodeChildren()  -- Fire-and-forget
  end)
  
  -- From async context (inside other PascalCase methods):
  function MyPlugin:UpdateTree()  -- PascalCase = async context
    local children = variable:GetTreeNodeChildren()  -- Returns actual values
    local refreshed = variable:RefreshValue()        -- Returns actual values
    
    -- Can use results normally in async context
    for _, child in ipairs(children or {}) do
      print(child.ref.name)
    end
  end
end

-- ========================================
-- VARIABLES PLUGIN INTEGRATION
-- ========================================

local function integrateAsyncMethods()
  -- In Variables plugin, we can now use async methods naturally
  
  function VariablesPlugin:RefreshTree()  -- PascalCase = async
    if not self.current_frame then return end
    
    local scopes = self.current_frame:scopes()
    for _, scope in ipairs(scopes) do
      -- These are async calls but work properly in async context
      local updated_vars = scope:RefreshVariables()
      
      for _, variable in ipairs(updated_vars) do
        if variable:isTreeNodeExpandable() then
          local children = variable:GetTreeNodeChildren()
          -- Process children...
        end
      end
    end
    
    self:UpdateUI()  -- Update the tree display
  end
  
  -- Keybinding uses async method (fire-and-forget)
  vim.keymap.set('n', '<F5>', function()
    variables_plugin:RefreshTree()  -- Returns poison value, runs async
  end)
end

-- ========================================
-- BENEFITS OF ASYNC-AWARE EXTENSION
-- ========================================

--[[
1. **Consistent Async Behavior**: PascalCase methods follow neodap conventions
2. **Context-Aware Execution**: Fire-and-forget from sync, normal from async
3. **Library Plugin Pattern**: Extensions available to all plugins
4. **Unified Objects**: API objects ARE NuiTree.Nodes with proper async support
5. **Error Handling**: Automatic error recovery via NvimAsync system
6. **Performance**: Zero conversion + proper async execution
7. **Developer Experience**: Same patterns as core neodap classes

Now our extensions seamlessly integrate with neodap's async architecture!
--]]

return {
  AsyncAwareApiExtender = AsyncAwareApiExtender,
  demonstrateAsyncUsage = demonstrateAsyncUsage,
  integrateAsyncMethods = integrateAsyncMethods,
}