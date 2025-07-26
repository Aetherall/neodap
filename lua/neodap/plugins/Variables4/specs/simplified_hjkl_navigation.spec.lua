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
  T.TerminalSnapshot('simplified_initial_tree_hjkl_only')

  -- Test that Enter/Space keys no longer work for expansion
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(200)
  T.TerminalSnapshot('simplified_enter_has_no_effect')

  T.cmd("execute \"normal \\<Space>\"")
  T.sleep(200) 
  T.TerminalSnapshot('simplified_space_has_no_effect')

  -- Test hjkl navigation is the primary method
  -- l key: expand and move to first child 
  T.cmd("normal! l")
  T.sleep(500) -- Wait for async expansion and navigation
  T.TerminalSnapshot('simplified_l_expand_and_navigate')

  -- j key: navigate down through visible nodes
  T.cmd("normal! j")
  T.TerminalSnapshot('simplified_j_navigate_down')

  -- k key: navigate up through visible nodes
  T.cmd("normal! k")
  T.TerminalSnapshot('simplified_k_navigate_up')

  -- Navigate to expandable variable and test l key
  T.cmd("normal! j")
  T.cmd("normal! j") -- Position on expandable variable
  T.TerminalSnapshot('simplified_on_expandable_variable')

  -- l key: expand variable and move to first child
  T.cmd("normal! l")
  T.sleep(300)
  T.TerminalSnapshot('simplified_l_expand_variable_and_navigate')

  -- h key: collapse current node
  T.cmd("normal! h")
  T.TerminalSnapshot('simplified_h_collapse')

  -- h key again: move to parent node
  T.cmd("normal! h")
  T.TerminalSnapshot('simplified_h_move_to_parent')

  -- Test focus mode with hjkl-only navigation
  T.cmd("normal! f") -- Enter focus mode
  T.sleep(200)
  T.TerminalSnapshot('simplified_focus_mode_entered')

  -- Test that hjkl works seamlessly in focus mode
  T.cmd("normal! l") -- Should expand and auto-focus
  T.sleep(500)
  T.TerminalSnapshot('simplified_focus_l_auto_focus')

  T.cmd("normal! j")
  T.cmd("normal! j")
  T.cmd("normal! l") -- Drill deeper
  T.sleep(500)
  T.TerminalSnapshot('simplified_focus_drill_deeper')

  T.cmd("normal! h") -- Should defocus
  T.sleep(300)
  T.TerminalSnapshot('simplified_focus_defocus')

  T.cmd("normal! r") -- Exit focus mode
  T.sleep(200)
  T.TerminalSnapshot('simplified_focus_exit')

  -- Test help text shows hjkl-only navigation
  T.cmd("normal! ?")
  T.TerminalSnapshot('simplified_help_text_hjkl_only')

  -- Close popup
  T.cmd("normal! q")
  T.TerminalSnapshot('simplified_test_complete')
end)