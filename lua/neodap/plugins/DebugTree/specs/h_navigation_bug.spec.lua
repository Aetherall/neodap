-- Test to reproduce h navigation bug where cursor moves to wrong scope
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))

  -- Open test file and launch debugger
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 9j") -- Move to line 10 for breakpoint
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500) -- Wait for debugger to hit breakpoint
  
  -- Open the frame tree (starts with scopes)
  T.cmd("DebugTreeFrame")
  T.sleep(300) -- Let UI render
  T.TerminalSnapshot('frame_tree_initial')
  
  -- Expand first scope (Local)
  T.cmd("normal! l")
  T.TerminalSnapshot('local_scope_expanded')
  
  -- Navigate down to a variable in Local scope
  T.cmd("normal! j")
  T.cmd("normal! j") -- Should be on a variable now
  T.TerminalSnapshot('on_variable_in_local')
  
  -- Navigate to parent with h - should go to Local scope
  T.cmd("normal! h")
  T.TerminalSnapshot('after_h_should_be_on_local_scope')
  
  -- Let's try another scenario - expand multiple scopes
  T.cmd("normal! j") -- Move to next scope (Closure or Global)
  T.cmd("normal! l") -- Expand it
  T.TerminalSnapshot('second_scope_expanded')
  
  -- Navigate into a variable in the second scope
  T.cmd("normal! j")
  T.TerminalSnapshot('on_variable_in_second_scope')
  
  -- Navigate back with h
  T.cmd("normal! h")
  T.TerminalSnapshot('after_h_from_second_scope_variable')
end)