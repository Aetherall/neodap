local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables4'))

  -- Set up initial state and launch session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j") -- Move to line with variables
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables")
  T.sleep(1500) -- Wait for session and breakpoint hit

  -- Open the variables tree popup
  T.cmd("Variables4Tree")
  T.sleep(300)
  T.TerminalSnapshot('cursor_name_initial_scopes')

  -- Test 1: Cursor Position on Scope Names
  -- Verify cursor is positioned at first character of scope name
  T.TerminalSnapshot('cursor_name_scope_local_position')

  -- Move to Global scope and verify cursor position
  T.cmd("normal! j")
  T.TerminalSnapshot('cursor_name_scope_global_position')

  -- Test 2: Cursor Position After Expansion
  -- Expand Local scope and verify cursor position on variables
  T.cmd("normal! k") -- Back to Local scope
  T.cmd("normal! l") -- Expand Local scope
  T.sleep(500)
  T.TerminalSnapshot('cursor_name_after_local_expansion')

  -- Test 3: Cursor Position on Variable Names
  -- Navigate through variables and verify cursor is at name start
  T.cmd("normal! j") -- Move to first variable
  T.TerminalSnapshot('cursor_name_first_variable')

  T.cmd("normal! j") -- Move to second variable
  T.TerminalSnapshot('cursor_name_second_variable')

  T.cmd("normal! j") -- Move to third variable
  T.TerminalSnapshot('cursor_name_third_variable')

  -- Test 4: Cursor Position in Focus Mode
  -- Test that cursor positioning works correctly in focus mode
  T.cmd("normal! f") -- Enable focus mode
  T.sleep(200)
  T.TerminalSnapshot('cursor_name_focus_mode_enabled')

  -- Navigate in focus mode and verify cursor positions
  T.cmd("normal! j") -- Navigate in focus mode
  T.TerminalSnapshot('cursor_name_focus_mode_navigation')

  T.cmd("normal! l") -- Drill down in focus mode
  T.sleep(300)
  T.TerminalSnapshot('cursor_name_focus_mode_drilldown')

  -- Test 5: Cursor Position After H-key Navigation
  -- Test cursor position after jumping to parent
  T.cmd("normal! h") -- Jump to parent
  T.sleep(200)
  T.TerminalSnapshot('cursor_name_after_jump_to_parent')

  -- Test 6: Cursor Position in Deep Hierarchy
  -- Test cursor positioning at different indentation levels
  T.cmd("normal! f") -- Exit focus mode
  T.sleep(200)
  T.cmd("normal! l") -- Drill down
  T.sleep(300)
  T.cmd("normal! l") -- Drill deeper
  T.sleep(300)
  T.TerminalSnapshot('cursor_name_deep_hierarchy_level_1')

  T.cmd("normal! l") -- Drill even deeper
  T.sleep(300)
  T.TerminalSnapshot('cursor_name_deep_hierarchy_level_2')

  -- Test that cursor is properly positioned at each level
  T.cmd("normal! h") -- Back up one level
  T.sleep(200)
  T.TerminalSnapshot('cursor_name_backup_to_level_1')

  T.cmd("normal! h") -- Back up another level
  T.sleep(200)
  T.TerminalSnapshot('cursor_name_backup_to_scope_level')

  -- Test 7: Cursor Position in Global Scope
  -- Test cursor positioning in different scope types
  T.cmd("normal! j") -- Move to Global scope
  T.cmd("normal! l") -- Expand Global scope
  T.sleep(500)
  T.TerminalSnapshot('cursor_name_global_scope_expanded')

  -- Navigate through global variables
  T.cmd("normal! j") -- Move to first global variable
  T.TerminalSnapshot('cursor_name_global_variable_1')

  T.cmd("normal! j") -- Move to second global variable
  T.TerminalSnapshot('cursor_name_global_variable_2')

  -- Test 8: Cursor Position Consistency Check
  -- Rapid navigation to test cursor position stability
  T.cmd("normal! k") -- Up
  T.cmd("normal! j") -- Down
  T.cmd("normal! k") -- Up
  T.cmd("normal! j") -- Down
  T.TerminalSnapshot('cursor_name_rapid_navigation_stable')

  -- Test 9: Cursor Position with UTF-8 Indicators
  -- Verify cursor position accounts for UTF-8 indent indicators
  T.cmd("normal! l") -- Drill down to create indentation
  T.sleep(300)
  T.TerminalSnapshot('cursor_name_with_utf8_indentation')

  -- Test 10: Round-trip Cursor Consistency
  -- Complete navigation cycle to verify cursor positioning remains consistent
  T.cmd("normal! h") -- Back up
  T.sleep(200)
  T.cmd("normal! l") -- Drill down again
  T.sleep(300)
  T.TerminalSnapshot('cursor_name_round_trip_consistency')

  -- Close popup
  T.cmd("normal! q")
  T.TerminalSnapshot('cursor_name_positioning_test_complete')
end)