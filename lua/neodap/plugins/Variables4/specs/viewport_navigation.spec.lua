-- Test for path-based viewport navigation in Variables4 plugin
-- Verifies that navigation automatically adjusts viewport when reaching boundaries

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load the Variables4 plugin
  local variables4_plugin = api:getPluginInstance(require('neodap.plugins.Variables4'))
  
  -- Load supporting plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  
  -- Launch debug session with complex variables
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500)  -- Wait for session to start
  
  -- Open the variables tree
  T.cmd("Variables4Tree")
  T.sleep(300)
  T.TerminalSnapshot('viewport_initial')
  
  -- Navigate into Local scope
  T.cmd("execute \"normal \\<CR>\"")  -- Expand Local
  T.sleep(300)
  T.cmd("normal! j")  -- Move to first variable
  T.cmd("normal! j")  -- Move to second variable
  T.TerminalSnapshot('viewport_in_local')
  
  -- Use 'f' to focus on the Local scope level
  T.cmd("normal! f")
  T.sleep(200)
  T.TerminalSnapshot('viewport_focused_local')
  
  -- Navigate to the top and press 'k' to go up beyond visible boundary
  -- This should adjust viewport to show parent level
  T.cmd("normal! gg")  -- Go to top of focused view
  T.cmd("normal! k")   -- Navigate up beyond boundary
  T.sleep(200)
  T.TerminalSnapshot('viewport_adjusted_up')
  
  -- Navigate into a nested object to test deep navigation
  T.cmd("execute \"normal \\<CR>\"")  -- Re-expand Local
  T.sleep(200)
  T.cmd("normal! /objectVar")  -- Search for objectVar
  T.cmd("normal! n")
  T.cmd("execute \"normal l\"")  -- Drill into objectVar
  T.sleep(300)
  T.TerminalSnapshot('viewport_in_object')
  
  -- Focus on the object level
  T.cmd("normal! f")
  T.sleep(200)
  T.TerminalSnapshot('viewport_focused_object')
  
  -- Navigate up to test viewport adjustment from deep level
  T.cmd("normal! k")
  T.cmd("normal! k")
  T.cmd("normal! k")  -- Should trigger viewport adjustment
  T.sleep(200)
  T.TerminalSnapshot('viewport_adjusted_from_deep')
  
  -- Test 'f' zoom out behavior
  T.cmd("normal! f")  -- Zoom out one level
  T.sleep(200)
  T.TerminalSnapshot('viewport_zoomed_out')
  
  -- Close the tree
  T.cmd("execute \"normal q\"")
  T.sleep(100)
  T.TerminalSnapshot('viewport_test_complete')
end)