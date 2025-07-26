local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables4'))

  -- Set up initial state and launch session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1100)

  -- Open the variables tree popup
  T.cmd("Variables4Tree")
  T.sleep(300)
  T.TerminalSnapshot('simple_focus_initial_full_tree')

  -- Navigate into the tree with hjkl
  T.cmd("normal! l") -- Expand Local scope
  T.sleep(500)
  T.cmd("normal! j") -- Move down to a variable
  T.cmd("normal! j") -- Move down to another variable
  T.TerminalSnapshot('simple_focus_navigated_to_variable')

  -- Toggle focus mode ON (should show parent subtree)
  T.cmd("normal! f")
  T.sleep(200)
  T.TerminalSnapshot('simple_focus_mode_on_parent_subtree')

  -- Navigate within focused subtree
  T.cmd("normal! j")
  T.cmd("normal! l") -- Expand a variable
  T.sleep(300)
  T.TerminalSnapshot('simple_focus_navigate_in_subtree')

  -- Toggle focus mode OFF (should restore full tree)
  T.cmd("normal! f")
  T.sleep(200)
  T.TerminalSnapshot('simple_focus_mode_off_full_tree_restored')

  -- Navigate deeper and focus again
  T.cmd("normal! l") -- Enter variable
  T.sleep(300)
  T.cmd("normal! j")
  T.TerminalSnapshot('simple_focus_deeper_navigation')

  -- Toggle focus mode ON at deeper level
  T.cmd("normal! f")
  T.sleep(200)
  T.TerminalSnapshot('simple_focus_mode_on_deeper_level')

  -- Test that focus at root level is handled
  T.cmd("normal! f") -- Toggle off
  T.sleep(200)
  T.cmd("normal! h") -- Move back up
  T.cmd("normal! h") -- Move to root
  T.cmd("normal! h") -- Try to go above root
  T.TerminalSnapshot('simple_focus_at_root_level')

  -- Try focus mode at root (should show error)
  T.cmd("normal! f")
  T.TerminalSnapshot('simple_focus_cannot_focus_at_root')

  -- Show help to verify updated text
  T.cmd("normal! ?")
  T.TerminalSnapshot('simple_focus_updated_help_text')

  -- Close popup
  T.cmd("normal! q")
  T.TerminalSnapshot('simple_focus_test_complete')
end)