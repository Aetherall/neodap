local T = require("testing.testing")(describe, it)

-- T.Scenario(function(api)
--   api:getPluginInstance(require('neodap.plugins.NuiVariableTree'))

--   T.cmd("NuiVariableTreeShow")
--   T.sleep(300) -- Let UI render
--   T.TerminalSnapshot('shows_empty_window')

--   T.cmd("NuiVariableTreeHide")
--   T.TerminalSnapshot('hides_window')
-- end)

T.Scenario(function(api)

  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.NuiVariableTree'))

  T.cmd("edit lua/testing/fixtures/loop/loop.js")
  T.cmd("NeodapLaunchClosest Loop [loop]")
  T.sleep(3000) -- Increased sleep for debugger to initialize and session to register
  T.cmd("normal! 2j") -- Move to line 3
  T.cmd("NeodapToggleBreakpoint")
  T.sleep(2000)       -- Wait for breakpoint to be set and hit
  vim.cmd("buffer #") -- Switch back to the test buffer
  T.TerminalSnapshot('before_variable_tree_show')

  T.cmd("NuiVariableTreeShow")
  T.sleep(3000) -- Increased sleep for UI to update with variables
  T.TerminalSnapshot('shows_variables')
end)



--[[ TERMINAL SNAPSHOT: before_variable_tree_show
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|   console.log("A Loop iteration:", i++);
 4|   console.log("B Loop iteration:", i++);
 5|   console.log("C Loop iteration:", i++);
 6|   console.log("D Loop iteration:", i++);
 7| }, 1000);
 8| ~
 9| ~
10| ~
11| ~
12| ~
13| ~
14| ~
15| ~
16| ~
17| ~
18| ~
19| ~
20| ~
21| ~
22| ~
23| lua/testing/fixtures/loop/loop.js                             3,1            All
24|
]]



--[[ TERMINAL SNAPSHOT: shows_variables
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| 
 2| 
 3| 
 4| 
 5| 
 6| 
 7| 
 8| 
 9| 
10| 
11| 
12| 
13| 
14| 
15| 
16| 
17| 
18| 
19| 
20| 
21| 
22| 
23| 
24| 
]]