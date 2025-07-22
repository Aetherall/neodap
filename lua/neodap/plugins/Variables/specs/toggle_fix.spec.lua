-- Test to verify the Variables plugin properly uses Neo-tree's delegation pattern
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables'))

  -- Set up initial state and launch session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 15gg") -- Go to line 15 where breakpoint should be
  T.cmd("NeodapToggleBreakpoint")
  T.sleep(500)
  
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500) -- Wait for session to start and hit breakpoint
  
  -- Open Variables window
  T.cmd("NeodapVariablesShow")
  T.sleep(300) -- Let UI render
  T.TerminalSnapshot('variables_initial')
  
  -- Navigate to Variables window
  T.cmd("wincmd h") -- Move to left window (variables)
  T.TerminalSnapshot('variables_focused')
  
  -- Test expanding first scope (Locals)
  T.cmd("normal! j") -- Move to first scope
  T.cmd("execute \"normal \\<CR>\"") -- Use execute for Neo-tree buffer
  T.sleep(500) -- Wait for async loading
  T.TerminalSnapshot('locals_expanded')
  
  -- Test expanding a variable within Locals
  T.cmd("normal! j") -- Move to first variable
  T.cmd("execute \"normal \\<CR>\"") -- Expand complex object
  T.sleep(500)
  T.TerminalSnapshot('object_expanded')
  
  -- Test collapsing the variable
  T.cmd("execute \"normal \\<CR>\"") -- Toggle to collapse
  T.sleep(200)
  T.TerminalSnapshot('object_collapsed')
  
  -- Test expanding second scope (Global)
  T.cmd("normal! k") -- Move back up
  T.cmd("normal! k") -- Move to Locals scope
  T.cmd("normal! j") -- Move to Global scope
  T.cmd("normal! j") -- Skip past locals variables
  T.cmd("execute \"normal \\<CR>\"") -- Expand Global
  T.sleep(500)
  T.TerminalSnapshot('global_expanded')
  
  -- Continue execution to verify state clears properly
  T.cmd("NeodapContinue")
  T.sleep(1000)
  T.TerminalSnapshot('after_continue')
end)