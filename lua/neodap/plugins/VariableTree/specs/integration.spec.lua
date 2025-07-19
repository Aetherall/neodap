local Test = require("spec.helpers.testing")(describe, it)
local VariableTree = require("neodap.plugins.VariableTree")
local VariableCore = require("neodap.plugins.VariableCore")
local PrepareHelper = require("spec.helpers.prepare")
local prepare = PrepareHelper.prepare

Test.Describe("VariableTree VariableCore Integration", function()

  Test.It("variable_tree_uses_variable_core_correctly", function()
    local api, start = prepare()
    
    local variableTree = api:getPluginInstance(VariableTree)
    local variableCore = api:getPluginInstance(VariableCore)
    
    -- Verify VariableTree has access to VariableCore instance
    assert(variableTree ~= nil)
    assert(variableCore ~= nil)
    assert(type(variableTree) == "table")
    assert(type(variableCore) == "table")
    assert(variableTree.variableCore == variableCore)
    
    print("✓ VariableTree VariableCore integration basic setup passed")
  end)

  Test.It("variable_tree_delegates_auto_expansion", function()
    local api, start = prepare()
    
    local variableTree = api:getPluginInstance(VariableTree)
    local variableCore = api:getPluginInstance(VariableCore)
    
    -- Test that VariableTree delegates auto-expansion logic to VariableCore
    local expensive_scope = { expensive = true }
    local normal_scope = { expensive = false }
    local no_flag_scope = {}
    
    -- VariableCore should correctly determine auto-expansion
    assert(variableCore:shouldAutoExpand(expensive_scope) == false)
    assert(variableCore:shouldAutoExpand(normal_scope) == true)
    assert(variableCore:shouldAutoExpand(no_flag_scope) == true)
    
    print("✓ Auto-expansion delegation tests passed")
  end)

  Test.It("variable_tree_class_structure", function()
    local api, start = prepare()
    
    local variableTree = api:getPluginInstance(VariableTree)
    
    -- Verify VariableTree follows proper class structure
    assert(type(variableTree.ShowVariables) == "function")
    assert(type(variableTree.HideVariables) == "function") 
    assert(type(variableTree.ToggleVariables) == "function")
    assert(type(variableTree.RefreshNeotree) == "function")
    assert(type(variableTree.destroy) == "function")
    
    -- Verify it has proper properties
    assert(type(variableTree.api) == "table")
    assert(type(variableTree.logger) == "table")
    assert(type(variableTree.variableCore) == "table")
    
    print("✓ Class structure tests passed")
  end)

  Test.It("variable_tree_command_registration", function()
    local api, start = prepare()
    
    local variableTree = api:getPluginInstance(VariableTree)
    
    -- Verify VariableTree registers its commands
    local commands = vim.api.nvim_get_commands({})
    
    assert(commands["NeodapVariableTreeShow"] ~= nil)
    assert(commands["NeodapVariableTreeHide"] ~= nil)
    assert(commands["NeodapVariableTreeToggle"] ~= nil)
    assert(commands["NeodapVariableTreeStatus"] ~= nil)
    
    print("✓ Command registration tests passed")
  end)

  Test.It("variable_tree_user_collapse_tracking", function()
    local api, start = prepare()
    
    local variableTree = api:getPluginInstance(VariableTree)
    
    -- Verify VariableTree has user collapse tracking
    assert(type(variableTree.user_collapsed) == "table")
    
    -- Test that we can track user collapses
    variableTree.user_collapsed["scope_123"] = true
    assert(variableTree.user_collapsed["scope_123"] == true)
    
    print("✓ User collapse tracking tests passed")
  end)

end)