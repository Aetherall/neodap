-- DebugMode Integration Tests
-- Tests the orchestration plugin with 'v' key integration

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load orchestration and service plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.VariablesBuffer'))
  api:getPluginInstance(require('neodap.plugins.VariablesPopup'))
  api:getPluginInstance(require('neodap.plugins.DebugMode'))

  -- Set up debugging session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j")
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500)
  
  -- Test entering debug mode
  T.TerminalSnapshot('before_debug_mode')
  
  T.cmd("DebugModeEnter")
  T.sleep(300)
  T.TerminalSnapshot('debug_mode_entered')
  
  -- Test 'v' key integration - should show variables
  T.cmd("execute \"normal \\v\"") -- Send 'v' key
  T.sleep(500)
  T.TerminalSnapshot('v_key_variables_popup')
  
  -- Test navigation within debug mode variables
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(300)
  T.TerminalSnapshot('debug_mode_navigation')
  
  -- Close variables popup
  T.cmd("normal! q")
  T.sleep(200)
  
  -- Test debug control keys
  T.TerminalSnapshot('after_variables_closed')
  
  -- Test 'q' key to exit debug mode
  T.cmd("execute \"normal \\q\"")
  T.sleep(300)
  T.TerminalSnapshot('debug_mode_exited')
end)