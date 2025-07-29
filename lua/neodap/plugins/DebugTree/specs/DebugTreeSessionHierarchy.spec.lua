-- Test session hierarchy - Session 2 should appear as child of Session 1
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Use any fixture that triggers debugging
  T.cmd("edit lua/testing/fixtures/loop/loop.js")
  T.cmd("normal! 2j") -- Go to line 3
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Loop [loop]")
  T.sleep(2000) -- Wait for sessions to start
  
  -- Open DebugTree to see session hierarchy
  T.cmd("DebugTree")
  T.sleep(500)
  T.TerminalSnapshot('01_session_hierarchy_initial')
  
  -- Expand Session 1 to see child session
  T.cmd("normal! j") -- Move to Session 1
  T.cmd("execute \"normal \\<CR>\"") -- Expand
  T.sleep(300)
  T.TerminalSnapshot('02_session1_expanded_shows_child')
  
  -- Navigate to child session
  T.cmd("normal! j") -- Move to child session
  T.TerminalSnapshot('03_child_session_selected')
  
  -- Expand child session to see its threads
  T.cmd("execute \"normal \\<CR>\"") -- Expand
  T.sleep(300)
  T.TerminalSnapshot('04_child_session_expanded')
  
  -- Clean up
  T.cmd("normal! q")
  T.sleep(200)
end)


--[[ TERMINAL SNAPSHOT: 01_session_hierarchy_initial
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|   conso╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|   conso│▶ 📡  Session 1                                                  │
 5|   conso│▶ 📡  Session 2                                                  │
 6|   conso│                                                                │
 7| }, 1000│                                                                │
 8| ~      │                                                                │
 9| ~      │                                                                │
10| ~      │                                                                │
11| ~      │                                                                │
12| ~      │                                                                │
13| ~      │                                                                │
14| ~      │                                                                │
15| ~      │                                                                │
16| ~      │                                                                │
17| ~      │                                                                │
18| ~      │                                                                │
19| ~      ╰────────────────────────────────────────────────────────────────╯
20| ~
21| ~
22| ~
23| lua/testing/fixtures/loop/loop.js                             3,1            All
24|                                                               1,1           All
]]


--[[ TERMINAL SNAPSHOT: 02_session1_expanded_shows_child
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|   conso╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|   conso│▶ 📡  Session 1                                                  │
 5|   conso│▼ 📡  Session 2                                                  │
 6|   conso│                                                                │
 7| }, 1000│                                                                │
 8| ~      │                                                                │
 9| ~      │                                                                │
10| ~      │                                                                │
11| ~      │                                                                │
12| ~      │                                                                │
13| ~      │                                                                │
14| ~      │                                                                │
15| ~      │                                                                │
16| ~      │                                                                │
17| ~      │                                                                │
18| ~      │                                                                │
19| ~      ╰────────────────────────────────────────────────────────────────╯
20| ~
21| ~
22| ~
23| lua/testing/fixtures/loop/loop.js                             3,1            All
24|                                                               2,1           All
]]


--[[ TERMINAL SNAPSHOT: 03_child_session_selected
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|   conso╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|   conso│▶ 📡  Session 1                                                  │
 5|   conso│▼ 📡  Session 2                                                  │
 6|   conso│                                                                │
 7| }, 1000│                                                                │
 8| ~      │                                                                │
 9| ~      │                                                                │
10| ~      │                                                                │
11| ~      │                                                                │
12| ~      │                                                                │
13| ~      │                                                                │
14| ~      │                                                                │
15| ~      │                                                                │
16| ~      │                                                                │
17| ~      │                                                                │
18| ~      │                                                                │
19| ~      ╰────────────────────────────────────────────────────────────────╯
20| ~
21| ~
22| ~
23| lua/testing/fixtures/loop/loop.js                             3,1            All
24|                                                               2,1           All
]]


--[[ TERMINAL SNAPSHOT: 04_child_session_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|   conso╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|   conso│▶ 📡  Session 1                                                  │
 5|   conso│▶ 📡  Session 2                                                  │
 6|   conso│                                                                │
 7| }, 1000│                                                                │
 8| ~      │                                                                │
 9| ~      │                                                                │
10| ~      │                                                                │
11| ~      │                                                                │
12| ~      │                                                                │
13| ~      │                                                                │
14| ~      │                                                                │
15| ~      │                                                                │
16| ~      │                                                                │
17| ~      │                                                                │
18| ~      │                                                                │
19| ~      ╰────────────────────────────────────────────────────────────────╯
20| ~
21| ~
22| ~
23| lua/testing/fixtures/loop/loop.js                             3,1            All
24|                                                               2,1           All
]]