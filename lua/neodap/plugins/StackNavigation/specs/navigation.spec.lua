local T = require("testing.testing")(describe, it)
local CommonSetups = require("testing.common_setups")

T.Scenario(function(api)
  -- Load standard plugins + StackNavigation specific plugins
  local plugins = CommonSetups.loadStandardPlugins(api)
  api:getPluginInstance(require('neodap.plugins.FrameHighlight'))
  api:getPluginInstance(require('neodap.plugins.StackNavigation'))

  -- Set up debugging with stack fixture
  T.cmd("edit lua/testing/fixtures/stack/deep.js")
  T.cmd("NeodapLaunchClosest Stack [stack]")
  T.sleep(1500) -- Wait for session and breakpoint hit

  -- Capture the initial state (should be stopped at debugger statement in functionFour)
  T.TerminalSnapshot('initial_state')

  -- Test navigating up the stack
  T.cmd("NeodapStackNavigationUp")
  T.TerminalSnapshot('after_up')
  T.cmd("NeodapStackNavigationDown")
  T.TerminalSnapshot('after_down')
  T.cmd("NeodapStackNavigationTop")
  T.TerminalSnapshot('after_top')
  T.cmd("NeodapStackNavigationUp")
  T.cmd("NeodapStackNavigationUp")
  T.TerminalSnapshot('after_multiple_up')
end)


