local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- First, ensure the necessary plugins are loaded
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.BreakpointVirtualText'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))

  -- Second, open the fixture
  T.cmd("edit lua/testing/fixtures/loop/loop.js")

  -- Then, proceed with the test

  T.cmd("normal! 2j") -- Move cursor to line 3

  T.TerminalSnapshot('before')

  T.cmd("NeodapToggleBreakpoint")

  T.TerminalSnapshot('toggled_on')

  T.cmd("NeodapToggleBreakpoint")

  T.TerminalSnapshot('toggled_off')
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
24| Too many rounds of missing plugins
]]

--[[ TERMINAL SNAPSHOT: toggled_on
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3| ●  console.log("A Loop iteration:", i++);
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
23| lua/testing/fixtures/loop/loop.js                             3,1-2          All
24|
]]

--[[ TERMINAL SNAPSHOT: toggled_off
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
