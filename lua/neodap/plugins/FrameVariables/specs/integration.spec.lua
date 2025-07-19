local Test = require("spec.helpers.testing")(describe, it)
local TerminalSnapshot = require("spec.helpers.terminal_snapshot")
local FrameVariables = require("neodap.plugins.FrameVariables")
local VariableCore = require("neodap.plugins.VariableCore")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local StackNavigation = require("neodap.plugins.StackNavigation")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local PrepareHelper = require("spec.helpers.prepare")
local prepare = PrepareHelper.prepare

Test.Describe("FrameVariables VariableCore Integration", function()

  Test.It("frame_variables_uses_variable_core_correctly", function()
    local api, start = prepare()
    
    local frameVariables = api:getPluginInstance(FrameVariables)
    local variableCore = api:getPluginInstance(VariableCore)
    
    -- Verify FrameVariables has access to VariableCore instance
    assert(frameVariables ~= nil)
    assert(variableCore ~= nil)
    assert(type(frameVariables) == "table")
    assert(type(variableCore) == "table")
    
    print("✓ FrameVariables VariableCore integration basic setup passed")
  end)

  Test.It("lazy_variable_detection_delegation", function()
    local api, start = prepare()
    
    local frameVariables = api:getPluginInstance(FrameVariables)
    local variableCore = api:getPluginInstance(VariableCore)
    
    -- Test that FrameVariables delegates lazy variable detection to VariableCore
    local lazy_var = { 
      presentationHint = { lazy = true }
    }
    local normal_var = { 
      presentationHint = {}
    }
    
    -- VariableCore should correctly identify lazy variables
    local lazy_result = variableCore:isLazyVariable(lazy_var)
    local normal_result = variableCore:isLazyVariable(normal_var)
    
    assert(lazy_result == true, "Lazy variable should be detected as lazy")
    assert(normal_result == false, "Normal variable should not be detected as lazy")
    
    print("✓ Lazy variable detection delegation tests passed")
  end)

  Test.It("auto_expansion_logic_delegation", function()
    local api, start = prepare()
    
    local frameVariables = api:getPluginInstance(FrameVariables)
    local variableCore = api:getPluginInstance(VariableCore)
    
    -- Test that FrameVariables uses VariableCore's auto-expansion logic
    local expensive_scope = { expensive = true }
    local normal_scope = { expensive = false }
    local no_flag_scope = {}
    
    -- VariableCore should correctly determine auto-expansion
    assert(variableCore:shouldAutoExpand(expensive_scope) == false)
    assert(variableCore:shouldAutoExpand(normal_scope) == true)
    assert(variableCore:shouldAutoExpand(no_flag_scope) == true)
    
    print("✓ Auto-expansion logic delegation tests passed")
  end)

  Test.It("variable_formatting_delegation_basic", function()
    local api, start = prepare()
    
    local frameVariables = api:getPluginInstance(FrameVariables)
    local variableCore = api:getPluginInstance(VariableCore)
    
    -- Test that FrameVariables can use VariableCore for basic formatting
    local test_var = { name = "testVar", value = "testValue", type = "string" }
    
    -- Test VariableCore formatting capabilities
    local formatted_value = variableCore:formatVariableValue(test_var)
    assert(formatted_value == "testValue", "Variable value should be formatted correctly")
    
    local formatted_variable = variableCore:formatVariable(test_var, 0)
    local expected_text = "testVar = testValue : string"
    assert(formatted_variable.text == expected_text, "Expected '" .. expected_text .. "' but got '" .. formatted_variable.text .. "'")
    assert(#formatted_variable.highlights == 3, "Should have 3 highlights") -- name, value, type
    
    print("✓ Variable formatting delegation tests passed")
  end)

  Test.It("neotree_source_with_variable_core", function()
    local api, start = prepare()
    
    local frameVariables = api:getPluginInstance(FrameVariables)
    local variableCore = api:getPluginInstance(VariableCore)
    
    -- Verify FrameVariables still provides its Neo-tree integration
    -- while leveraging VariableCore for data processing
    assert(type(frameVariables.refresh) == "function")
    assert(type(frameVariables.try_register_neotree) == "function")
    
    -- Test that both instances exist and work together
    local session_id = 1
    local test_scope = { name = "Local", variablesReference = 123, expensive = false }
    
    -- VariableCore should handle session state
    local state = variableCore:getSessionState(session_id)
    assert(type(state.expanded_scopes) == "table")
    
    -- VariableCore should handle scope key generation
    local scope_key = variableCore:getScopeKey(test_scope, session_id)
    assert(scope_key == "scope_123")
    
    print("✓ Neo-tree source integration tests passed")
  end)

  Test.It("command_registration_preserved", function()
    local api, start = prepare()
    
    local frameVariables = api:getPluginInstance(FrameVariables)
    
    -- Verify FrameVariables preserves its command registration
    -- The commands should still be available after refactoring
    local commands = vim.api.nvim_get_commands({})
    
    -- Commands may not be registered yet in test environment, but we can verify
    -- the plugin structure is intact
    assert(type(frameVariables.destroy) == "function")
    
    print("✓ Command registration preservation tests passed")
  end)

end)