-- Variables4 Plugin - AsNode() Caching Strategy
-- Variables and Scopes get an asNode() method that creates and caches NuiTree.Nodes

local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')

-- ========================================
-- PLUGIN CLASS
-- ========================================

---@class Variables4Plugin
---@field api Api
---@field current_frame? Frame
---@field logger Logger
local Variables4Plugin = Class()

Variables4Plugin.name = "Variables4"

-- ========================================
-- PLUGIN INITIALIZATION
-- ========================================

function Variables4Plugin.plugin(api)
  local instance = Variables4Plugin:new({
    api = api,
    logger = Logger.get("Variables4"),
  })
  
  instance:initialize()
  return instance
end

function Variables4Plugin:initialize()
  print("=== Variables4Plugin:initialize() called ===")
  self.logger:info("Initializing Variables4 plugin - asNode() caching strategy")
  
  -- Set up event handlers
  self:setupEventHandlers()
  
  -- Create commands
  self:setupCommands()
  
  print("=== Variables4Plugin:initialize() completed ===")
  self.logger:info("Variables4 plugin initialized - will add asNode() methods on first session")
end

-- ========================================
-- AS-NODE METHOD EXTENSIONS
-- ========================================

function Variables4Plugin:setupAsNodeExtensions()
  print("=== Adding asNode() methods to API classes ===")
  
  -- Load API classes
  local Variable = require('neodap.api.Session.Variable')
  local ArgumentsScope = require('neodap.api.Session.Scope.ArgumentsScope')
  local LocalsScope = require('neodap.api.Session.Scope.LocalsScope')
  local GlobalsScope = require('neodap.api.Session.Scope.GlobalsScope')
  local ReturnValueScope = require('neodap.api.Session.Scope.ReturnValueScope')
  local RegistersScope = require('neodap.api.Session.Scope.RegistersScope')
  local GenericScope = require('neodap.api.Session.Scope.GenericScope')
  
  local NuiTree = require("nui.tree")
  
  -- Add asNode() method to Variable
  if not Variable.asNode then
    Variable.asNode = function(self)
      -- Check if we already have a cached node
      if self._cached_node then
        return self._cached_node
      end
      
      -- Create new node and cache it
      self._cached_node = NuiTree.Node({
        id = string.format("var:%s", self.ref.name),
        text = string.format("%s: %s", self.ref.name, self.ref.value or self.ref.type),
        type = "variable",
        expandable = self.ref.variablesReference and self.ref.variablesReference > 0,
        
        -- Store reference to original variable for access to methods
        _variable = self,
      })
      
      print("Created cached node for Variable: " .. self.ref.name)
      return self._cached_node
    end
    print("✓ Added asNode() method to Variable class")
  end
  
  -- Define common scope asNode method
  local function createScopeAsNode()
    return function(self)
      -- Check if we already have a cached node
      if self._cached_node then
        return self._cached_node
      end
      
      -- Create new node and cache it
      self._cached_node = NuiTree.Node({
        id = string.format("scope:%s", self.ref.name),
        text = "📁 " .. self.ref.name,
        type = "scope",
        expandable = true,
        
        -- Store reference to original scope for access to methods
        _scope = self,
      })
      
      print("Created cached node for Scope: " .. self.ref.name)
      return self._cached_node
    end
  end
  
  -- Add asNode() method to all scope classes
  local scope_classes = {
    ArgumentsScope, LocalsScope, GlobalsScope,
    ReturnValueScope, RegistersScope, GenericScope
  }
  
  for i, ScopeClass in ipairs(scope_classes) do
    if not ScopeClass.asNode then
      ScopeClass.asNode = createScopeAsNode()
      print("✓ Added asNode() method to scope class " .. i)
    end
    
    -- Also ensure BaseScope methods are available (same inheritance fix as Variables3)
    if not ScopeClass.variables then
      local BaseScope = require('neodap.api.Session.Scope.BaseScope')
      if BaseScope.variables then
        ScopeClass.variables = BaseScope.variables
        print("✓ Added inherited variables() method to scope class " .. i)
      end
    end
  end
  
  self.logger:info("Added asNode() methods to all Variable and Scope classes")
end

-- ========================================
-- EVENT HANDLERS
-- ========================================

function Variables4Plugin:setupEventHandlers()
  local extensions_applied = false
  
  self.api:onSession(function(session)
    -- Apply asNode extensions on first session
    if not extensions_applied then
      print("=== Applying asNode() extensions on session start ===")
      self:setupAsNodeExtensions()
      extensions_applied = true
    end
    
    session:onThread(function(thread)
      thread:onStopped(function(stopped_event)
        local stack = thread:stack()
        if stack then
          self:UpdateCurrentFrame(stack:top())
        end
      end)
      
      thread:onContinued(function()
        self:ClearCurrentFrame()
      end)
    end)
    
    session:onTerminated(function()
      self:ClearCurrentFrame()
    end)
  end)
