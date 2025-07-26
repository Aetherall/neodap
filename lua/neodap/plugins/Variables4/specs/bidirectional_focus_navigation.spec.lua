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
  T.TerminalSnapshot('bidirectional_initial_tree')

  -- Enter focus mode on Local scope
  T.cmd("normal! f")
  T.sleep(200)
  T.TerminalSnapshot('bidirectional_focus_mode_entered')

  -- Drill down: expand Local scope - should auto-focus
  T.cmd("normal! l")
  T.sleep(500) -- Wait for async expansion and auto-focus
  T.TerminalSnapshot('bidirectional_drilled_into_local_scope')

  -- Navigate to an expandable variable (objectVar or arrayVar)
  T.cmd("normal! j") -- Move through variables
  T.cmd("normal! j")
  T.cmd("normal! j") -- Position on expandable variable
  T.TerminalSnapshot('bidirectional_on_expandable_variable')

  -- Drill down further: expand variable - should auto-focus deeper
  T.cmd("normal! l")
  T.sleep(500) -- Wait for async expansion and auto-focus
  T.TerminalSnapshot('bidirectional_drilled_into_variable')

  -- Navigate to a nested property if available
  T.cmd("normal! j")
  T.TerminalSnapshot('bidirectional_in_nested_content')

  -- Test defocus: collapse current level - should defocus to previous level
  T.cmd("normal! h")
  T.sleep(300)
  T.TerminalSnapshot('bidirectional_defocused_one_level')

  -- Test defocus again: should go up another level
  T.cmd("normal! h")
  T.sleep(300)
  T.TerminalSnapshot('bidirectional_defocused_two_levels')

  -- Test defocus to exit: should exit focus mode entirely
  T.cmd("normal! h")
  T.sleep(300)
  T.TerminalSnapshot('bidirectional_exited_focus_mode')

  -- Re-enter focus mode to test navigation-based defocus
  T.cmd("normal! f")
  T.sleep(200)
  
  -- Drill down multiple levels again
  T.cmd("normal! l") -- Expand scope
  T.sleep(500)
  T.cmd("normal! j")
  T.cmd("normal! j")
  T.cmd("normal! l") -- Expand variable
  T.sleep(500)
  T.TerminalSnapshot('bidirectional_drilled_for_navigation_test')

  -- Test parent navigation defocus: move to parent with h
  T.cmd("normal! h") -- Should trigger defocus when moving to parent
  T.sleep(300)
  T.TerminalSnapshot('bidirectional_navigation_defocus_test')

  -- Close popup
  T.cmd("normal! q")
  T.TerminalSnapshot('bidirectional_test_complete')
end)