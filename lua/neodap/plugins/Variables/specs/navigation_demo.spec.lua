-- Simple navigation demonstration test
-- Shows that breadcrumb navigation properly filters tree content

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
  
  -- Show normal tree with all scopes
  T.TerminalSnapshot('01_normal_mode_all_scopes')

  -- Switch to breadcrumb mode - should still show all scopes
  T.cmd("VariablesBreadcrumb")
  T.sleep(300)
  T.TerminalSnapshot('02_breadcrumb_root_shows_scopes')

  -- Navigate into Local scope - should only show Local variables
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500)
  T.TerminalSnapshot('03_breadcrumb_local_only')

  -- Navigate into complexObject - should only show object properties
  T.cmd("/complexObject")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500)  
  T.TerminalSnapshot('04_breadcrumb_object_properties_only')

  -- Go back to root - should show all scopes again
  T.cmd("normal! r")
  T.sleep(400)
  T.TerminalSnapshot('05_breadcrumb_root_again')

  -- Return to normal mode - should show expandable tree
  T.cmd("normal! B")
  T.sleep(300)
  T.TerminalSnapshot('06_normal_mode_restored')
end)