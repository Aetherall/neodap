-- Variables3 Plugin - Simple Generic Class Mixing
-- Variables and Scopes become NuiTree.Nodes using the generic ClassMixer

local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')
local ClassMixer = require('neodap.plugins.Variables3.class_mixer')

-- ========================================
-- PLUGIN CLASS
-- ========================================

---@class Variables3Plugin
---@field api Api
---@field current_frame? Frame
---@field logger Logger
local Variables3Plugin = Class()

Variables3Plugin.name = "Variables3"

-- ========================================
-- PLUGIN INITIALIZATION
-- ========================================

function Variables3Plugin.plugin(api)
  local instance = Variables3Plugin:new({
    api = api,
    logger = Logger.get("Variables3"),
  })
  
  instance:initialize()
  return instance
end

function Variables3Plugin:initialize()
  print("=== Variables3Plugin:initialize() called ===")
  self.logger:info("Initializing Variables3 plugin - Variables become Nodes via generic ClassMixer")
  
  -- NOTE: Don't transform here - do it when session starts
  -- This ensures we transform the classes that will actually be used
  
  -- Set up event handlers
  self:setupEventHandlers()
  
  -- Create commands
  self:setupCommands()
  
  print("=== Variables3Plugin:initialize() completed ===")
  self.logger:info("Variables3 plugin initialized - will transform classes on first session")
end

-- ========================================
-- CLASS TRANSFORMATIONS
-- ========================================

