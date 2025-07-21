local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables'))
  
  -- Set up neo-tree with the Variables source
  local neotree = require('neo-tree')
  neotree.setup({
    sources = {
      "neodap.plugins.Variables",
    }
  })
  
  -- Use the simpler loop fixture that works reliably
  T.cmd("edit lua/testing/fixtures/loop/loop.js")
  
  -- Move to line 3 where we'll set a breakpoint
  T.cmd("normal! 2j")  -- Move to line 3
  
  -- Launch with the Loop config
  T.cmd("NeodapLaunchClosest Loop [loop]")
  
  -- Set a breakpoint and wait for it to hit
  T.cmd("NeodapToggleBreakpoint")
  T.sleep(1500)  -- Wait for breakpoint to be hit
  
  -- Capture initial state with debugger stopped
  T.TerminalSnapshot('breakpoint_hit')
  
  -- Open Variables window
  T.cmd("NeodapVariablesShow")
  T.sleep(500)  -- Let Neo-tree render
  T.TerminalSnapshot('variables_window_open')
  
  -- Navigate to Variables window (it opens on the left)
  T.cmd("wincmd h")
  T.sleep(100)
  T.TerminalSnapshot('variables_focused')
  
  -- Just capture the final state with Variables window open showing scopes
  -- This is sufficient to verify the Variables plugin is working
  T.TerminalSnapshot('variables_showing_scopes')
end)


--[[ TERMINAL SNAPSHOT: breakpoint_hit
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

--[[ TERMINAL SNAPSHOT: variables_window_open
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|   Closure                              │setInterval(() => {
 3|   Global                               │  console.log("A Loop iteration:", i++)
 4| ~                                       │;
 5| ~                                       │  console.log("B Loop iteration:", i++)
 6| ~                                       │;
 7| ~                                       │  console.log("C Loop iteration:", i++)
 8| ~                                       │;
 9| ~                                       │  console.log("D Loop iteration:", i++)
10| ~                                       │;
11| ~                                       │}, 1000);
12| ~                                       │~
13| ~                                       │~
14| ~                                       │~
15| ~                                       │~
16| ~                                       │~
17| ~                                       │~
18| ~                                       │~
19| ~                                       │~
20| ~                                       │~
21| ~                                       │~
22| ~                                       │~
23| <e variables [1] [RO] 1,1            All <xtures/loop/loop.js 3,1            All
24| 
]]

--[[ TERMINAL SNAPSHOT: variables_focused
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|   Closure                              │setInterval(() => {
 3|   Global                               │  console.log("A Loop iteration:", i++)
 4| ~                                       │;
 5| ~                                       │  console.log("B Loop iteration:", i++)
 6| ~                                       │;
 7| ~                                       │  console.log("C Loop iteration:", i++)
 8| ~                                       │;
 9| ~                                       │  console.log("D Loop iteration:", i++)
10| ~                                       │;
11| ~                                       │}, 1000);
12| ~                                       │~
13| ~                                       │~
14| ~                                       │~
15| ~                                       │~
16| ~                                       │~
17| ~                                       │~
18| ~                                       │~
19| ~                                       │~
20| ~                                       │~
21| ~                                       │~
22| ~                                       │~
23| <e variables [1] [RO] 1,1            All <xtures/loop/loop.js 3,1            All
24| 
]]

--[[ TERMINAL SNAPSHOT: variables_showing_scopes
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|   Closure                              │setInterval(() => {
 3|   Global                               │  console.log("A Loop iteration:", i++)
 4| ~                                       │;
 5| ~                                       │  console.log("B Loop iteration:", i++)
 6| ~                                       │;
 7| ~                                       │  console.log("C Loop iteration:", i++)
 8| ~                                       │;
 9| ~                                       │  console.log("D Loop iteration:", i++)
10| ~                                       │;
11| ~                                       │}, 1000);
12| ~                                       │~
13| ~                                       │~
14| ~                                       │~
15| ~                                       │~
16| ~                                       │~
17| ~                                       │~
18| ~                                       │~
19| ~                                       │~
20| ~                                       │~
21| ~                                       │~
22| ~                                       │~
23| <e variables [1] [RO] 1,1            All <xtures/loop/loop.js 3,1            All
24| 
]]