local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  local variables4_plugin = api:getPluginInstance(require('neodap.plugins.Variables4'))
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))

  -- Set up initial state and launch session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j") -- Move to line with variables (line 7)
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]") -- Exact config name
  T.sleep(1500) -- Wait for session and breakpoint hit

  -- Open the variables tree popup
  T.cmd("Variables4Tree")
  T.sleep(500)
  T.TerminalSnapshot('duplication_tree_opened')

  -- Expand Local scope using correct NUI interaction
  T.cmd("execute \"normal \\<CR>\"") -- This is the correct way for NUI
  T.sleep(400)
  T.TerminalSnapshot('duplication_local_scope_expanded')

  -- Navigate to objectVar (usually a complex object that can cause duplication)
  T.cmd("normal! j") -- Move down through variables
  T.cmd("normal! j")
  T.cmd("normal! j")
  T.cmd("normal! j")
  T.cmd("normal! j") -- Should be on objectVar
  T.TerminalSnapshot('duplication_on_object_var')

  -- Expand objectVar (complex object expansion - prime candidate for duplication)
  T.cmd("execute \"normal \\<CR>\"") -- Expand objectVar
  T.sleep(500)
  T.TerminalSnapshot('duplication_object_expanded')

  -- This is the critical test: collapse and expand again to check for duplication
  T.cmd("execute \"normal \\<CR>\"") -- Collapse objectVar
  T.sleep(200)
  T.TerminalSnapshot('duplication_object_collapsed')
  
  T.cmd("execute \"normal \\<CR>\"") -- Expand objectVar again
  T.sleep(500)
  T.TerminalSnapshot('duplication_object_expanded_again')

  -- Navigate into the expanded object to check for duplicate children
  T.cmd("normal! j") -- Move to first child
  T.TerminalSnapshot('duplication_inside_object_first_child')
  
  T.cmd("normal! j") -- Move to second child
  T.TerminalSnapshot('duplication_inside_object_second_child')
  
  T.cmd("normal! j") -- Move to third child
  T.TerminalSnapshot('duplication_inside_object_third_child')

  -- Try expanding a nested object if available
  T.cmd("execute \"normal \\<CR>\"") -- Try to expand current child
  T.sleep(400)
  T.TerminalSnapshot('duplication_nested_expanded')

  -- Test with array expansion too (another common duplication source)
  T.cmd("normal! k") -- Go back up
  T.cmd("normal! k")
  T.cmd("normal! k")
  T.cmd("normal! k") -- Navigate to arrayVar
  T.TerminalSnapshot('duplication_on_array_var')
  
  T.cmd("execute \"normal \\<CR>\"") -- Expand arrayVar
  T.sleep(400)
  T.TerminalSnapshot('duplication_array_expanded')
  
  -- Collapse and expand array to check for duplication
  T.cmd("execute \"normal \\<CR>\"") -- Collapse
  T.sleep(200)
  T.cmd("execute \"normal \\<CR>\"") -- Expand again
  T.sleep(400)
  T.TerminalSnapshot('duplication_array_expanded_again')

  -- Close popup
  T.cmd("normal! q")
end)

--[[ TERMINAL SNAPSHOT: duplication_tree_opened
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

--[[ TERMINAL SNAPSHOT: duplication_local_scope_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: duplication_on_object_var
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: duplication_object_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: duplication_object_collapsed
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: duplication_object_expanded_again
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: duplication_inside_object_first_child
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: duplication_inside_object_second_child
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: duplication_inside_object_third_child
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: duplication_nested_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: duplication_on_array_var
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
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
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: duplication_array_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: duplication_array_expanded_again
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]