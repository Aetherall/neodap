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
  T.TerminalSnapshot('cursor_test_initial_state')

  -- Test that cursor positioning works with l key
  T.cmd("normal! l")
  T.sleep(500) -- Wait for async expansion
  T.TerminalSnapshot('cursor_test_after_l_expand_and_move')

  -- Test j key cursor movement
  T.cmd("normal! j")
  T.TerminalSnapshot('cursor_test_after_j_move_down')

  -- Test k key cursor movement
  T.cmd("normal! k")
  T.TerminalSnapshot('cursor_test_after_k_move_up')

  -- Test h key cursor movement to parent
  T.cmd("normal! h")
  T.TerminalSnapshot('cursor_test_after_h_move_to_parent')

  -- Close popup
  T.cmd("normal! q")
  T.TerminalSnapshot('cursor_test_closed')
end)