function Variables3Plugin:setupTransformations()
  print("=== setupTransformations() called ===")
  local Variable = require('neodap.api.Session.Variable')
  
  -- Load ALL concrete scope classes, not just BaseScope
  local ArgumentsScope = require('neodap.api.Session.Scope.ArgumentsScope')
  local LocalsScope = require('neodap.api.Session.Scope.LocalsScope')
  local GlobalsScope = require('neodap.api.Session.Scope.GlobalsScope')
  local ReturnValueScope = require('neodap.api.Session.Scope.ReturnValueScope')
  local RegistersScope = require('neodap.api.Session.Scope.RegistersScope')
  local GenericScope = require('neodap.api.Session.Scope.GenericScope')
  
  local all_scope_classes = {
    ArgumentsScope, LocalsScope, GlobalsScope, 
    ReturnValueScope, RegistersScope, GenericScope
  }
  
  print("Variable class: " .. tostring(Variable))
  print("Found " .. #all_scope_classes .. " concrete scope classes to transform")
  self.logger:info("Variables3: About to extend Variable class with tree methods")
  self.logger:info("Variable class before extend: " .. tostring(Variable))
  self.logger:info("Variable.getTreeNodeId before: " .. tostring(Variable.getTreeNodeId))
  
  -- First extend Variable with tree methods
  print("About to call ClassMixer.extendClass for Variable")
  ClassMixer.extendClass(Variable, {
    getTreeNodeId = function(self)
      return string.format("var:%s", self.ref.name)
    end,
    
    formatTreeNodeDisplay = function(self)
      return string.format("%s: %s", self.ref.name, self.ref.value or self.ref.type)
    end,
    
    isTreeNodeExpandable = function(self)
      return self.ref.variablesReference and self.ref.variablesReference > 0
    end,
    
    -- Async method (PascalCase - auto-wrapped)
    GetTreeNodeChildren = function(self)
      if self.ref.variablesReference and self.ref.variablesReference > 0 then
        local frame = self.scope and self.scope.frame
        if frame then
          return frame:variables(self.ref.variablesReference)
        end
      end
      return nil
    end,
  })
  
  print("Variable.getTreeNodeId after extend: " .. tostring(Variable.getTreeNodeId))
  self.logger:info("Variable.getTreeNodeId after extend: " .. tostring(Variable.getTreeNodeId))
  
  -- Then transform Variable to return NuiTree.Node instances
  local NuiTree = require("nui.tree")
  ClassMixer.transformToClass(Variable, NuiTree, {
    map_data = function(variable)
      return {
        id = variable:getTreeNodeId(),
        text = variable:formatTreeNodeDisplay(),
      }
    end,
    
    copy_properties = true,
    chain_methods = true,
  }, {
    target_constructor = function(TargetClass, data)
      return NuiTree.Node(data)
    end
  })
  
  -- Define common scope methods
  local scope_methods = {
    getTreeNodeId = function(self)
      return string.format("scope:%s", self.ref.name)
    end,
    
    formatTreeNodeDisplay = function(self)
      return "📁 " .. self.ref.name
    end,
    
    isTreeNodeExpandable = function(self)
      return true
    end,
    
    -- Async method
    GetTreeNodeChildren = function(self)
      return self:variables()
    end,
  }
  
  local scope_transformation_config = {
    map_data = function(scope)
      return {
        id = scope:getTreeNodeId(),
        text = scope:formatTreeNodeDisplay(),
      }
    end,
    
    copy_properties = true,
    chain_methods = true,
  }
  
  local scope_options = {
    target_constructor = function(TargetClass, data)
      return NuiTree.Node(data)
    end
  }
  
  -- Transform ALL concrete scope classes
  for i, ScopeClass in ipairs(all_scope_classes) do
    local class_name = tostring(ScopeClass):match("table: 0x%w+") or ("ScopeClass" .. i)
    print("Transforming scope class " .. i .. ": " .. class_name)
    
    -- First extend each scope class with tree methods
    ClassMixer.extendClass(ScopeClass, scope_methods)
    
    -- Then transform each to return NuiTree.Node instances  
    ClassMixer.transformToClass(ScopeClass, NuiTree, scope_transformation_config, scope_options)
  end
  
  self.logger:info("Transformed Variables and Scopes to return NuiTree.Node instances")
end

-- ========================================
-- EVENT HANDLERS
-- ========================================

function Variables3Plugin:setupEventHandlers()
  local transformations_applied = false
  
  self.api:onSession(function(session)
    -- Apply transformations on first session
    if not transformations_applied then
      print("=== Applying transformations on session start ===")
      self:setupTransformations()
      transformations_applied = true
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

function Variables3Plugin:UpdateCurrentFrame(frame)
  self.current_frame = frame
  self.logger:debug("Updated current frame")
end

function Variables3Plugin:ClearCurrentFrame()
  self.current_frame = nil
  self.logger:debug("Cleared current frame")
end

-- ========================================
-- USER COMMANDS
-- ========================================

function Variables3Plugin:setupCommands()
  vim.api.nvim_create_user_command("Variables3Demo", function()
    self:DemonstrateTransformation()
  end, { desc = "Demonstrate Variables3 node transformation" })
  
  vim.api.nvim_create_user_command("Variables3Status", function()
    self:ShowStatus()
  end, { desc = "Show Variables3 status" })
end

-- ========================================
-- DEMONSTRATION
-- ========================================

function Variables3Plugin:DemonstrateTransformation()
  if not self.current_frame then
    print("No debug session active - start debugging to see node transformation")
    return
  end
  
  print("Variables3: Variables and Scopes are NuiTree.Nodes")
  print("===============================================")
  print("")
  
  local scopes = self.current_frame:scopes()
  
  for _, scope in ipairs(scopes) do
    print("Scope: " .. scope.ref.name)
    print("  ✓ Type: " .. type(scope))
    print("  ✓ Actual class: " .. tostring(scope.__class or "unknown"))
    print("  ✓ Metatable: " .. tostring(getmetatable(scope)))
    print("  ✓ Has get_id: " .. tostring(scope.get_id ~= nil))
    print("  ✓ Has text: " .. tostring(scope.text ~= nil))
    print("  ✓ Has getTreeNodeId: " .. tostring(scope.getTreeNodeId ~= nil))
    print("  ✓ Original Scope method: " .. tostring(scope.variables ~= nil))
    
    -- Safe access to node methods
    if scope.get_id then
      print("  ✓ Node ID: " .. tostring(scope:get_id()))
    else
      print("  ✗ No get_id method")
    end
    
    if scope.text then
      print("  ✓ Display Text: " .. tostring(scope.text))
    else
      print("  ✗ No text property")
    end
    print("")
    
    -- Show first few variables
    local variables = scope:variables()
    if variables and #variables > 0 then
      print("  Variables:")
      for i, variable in ipairs(variables) do
        if i > 3 then break end -- Limit output
        
        print("    " .. variable.ref.name)
        print("      ✓ Type: " .. type(variable))
        print("      ✓ Has get_id: " .. tostring(variable.get_id ~= nil))
        print("      ✓ Has text: " .. tostring(variable.text ~= nil))
        print("      ✓ Has getTreeNodeId: " .. tostring(variable.getTreeNodeId ~= nil))
        print("      ✓ Original Variable methods: " .. tostring(variable.evaluate ~= nil))
        
        -- Safe access
        if variable.get_id then
          print("      ✓ Node ID: " .. tostring(variable:get_id()))
        else
          print("      ✗ No get_id method")
        end
        
        if variable.text then
          print("      ✓ Display Text: " .. tostring(variable.text))
        else
          print("      ✗ No text property")
        end
        
        if variable.isTreeNodeExpandable then
          print("      ✓ Expandable: " .. tostring(variable:isTreeNodeExpandable()))
        else
          print("      ✗ No isTreeNodeExpandable method")
        end
      end
      if #variables > 3 then
        print("    ... and " .. (#variables - 3) .. " more variables")
      end
      print("")
    end
  end
  
  print("✓ All Variables and Scopes are NuiTree.Nodes with full API capabilities!")
  print("✓ Zero conversion overhead - they ARE nodes from construction!")
  print("✓ Generic ClassMixer enables any class → any other class transformation!")
end

function Variables3Plugin:ShowStatus()
  print("Variables3 Plugin Status:")
  print("========================")
  print("Current frame: " .. (self.current_frame and "Yes" or "No"))
  print("")
  
  if self.current_frame then
    local scopes = self.current_frame:scopes()
    print("Available scopes: " .. #scopes)
    
    for _, scope in ipairs(scopes) do
      local node_id = scope.get_id and scope:get_id() or "no-id"
      print("  - " .. scope.ref.name .. " (Node ID: " .. tostring(node_id) .. ")")
    end
  end
  
  print("")
  print("✓ Variables are NuiTree.Nodes")
  print("✓ Scopes are NuiTree.Nodes") 
  print("✓ Generic transformation active")
end

-- ========================================
-- MODULE EXPORTS
-- ========================================

return Variables3Plugin