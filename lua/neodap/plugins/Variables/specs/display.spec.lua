local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.BreakpointVirtualText'))
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
  T.sleep(2000)  -- Give more time for breakpoint to be hit
  
  -- Capture initial state with debugger stopped
  T.TerminalSnapshot('breakpoint_hit')
  
  -- Add a small delay to ensure the frame is properly set
  T.sleep(300)
  
  -- Open Variables window
  T.cmd("NeodapVariablesShow")
  T.sleep(1000)  -- Give more time for Neo-tree to render and load data
  T.TerminalSnapshot('variables_window_open')
  
  -- Navigate to Variables window (it opens on the left)
  T.cmd("wincmd h")
  T.sleep(100)
  T.TerminalSnapshot('variables_focused')
  
  -- Expand Local scope to show variables
  T.cmd("execute \"normal \\<CR>\"")  -- Simulate Enter key
  T.sleep(200)
  T.TerminalSnapshot('local_expanding')
  
  T.sleep(1500)  -- Wait for async data loading
  T.TerminalSnapshot('local_expanded')
  
  -- Navigate to Closure and expand it to see 'i' variable
  T.cmd("normal! jj")  -- Skip 'this' and move to Closure
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(1500)
  T.TerminalSnapshot('closure_expanded')
end)



--[[ TERMINAL SNAPSHOT: breakpoint_hit
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3| ●  ◆console.log("A Loop iteration:", i++);
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



--[[ TERMINAL SNAPSHOT: variables_window_open
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|   Closure                              │setInterval(() => {
 3|   Global                               │●  ◆console.log("A Loop iteration:", i+
 4| ~                                       │+);
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
23| <e variables [1] [RO] 1,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]


--[[ TERMINAL SNAPSHOT: variables_focused
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|   Closure                              │setInterval(() => {
 3|   Global                               │●  ◆console.log("A Loop iteration:", i+
 4| ~                                       │+);
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
23| <e variables [1] [RO] 1,1            All <xtures/loop/loop.js 3,1-2          All
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


--[[ TERMINAL SNAPSHOT: cursor_on_local_scope
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|   Closure                              │setInterval(() => {
 3|   Global                               │●  ◆console.log("A Loop iteration:", i+
 4| ~                                       │+);
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
23| <e variables [1] [RO] 1,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: local_scope_expanded_attempt
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|   Closure                              │setInterval(() => {
 3|   Global                               │●  ◆console.log("A Loop iteration:", i+
 4| ~                                       │+);
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
23| <e variables [1] [RO] 2,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: final_variables_window
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|   Closure                              │setInterval(() => {
 3|   Global                               │●  ◆console.log("A Loop iteration:", i+
 4| ~                                       │+);
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
23| <e variables [1] [RO] 1,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: local_expanded_visual
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|   Closure                              │setInterval(() => {
 3|   Global                               │●  ◆console.log("A Loop iteration:", i+
 4| ~                                       │+);
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
23| <e variables [1] [RO] 1,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]


--[[ TERMINAL SNAPSHOT: local_expanded_with_data
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|    * this: undefined                    │setInterval(() => {
 3|   Closure                              │●  ◆console.log("A Loop iteration:", i+
 4|   Global                               │+);
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
23| <e variables [1] [RO] 1,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: cursor_on_variable_i
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|   Closure                              │setInterval(() => {
 3|   Global                               │●  ◆console.log("A Loop iteration:", i+
 4| ~                                       │+);
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
23| <e variables [1] [RO] 2,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: variable_i_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|   Closure                              │setInterval(() => {
 3|   Global                               │●  ◆console.log("A Loop iteration:", i+
 4| ~                                       │+);
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
23| <e variables [1] [RO] 2,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: final_variables_tree
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|   Closure                              │setInterval(() => {
 3|   Global                               │●  ◆console.log("A Loop iteration:", i+
 4| ~                                       │+);
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
23| <e variables [1] [RO] 2,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: after_enter_key
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|    * this: undefined                    │setInterval(() => {
 3|   Closure                              │●  ◆console.log("A Loop iteration:", i+
 4|   Global                               │+);
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
23| <e variables [1] [RO] 1,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: moved_down
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|    * this: undefined                    │setInterval(() => {
 3|   Closure                              │●  ◆console.log("A Loop iteration:", i+
 4|   Global                               │+);
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
23| <e variables [1] [RO] 2,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: cursor_on_closure
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|    * this: undefined                    │setInterval(() => {
 3|   Closure                              │●  ◆console.log("A Loop iteration:", i+
 4|   Global                               │+);
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
23| <e variables [1] [RO] 3,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: local_expanding
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|    * this: undefined                    │setInterval(() => {
 3|   Closure                              │●  ◆console.log("A Loop iteration:", i+
 4|   Global                               │+);
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
23| <e variables [1] [RO] 1,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: local_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|    * this: undefined                    │setInterval(() => {
 3|   Closure                              │●  ◆console.log("A Loop iteration:", i+
 4|   Global                               │+);
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
23| <e variables [1] [RO] 1,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: closure_expanded
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|    * this: undefined                    │setInterval(() => {
 3|   Closure                              │●  ◆console.log("A Loop iteration:", i+
 4|    * i: 0                               │+);
 5|   Global                               │  console.log("B Loop iteration:", i++)
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
23| <e variables [1] [RO] 3,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]