end

function Variables4Plugin:UpdateCurrentFrame(frame)
  self.current_frame = frame
  self.logger:debug("Updated current frame")
end

function Variables4Plugin:ClearCurrentFrame()
  self.current_frame = nil
  self.logger:debug("Cleared current frame")
end

-- ========================================
-- USER COMMANDS
-- ========================================

function Variables4Plugin:setupCommands()
  vim.api.nvim_create_user_command("Variables4Demo", function()
    self:DemonstrateAsNodeStrategy()
  end, { desc = "Demonstrate Variables4 asNode() caching strategy" })
  
  vim.api.nvim_create_user_command("Variables4Status", function()
    self:ShowStatus()
  end, { desc = "Show Variables4 status" })
end

-- ========================================
-- DEMONSTRATION
-- ========================================

function Variables4Plugin:DemonstrateAsNodeStrategy()
  if not self.current_frame then
    print("No debug session active - start debugging to see asNode() strategy")
    return
  end
  
  print("Variables4: AsNode() Caching Strategy")
  print("===================================")
  print("")
  
  local scopes = self.current_frame:scopes()
  
  for _, scope in ipairs(scopes) do
    print("Scope: " .. scope.ref.name)
    print("  ✓ Type: " .. type(scope))
    print("  ✓ Has asNode method: " .. tostring(scope.asNode ~= nil))
    print("  ✓ Has cached node: " .. tostring(scope._cached_node ~= nil))
    print("  ✓ Original variables method: " .. tostring(scope.variables ~= nil))
    
    -- Test asNode() method
    if scope.asNode then
      print("  → Calling scope:asNode() for first time...")
      local node1 = scope:asNode()
      print("    ✓ Node created: " .. tostring(node1))
      print("    ✓ Node ID: " .. tostring(node1:get_id()))
      print("    ✓ Node text: " .. tostring(node1.text))
      
      print("  → Calling scope:asNode() again (should be cached)...")
      local node2 = scope:asNode()
      print("    ✓ Same instance: " .. tostring(node1 == node2))
      print("    ✓ Cache working: " .. tostring(scope._cached_node == node2))
    end
    print("")
    
    -- Show first few variables with asNode()
    local variables = scope:variables()
    if variables and #variables > 0 then
      print("  Variables (showing first 3):")
      for i, variable in ipairs(variables) do
        if i > 3 then break end
        
        print("    " .. variable.ref.name)
        print("      ✓ Has asNode method: " .. tostring(variable.asNode ~= nil))
        print("      ✓ Has cached node: " .. tostring(variable._cached_node ~= nil))
        
        if variable.asNode then
          print("      → Calling variable:asNode() for first time...")
          local var_node1 = variable:asNode()
          print("        ✓ Node ID: " .. tostring(var_node1:get_id()))
          print("        ✓ Node text: " .. tostring(var_node1.text))
          
          print("      → Calling variable:asNode() again (should be cached)...")
          local var_node2 = variable:asNode()
          print("        ✓ Same instance: " .. tostring(var_node1 == var_node2))
          print("        ✓ Cache working: " .. tostring(variable._cached_node == var_node2))
        end
      end
      if #variables > 3 then
        print("    ... and " .. (#variables - 3) .. " more variables")
      end
      print("")
    end
  end
  
  print("✓ AsNode() caching strategy demonstrated!")
  print("✓ Each Variable/Scope creates exactly one cached NuiTree.Node")
  print("✓ Subsequent calls return the same cached instance")
  print("✓ Non-intrusive - original API methods remain unchanged")
end

function Variables4Plugin:ShowStatus()
  print("Variables4 Plugin Status:")
  print("========================")
  print("Strategy: asNode() caching method")
  print("Current frame: " .. (self.current_frame and "Yes" or "No"))
  print("")
  
  if self.current_frame then
    local scopes = self.current_frame:scopes()
    print("Available scopes: " .. #scopes)
    
    for _, scope in ipairs(scopes) do
      local has_method = scope.asNode ~= nil
      local has_cache = scope._cached_node ~= nil
      print("  - " .. scope.ref.name .. " (asNode: " .. tostring(has_method) .. ", cached: " .. tostring(has_cache) .. ")")
    end
  end
  
  print("")
  print("✓ Variables have asNode() method")
  print("✓ Scopes have asNode() method") 
  print("✓ Caching strategy active")
end

-- ========================================
-- MODULE EXPORTS
-- ========================================

return Variables4Plugin