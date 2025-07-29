-- Test to verify path-based IDs are working correctly
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))

  -- Open test file and set breakpoint
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 9j") -- Move to line 10
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500) -- Wait for debugger to hit breakpoint
  
  -- Open debug tree
  T.cmd("DebugTree")
  T.sleep(300)
  T.TerminalSnapshot('tree_opened')
  
  -- Navigate down the tree to see path-based IDs
  T.cmd("normal! l") -- Into session
  T.sleep(100)
  T.cmd("normal! l") -- Into thread
  T.sleep(100)
  T.cmd("normal! l") -- Into stack
  T.sleep(100) 
  T.cmd("normal! l") -- Into frame (should load scopes)
  T.sleep(200)
  T.TerminalSnapshot('scopes_visible')
  
  -- Check a node's debug info to see the path-based ID
  T.cmd("normal! !") -- Show debug info for current frame
  T.sleep(200)
  T.TerminalSnapshot('frame_debug_info')
  T.cmd("normal! q") -- Close debug popup
  
  -- Navigate to a scope
  T.cmd("normal! j") -- Move to first scope
  T.cmd("normal! !") -- Show debug info
  T.sleep(200)
  T.TerminalSnapshot('scope_debug_info')
  T.cmd("normal! q") -- Close debug popup
  
  -- Expand scope to see variables
  T.cmd("normal! l") -- Expand scope
  T.sleep(200)
  T.cmd("normal! j") -- Move to a variable
  T.cmd("normal! !") -- Show debug info
  T.sleep(200)
  T.TerminalSnapshot('variable_debug_info')
end)