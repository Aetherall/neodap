-- Test to verify path-based IDs are working correctly
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))

  -- Open test file and set breakpoint
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 9j") -- Move to line 10
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500) -- Wait for debugger to hit breakpoint
  
  -- Open debug tree
  T.cmd("DebugTree")
  T.sleep(300)
  T.TerminalSnapshot('tree_opened')
  
  -- Navigate down the tree to see path-based IDs
  T.cmd("normal! l") -- Into session
  T.sleep(100)
  T.cmd("normal! l") -- Into thread
  T.sleep(100)
  T.cmd("normal! l") -- Into stack
  T.sleep(100) 
  T.cmd("normal! l") -- Into frame (should load scopes)
  T.sleep(200)
  T.TerminalSnapshot('scopes_visible')
  
  -- Check a node's debug info to see the path-based ID
  T.cmd("normal! !") -- Show debug info for current frame
  T.sleep(200)
  T.TerminalSnapshot('frame_debug_info')
  T.cmd("normal! q") -- Close debug popup
  
  -- Navigate to a scope
  T.cmd("normal! j") -- Move to first scope
  T.cmd("normal! !") -- Show debug info
  T.sleep(200)
  T.TerminalSnapshot('scope_debug_info')
  T.cmd("normal! q") -- Close debug popup
  
  -- Expand scope to see variables
  T.cmd("normal! l") -- Expand scope
  T.sleep(200)
  T.cmd("normal! j") -- Move to a variable
  T.cmd("normal! !") -- Show debug info
  T.sleep(200)
  T.TerminalSnapshot('variable_debug_info')
end)

--[[ TERMINAL SNAPSHOT: tree_opened
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▶ 📡  Session 2                                                  │
 6|     let│                                                                │
 7|     let│                                                                │
 8|     let│                                                                │
 9|     let│                                                                │
10|     let│                                                                │lue";
11|     let│                                                                │e trunc
12| ated wh│                                                                │
13|        │                                                                │
14|     // │                                                                │
15|     let│                                                                │
16|     let│                                                                │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     10,1           Top
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: scopes_visible
Size: 24x80
Cursor: [1, 9] (line 1, col 9)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▶ 📡  Session 2                                                  │
 6|     let│                                                                │
 7|     let│                                                                │
 8|     let│                                                                │
 9|     let│                                                                │
10|     let│                                                                │lue";
11|     let│                                                                │e trunc
12| ated wh│                                                                │
13|        │                                                                │
14|     // │                                                                │
15|     let│                                                                │
16|     let│                                                                │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     10,1           Top
24|                                                               1,10-6        All
]]

--[[ TERMINAL SNAPSHOT: frame_debug_info
Size: 24x80
Cursor: [1, 9] (line 1, col 9)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▶ 📡  Session 2                                                  │
 6|     let│                                                                │
 7|     let│                                                                │
 8|     let│                                                                │
 9|     let│                                                                │
10|     let│                                                                │lue";
11|     let│                                                                │e trunc
12| ated wh│                                                                │
13|        │                                                                │
14|     // │                                                                │
15|     let│                                                                │
16|     let│                                                                │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     10,1           Top
24|                                                               1,10-6        All
]]

--[[ TERMINAL SNAPSHOT: scope_debug_info
Size: 24x80
Cursor: [2, 9] (line 2, col 9)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▶ 📡  Session 2                                                  │
 6|     let│                                                                │
 7|     let│                                                                │
 8|     let│                                                                │
 9|     let│                                                                │
10|     let│                                                                │lue";
11|     let│                                                                │e trunc
12| ated wh│                                                                │
13|        │                                                                │
14|     // │                                                                │
15|     let│                                                                │
16|     let│                                                                │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     10,1           Top
24|                                                               2,10-6        All
]]

--[[ TERMINAL SNAPSHOT: variable_debug_info
Size: 24x80
Cursor: [2, 10] (line 2, col 10)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▶ 📡  Session 2                                                  │
 6|     let│                                                                │
 7|     let│                                                                │
 8|     let│                                                                │
 9|     let│                                                                │
10|     let│                                                                │lue";
11|     let│                                                                │e trunc
12| ated wh│                                                                │
13|        │                                                                │
14|     // │                                                                │
15|     let│                                                                │
16|     let│                                                                │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     10,1           Top
24|                                                               2,11-7        All
]]