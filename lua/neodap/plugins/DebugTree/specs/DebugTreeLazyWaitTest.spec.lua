-- Test that cursor waits for lazy-loaded children before moving
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Use variables fixture with complex data
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j") -- Go to line with variables
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(2000) -- Wait for session to start and hit breakpoint
  
  -- Open frame-specific tree
  T.cmd("DebugTreeFrame")
  T.sleep(500)
  T.TerminalSnapshot('01_frame_tree_initial')
  
  -- Expand the frame - this triggers lazy loading of scopes
  T.cmd("execute \"normal \\<CR>\"")
  -- No sleep here - the async expand should wait for children
  T.TerminalSnapshot('02_frame_expanded_cursor_on_first_scope')
  
  -- The cursor should now be on the first scope (Local)
  -- Expand the Local scope - this triggers lazy loading of variables
  T.cmd("execute \"normal \\<CR>\"")
  -- Again, no sleep - should wait for variables to load
  T.TerminalSnapshot('03_scope_expanded_cursor_on_first_variable')
  
  -- Clean up
  T.cmd("normal! q")
  T.sleep(200)
end)