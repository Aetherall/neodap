local Test = require("spec.helpers.testing")(describe, it)
local TerminalSnapshot = require("spec.helpers.terminal_snapshot")
local ScopeViewer = require("neodap.plugins.ScopeViewer")
local VariableCore = require("neodap.plugins.VariableCore")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local StackNavigation = require("neodap.plugins.StackNavigation")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local PrepareHelper = require("spec.helpers.prepare")
local prepare = PrepareHelper.prepare

Test.Describe("ScopeViewer VariableCore Integration", function()

  Test.It("scope_viewer_uses_variable_core_correctly", function()
    local api, start = prepare()
    
    local scopeViewer = api:getPluginInstance(ScopeViewer)
    local variableCore = api:getPluginInstance(VariableCore)
    
    -- Verify ScopeViewer has VariableCore instance
    assert(scopeViewer.variableCore ~= nil)
    assert(type(scopeViewer.variableCore) == "table")
    
    -- Mock frame for testing
    local mock_frame = {
      ref = { id = 1 },
      scopes = function()
        return {
          { ref = { name = "Local", variablesReference = 1, expensive = false } },
          { ref = { name = "Global", variablesReference = 2, expensive = true } }
        }
      end,
      variables = function(self, ref)
        if ref == 1 then
          return { { name = "localVar", value = "test", type = "string" } }
        else
          return {}
        end
      end
    }
    
    -- Test that ScopeViewer delegates to VariableCore correctly
    local session_id = 1
    
    -- Simulate Render call (this calls buildScopeTree internally)
    local lines, highlights, scope_map, expanded_state = variableCore:buildScopeTree(mock_frame, session_id)
    
    -- Verify basic structure
    assert(#lines > 0)
    assert(type(highlights) == "table")
    assert(type(scope_map) == "table")
    assert(type(expanded_state) == "table")
    
    -- Check that Local scope is auto-expanded and Global is collapsed
    local content = table.concat(lines, "\n")
    assert(content:match("▼ Local"), "Local scope should be auto-expanded")
    assert(content:match("▶ Global"), "Global scope should be collapsed (expensive)")
    
    print("✓ ScopeViewer VariableCore integration tests passed")
  end)

  Test.It("scope_expansion_delegation_works", function()
    local api, start = prepare()
    
    local scopeViewer = api:getPluginInstance(ScopeViewer)
    local variableCore = api:getPluginInstance(VariableCore)
    
    local session_id = 1
    
    -- Mock scope
    local mock_scope = {
      ref = { name = "TestScope", variablesReference = 123, expensive = false }
    }
    
    -- Test scope expansion delegation
    local scope_key = "scope_123"
    
    -- Initial state should be nil
    assert(variableCore:getScopeExpansion(session_id, scope_key) == nil)
    
    -- Toggle through ScopeViewer should delegate to VariableCore
    scopeViewer:toggleScopeExpansion(mock_scope, session_id)
    
    -- Verify state changed in VariableCore
    assert(variableCore:getScopeExpansion(session_id, scope_key) == true)
    
    -- Toggle again
    scopeViewer:toggleScopeExpansion(mock_scope, session_id)
    assert(variableCore:getScopeExpansion(session_id, scope_key) == false)
    
    print("✓ Scope expansion delegation tests passed")
  end)

  Test.It("session_state_coordination_works", function()
    local api, start = prepare()
    
    local scopeViewer = api:getPluginInstance(ScopeViewer)
    local variableCore = api:getPluginInstance(VariableCore)
    
    local session_id = 1
    
    -- Initialize ScopeViewer session state
    scopeViewer:InitSessionState(session_id)
    
    -- Verify ScopeViewer session state exists
    local sv_state = scopeViewer:getSessionState(session_id)
    assert(sv_state ~= nil)
    assert(type(sv_state.current_frame) == "nil") -- Should be nil initially
    
    -- Verify VariableCore session state exists (created on demand)
    local vc_state = variableCore:getSessionState(session_id)
    assert(vc_state ~= nil)
    assert(type(vc_state.expanded_scopes) == "table")
    assert(type(vc_state.cached_variables) == "table")
    
    -- Test state interaction
    variableCore:setScopeExpansion(session_id, "test_scope", true)
    assert(variableCore:getScopeExpansion(session_id, "test_scope") == true)
    
    -- Cleanup
    scopeViewer:CleanupSessionState(session_id)
    
    -- Verify ScopeViewer state cleaned up
    local sv_state_after = scopeViewer:getSessionState(session_id)
    assert(next(sv_state_after) == nil) -- Should be empty table
    
    print("✓ Session state coordination tests passed")
  end)

  Test.It("render_method_integration_complete", function()
    local api, start = prepare()
    
    local scopeViewer = api:getPluginInstance(ScopeViewer)
    local debugOverlay = api:getPluginInstance(DebugOverlay)
    
    -- Mock the debug overlay methods to capture calls
    local set_left_panel_calls = {}
    debugOverlay.set_left_panel_content = function(self, lines, highlights, data)
      table.insert(set_left_panel_calls, { lines = lines, highlights = highlights, data = data })
    end
    
    -- Mock frame
    local mock_frame = {
      ref = { id = 1 },
      scopes = function()
        return {
          { ref = { name = "Local", variablesReference = 1, expensive = false } }
        }
      end,
      variables = function() return { { name = "var1", value = "value1" } } end
    }
    
    local session_id = 1
    scopeViewer:InitSessionState(session_id)
    
    -- Call Render (this should delegate to VariableCore internally)
    scopeViewer:Render(mock_frame, session_id)
    
    -- Verify debug overlay was called with proper content
    assert(#set_left_panel_calls == 1)
    local call_data = set_left_panel_calls[1]
    assert(#call_data.lines > 0)
    assert(type(call_data.highlights) == "table")
    assert(type(call_data.data.scope_map) == "table")
    
    -- Verify content contains expected scope structure
    local content = table.concat(call_data.lines, "\n")
    assert(content:match("▼ Local"), "Should contain expanded Local scope")
    assert(content:match("var1"), "Should contain variable name")
    
    print("✓ Render method integration tests passed")
  end)
end)