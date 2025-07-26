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
  T.TerminalSnapshot('initial_tree_state')

  -- Navigate to Local scope and enter focus mode
  T.cmd("normal! f") -- Enter focus mode
  T.sleep(200)
  T.TerminalSnapshot('focus_mode_entered')

  -- Test l key: should expand and auto-drill to Local scope
  T.cmd("normal! l")
  T.sleep(500) -- Wait for async expansion and auto-focus
  T.TerminalSnapshot('focus_mode_after_l_auto_drill')

  -- Navigate to an expandable variable using j
  T.cmd("normal! j")
  T.cmd("normal! j") -- Move to objectVar or arrayVar
  T.TerminalSnapshot('focus_mode_on_expandable_var')

  -- Test l key again: should expand variable and auto-drill
  T.cmd("normal! l")
  T.sleep(500)
  T.TerminalSnapshot('focus_mode_drilled_into_variable')

  -- Test navigation within the focused variable
  T.cmd("normal! j")
  T.cmd("normal! j")
  T.TerminalSnapshot('focus_mode_navigate_within_var')

  -- Reset to full tree view
  T.cmd("normal! r")
  T.sleep(200)
  T.TerminalSnapshot('focus_mode_reset_to_full_tree')

  -- Close popup
  T.cmd("normal! q")
  T.TerminalSnapshot('after_close_popup')
end)