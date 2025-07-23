-- Minimal test to debug breadcrumb navigation
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.Variables'))

  -- Set up initial state and launch session
  T.cmd("edit lua/testing/fixtures/variables/deep_nested.js")
  T.cmd("NeodapLaunchClosest Deep Nested")

  -- Wait for session to start and hit breakpoint
  T.sleep(2000)

  -- Open Variables window
  T.cmd("VariablesShow")
  T.sleep(300)

  -- Navigate to Variables window
  T.cmd("wincmd h")
  T.TerminalSnapshot('01_normal_mode')

  -- Toggle to breadcrumb mode  
  T.cmd("VariablesBreadcrumb")
  T.sleep(300)
  T.TerminalSnapshot('02_breadcrumb_mode_initial')

  -- NOW TEST: Navigate into Local scope
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500)
  T.TerminalSnapshot('03_after_local_navigation')

  -- Check logs
  T.cmd("messages")
  T.TerminalSnapshot('04_debug_messages')
end)