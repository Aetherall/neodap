local T = require("testing.testing")(describe, it)
local CommonSetups = require("testing.common_setups")

T.Scenario(function(api)
  -- Load standard plugins + BreakpointVirtualText
  local plugins = CommonSetups.loadStandardPlugins(api)
  api:getPluginInstance(require('neodap.plugins.BreakpointVirtualText'))

  T.cmd("edit lua/testing/fixtures/loop/loop.js")
  T.cmd("NeodapLaunchClosest Loop [loop]")
  T.cmd("normal! 2j") -- Move cursor to line 3
  T.TerminalSnapshot('before')
  
  T.cmd("NeodapToggleBreakpoint")
  T.sleep(1100) -- Wait for hit

  T.TerminalSnapshot('hit')
end)




--[[ TERMINAL SNAPSHOT: before
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
24| [Plugin:BreakpointApi] New session started: 1
]]

--[[ TERMINAL SNAPSHOT: hit
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