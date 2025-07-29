-- Test for l key drilling down and moving cursor to first child
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
  
  -- Open the debug tree
  T.cmd("DebugTree")
  T.sleep(300) -- Let UI render
  T.TerminalSnapshot('full_tree_initial')
  
  -- Drill into session with l
  T.cmd("normal! l")
  T.TerminalSnapshot('drilled_into_session')
  
  -- Drill into thread with l
  T.cmd("normal! l")
  T.TerminalSnapshot('drilled_into_thread')
  
  -- Drill into stack with l
  T.cmd("normal! l")
  T.TerminalSnapshot('drilled_into_stack')
  
  -- Drill into frame with l (this loads scopes lazily)
  T.cmd("normal! l")
  T.TerminalSnapshot('drilled_into_frame_cursor_on_first_scope')
  
  -- Drill into scope with l (this loads variables lazily)
  T.cmd("normal! l")
  T.TerminalSnapshot('drilled_into_scope_cursor_on_first_variable')
  
  -- Drill into a complex variable
  T.cmd("normal! l")
  T.TerminalSnapshot('drilled_into_variable_cursor_on_first_property')
  
  -- Navigate back up with h to verify it still works
  T.cmd("normal! h")
  T.sleep(100)
  T.TerminalSnapshot('navigated_back_parent_collapsed')
end)