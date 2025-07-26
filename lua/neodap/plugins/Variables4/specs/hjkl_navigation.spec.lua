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
  T.TerminalSnapshot('initial_tree_state_cursor_on_first_scope')

  -- Test l key: expand first scope AND move to first child
  T.cmd("normal! l")
  T.sleep(500) -- Wait for async expansion and navigation
  T.TerminalSnapshot('after_l_expand_and_move_to_first_variable')

  -- Test j key: tree-aware navigation down to next variable
  T.cmd("normal! j")
  T.TerminalSnapshot('after_j_tree_aware_down')

  -- Test j again: continue down through variables
  T.cmd("normal! j") 
  T.TerminalSnapshot('after_second_j_down')

  -- Test k key: tree-aware navigation up to previous variable
  T.cmd("normal! k")
  T.TerminalSnapshot('after_k_tree_aware_up')

  -- Navigate to an expandable variable and test l behavior
  T.cmd("normal! j") -- Move to arrayVar or objectVar
  T.cmd("normal! j")
  T.TerminalSnapshot('positioned_on_expandable_variable')

  -- Test l key: expand variable AND move to first child
  T.cmd("normal! l")
  T.sleep(300)
  T.TerminalSnapshot('after_l_expand_var_and_move_to_child')

  -- Test h key: collapse current node
  T.cmd("normal! h")
  T.TerminalSnapshot('after_h_collapse')

  -- Test h key again: move to parent
  T.cmd("normal! h")
  T.TerminalSnapshot('after_h_move_to_parent')

  -- Close popup
  T.cmd("normal! q")
  T.TerminalSnapshot('after_close_popup')
end)