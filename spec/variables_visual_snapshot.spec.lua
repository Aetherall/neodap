-- Visual verification test for Variables4 plugin
-- This test generates snapshots to visually verify the Variables4 NUI tree displays correctly
-- and allows interactive navigation through variable scopes

local T = require("testing.testing")(describe, it)
local CommonSetups = require("testing.common_setups")

T.Scenario(function(api)
  -- Load standard plugins
  local plugins = CommonSetups.loadStandardPlugins(api)

  -- Change to the fixture directory and open the file
  T.cmd("cd lua/testing/fixtures/variables")
  T.cmd("edit complex.js")
  T.TerminalSnapshot('01_initial_file')

  -- Launch the debug session - this will hit the debugger statement
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(2000) -- Wait for debugger to start and hit breakpoint

  -- Take snapshot showing stopped at debugger
  T.TerminalSnapshot('02_stopped_at_debugger')

  -- Open the Variables4 NUI tree popup
  T.cmd("Variables4Tree")
  T.sleep(500)

  -- Take snapshot showing the Variables4 popup with collapsed scopes
  T.TerminalSnapshot('03_variables4_popup_scopes')

  -- Expand the first scope (Local) using Enter key
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(1000)

  -- Take snapshot showing expanded Local scope with all variables
  T.TerminalSnapshot('04_local_scope_expanded')

  -- Navigate down and expand Global scope
  T.cmd("normal! j")
  T.sleep(100)
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(1000)

  -- Take snapshot showing both scopes expanded
  T.TerminalSnapshot('05_both_scopes_expanded')

  -- Navigate back to Local scope variables
  T.cmd("normal! k")
  T.cmd("normal! j")  -- Move to first variable
  T.sleep(100)

  -- Take snapshot showing navigation within variables
  T.TerminalSnapshot('06_variable_navigation')

  -- Close the popup with q
  T.cmd("normal! q")
  T.sleep(300)

  -- Take final snapshot showing return to normal editing
  T.TerminalSnapshot('07_popup_closed')
end)

