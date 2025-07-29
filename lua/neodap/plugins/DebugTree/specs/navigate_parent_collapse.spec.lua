-- Test for h key navigation with parent collapse behavior
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
  T.cmd("DebugTreeFrame")
  T.sleep(300) -- Let UI render
  T.TerminalSnapshot('tree_initial')
  
  -- Expand a scope (Local scope)
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(300)
  T.TerminalSnapshot('scope_expanded')
  
  -- Navigate into a variable
  T.cmd("normal! j") -- Move to first variable
  T.cmd("execute \"normal \\<CR>\"") -- Expand it
  T.sleep(300)
  T.TerminalSnapshot('variable_expanded')
  
  -- Navigate into a nested property
  T.cmd("normal! j") -- Move to a property
  T.TerminalSnapshot('at_nested_property')
  
  -- Press h to navigate to parent (should collapse the parent)
  T.cmd("normal! h")
  T.sleep(100)
  T.TerminalSnapshot('parent_collapsed_after_h')
  
  -- Press h again to go up another level (should collapse that parent too)
  T.cmd("normal! h")
  T.sleep(100)
  T.TerminalSnapshot('grandparent_collapsed_after_h')
  
  -- Expand again to verify the behavior
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(300)
  T.TerminalSnapshot('reexpanded_to_verify')
end)