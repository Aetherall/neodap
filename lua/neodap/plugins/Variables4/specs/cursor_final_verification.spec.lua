local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables4'))

  -- Set up initial state and launch session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j") -- Move to line with variables
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables")
  T.sleep(1500) -- Wait for session and breakpoint hit

  -- Open the variables tree popup
  T.cmd("Variables4Tree")
  T.sleep(300)
  T.TerminalSnapshot('final_initial_cursor_on_local')

  -- Test j navigation (down to Global scope)
  T.cmd("normal! j")
  T.TerminalSnapshot('final_cursor_moved_to_global')

  -- Test k navigation (back up to Local scope)  
  T.cmd("normal! k")
  T.TerminalSnapshot('final_cursor_back_to_local')

  -- Test l navigation (drill down into Local scope)
  T.cmd("normal! l")
  T.sleep(500)
  T.TerminalSnapshot('final_cursor_drilled_into_local')

  -- Test j navigation within drilled scope
  T.cmd("normal! j")
  T.TerminalSnapshot('final_cursor_navigate_within_scope')

  -- Test h navigation (back up to parent)
  T.cmd("normal! h")
  T.sleep(200)
  T.TerminalSnapshot('final_cursor_back_to_parent')

  -- Close popup
  T.cmd("normal! q")
end)


--[[ TERMINAL SNAPSHOT: final_initial_cursor_on_local
Size: 24x80
Cursor: [1, 9] (line 1, col 9)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▶ 📁  Local: testVariables                                       │
 5|     let│▶ 📁  Global                                                     │
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
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               1,10-6        All
]]


--[[ TERMINAL SNAPSHOT: final_cursor_moved_to_global
Size: 24x80
Cursor: [2, 9] (line 2, col 9)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▶ 📁  Local: testVariables                                       │
 5|     let│▶ 📁  Global                                                     │
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
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               2,10-6        All
]]


--[[ TERMINAL SNAPSHOT: final_cursor_back_to_local
Size: 24x80
Cursor: [1, 9] (line 1, col 9)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▶ 📁  Local: testVariables                                       │
 5|     let│▶ 📁  Global                                                     │
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
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               1,10-6        All
]]


--[[ TERMINAL SNAPSHOT: final_cursor_drilled_into_local
Size: 24x80
Cursor: [1, 10] (line 1, col 10)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▶ 📁  Local: testVariables                                       │
 5|     let│▶ 📁  Global                                                     │
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
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               1,11-7        All
]]


--[[ TERMINAL SNAPSHOT: final_cursor_navigate_within_scope
Size: 24x80
Cursor: [2, 10] (line 2, col 10)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▶ 📁  Local: testVariables                                       │
 5|     let│▶ 📁  Global                                                     │
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
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               2,11-7        All
]]


--[[ TERMINAL SNAPSHOT: final_cursor_back_to_parent
Size: 24x80
Cursor: [2, 9] (line 2, col 9)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▶ 📁  Local: testVariables                                       │
 5|     let│▶ 📁  Global                                                     │
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
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               2,10-6        All
]]