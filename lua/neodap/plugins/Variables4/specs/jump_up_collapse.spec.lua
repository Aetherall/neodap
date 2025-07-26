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
  T.TerminalSnapshot('jump_up_initial_tree')

  -- Test 1: Build a Deep Hierarchy for Jump-up Testing
  -- Create multiple levels of expansion to test jump-up behavior
  T.cmd("normal! l") -- Expand Local scope
  T.sleep(500)
  T.cmd("normal! l") -- Drill into first variable
  T.sleep(300)
  T.cmd("normal! l") -- Drill deeper if possible
  T.sleep(300)
  T.cmd("normal! l") -- Drill even deeper
  T.sleep(300)
  T.TerminalSnapshot('jump_up_deep_hierarchy_built')

  -- Test 2: Single H-key Jump-up with Collapse
  -- The ENHANCED behavior: h-key should jump to parent AND collapse children
  T.cmd("normal! h") -- Should jump to parent while collapsing current + children
  T.sleep(300)
  T.TerminalSnapshot('jump_up_first_jump_with_collapse')

  -- Test 3: Multiple Jump-ups in Sequence
  -- Each h-key should continue jumping up while maintaining clean collapsed state
  T.cmd("normal! h") -- Second jump up
  T.sleep(300)
  T.TerminalSnapshot('jump_up_second_jump_with_collapse')

  T.cmd("normal! h") -- Third jump up
  T.sleep(300)
  T.TerminalSnapshot('jump_up_third_jump_with_collapse')

  T.cmd("normal! h") -- Fourth jump up (should reach scope level)
  T.sleep(300)
  T.TerminalSnapshot('jump_up_reached_scope_level')

  -- Test 4: Jump-up vs Traditional Behavior Comparison
  -- Build hierarchy again to test the difference
  T.cmd("normal! l") -- Expand scope
  T.sleep(500)
  T.cmd("normal! l") -- Drill into variable
  T.sleep(300)
  T.cmd("normal! l") -- Drill deeper
  T.sleep(300)
  T.TerminalSnapshot('jump_up_hierarchy_rebuilt')

  -- Now test that h-key jumps immediately instead of just collapsing
  T.cmd("normal! h") -- Should JUMP to parent while collapsing (not just collapse)
  T.sleep(300)
  T.TerminalSnapshot('jump_up_immediate_jump_not_just_collapse')

  -- Test 5: Jump-up in Focus Mode
  -- Test the enhanced behavior works in focus mode too
  T.cmd("normal! l") -- Drill down for focus test
  T.sleep(300)
  T.cmd("normal! l") -- Drill deeper
  T.sleep(300)
  T.cmd("normal! f") -- Enable focus mode
  T.sleep(200)
  T.TerminalSnapshot('jump_up_focus_mode_setup')

  -- Test jump-up behavior in focus mode
  T.cmd("normal! h") -- Should jump up while collapsing in focus mode
  T.sleep(300)
  T.TerminalSnapshot('jump_up_focus_mode_jump_with_collapse')

  T.cmd("normal! h") -- Continue jumping up in focus mode
  T.sleep(300)
  T.TerminalSnapshot('jump_up_focus_mode_hierarchical_expansion')

  -- Test 6: Global Scope Jump-up Behavior
  -- Test that enhanced behavior works consistently across scopes
  T.cmd("normal! f") -- Exit focus mode
  T.sleep(200)
  T.cmd("normal! j") -- Move to Global scope
  T.cmd("normal! l") -- Expand Global scope
  T.sleep(500)
  T.cmd("normal! l") -- Drill into global variable
  T.sleep(300)
  T.cmd("normal! l") -- Drill deeper
  T.sleep(300)
  T.TerminalSnapshot('jump_up_global_hierarchy_built')

  -- Test jump-up from global variables
  T.cmd("normal! h") -- Jump up while collapsing in global scope
  T.sleep(300)
  T.TerminalSnapshot('jump_up_global_first_jump')

  T.cmd("normal! h") -- Continue jumping up
  T.sleep(300)
  T.TerminalSnapshot('jump_up_global_second_jump')

  T.cmd("normal! h") -- Jump to global scope level
  T.sleep(300)
  T.TerminalSnapshot('jump_up_global_scope_level')

  -- Test 7: Rapid Jump-up Sequence
  -- Test that multiple rapid h-key presses work smoothly
  T.cmd("normal! l") -- Build hierarchy for rapid test
  T.sleep(300)
  T.cmd("normal! l")
  T.sleep(300)
  T.cmd("normal! l")
  T.sleep(300)
  T.TerminalSnapshot('jump_up_rapid_test_setup')

  -- Rapid h-key sequence
  T.cmd("normal! h") -- Rapid jump 1
  T.cmd("normal! h") -- Rapid jump 2
  T.cmd("normal! h") -- Rapid jump 3
  T.sleep(300) -- Wait for all changes to settle
  T.TerminalSnapshot('jump_up_rapid_sequence_complete')

  -- Test 8: Edge Case - Non-expandable Node Jump-up
  -- Test jump-up behavior from leaf nodes
  T.cmd("normal! l") -- Expand to get to variables
  T.sleep(300)
  T.cmd("normal! j") -- Move to a variable
  T.cmd("normal! j") -- Move to potentially non-expandable variable
  T.TerminalSnapshot('jump_up_leaf_node_setup')

  T.cmd("normal! h") -- Jump up from leaf node
  T.sleep(300)
  T.TerminalSnapshot('jump_up_from_leaf_node')

  -- Test 9: Round-trip with Enhanced Jump-up
  -- Test that l/h navigation with enhanced jump-up is smooth
  T.cmd("normal! l") -- Drill down
  T.sleep(300)
  T.cmd("normal! l") -- Drill deeper
  T.sleep(300)
  T.cmd("normal! h") -- Enhanced jump up
  T.sleep(300)
  T.cmd("normal! l") -- Drill back down
  T.sleep(300)
  T.cmd("normal! h") -- Enhanced jump up again
  T.sleep(300)
  T.TerminalSnapshot('jump_up_round_trip_navigation')

  -- Show help to document the enhanced behavior
  T.cmd("normal! ?")
  T.TerminalSnapshot('jump_up_enhanced_help_text')

  -- Close popup
  T.cmd("normal! q")
  T.TerminalSnapshot('jump_up_test_complete')
end)

--[[ TERMINAL SNAPSHOT: jump_up_initial_tree
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

--[[ TERMINAL SNAPSHOT: jump_up_deep_hierarchy_built
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

--[[ TERMINAL SNAPSHOT: jump_up_first_jump_with_collapse
Size: 24x80
Cursor: [1, 8] (line 1, col 8)
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
24|                                                               1,9-5         All
]]

--[[ TERMINAL SNAPSHOT: jump_up_second_jump_with_collapse
Size: 24x80
Cursor: [1, 4] (line 1, col 4)
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
24|                                                               1,5-3         All
]]

--[[ TERMINAL SNAPSHOT: jump_up_third_jump_with_collapse
Size: 24x80
Cursor: [1, 3] (line 1, col 3)
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
24|                                                               1,4-2         All
]]

--[[ TERMINAL SNAPSHOT: jump_up_reached_scope_level
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

--[[ TERMINAL SNAPSHOT: jump_up_hierarchy_rebuilt
Size: 24x80
Cursor: [1, 8] (line 1, col 8)
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
24|                                                               1,9-5         All
]]

--[[ TERMINAL SNAPSHOT: jump_up_immediate_jump_not_just_collapse
Size: 24x80
Cursor: [1, 4] (line 1, col 4)
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
24|                                                               1,5-3         All
]]

--[[ TERMINAL SNAPSHOT: jump_up_focus_mode_setup
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

--[[ TERMINAL SNAPSHOT: jump_up_focus_mode_jump_with_collapse
Size: 24x80
Cursor: [1, 8] (line 1, col 8)
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
24|                                                               1,9-5         All
]]

--[[ TERMINAL SNAPSHOT: jump_up_focus_mode_hierarchical_expansion
Size: 24x80
Cursor: [1, 4] (line 1, col 4)
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
24|                                                               1,5-3         All
]]

--[[ TERMINAL SNAPSHOT: jump_up_global_hierarchy_built
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

--[[ TERMINAL SNAPSHOT: jump_up_global_first_jump
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

--[[ TERMINAL SNAPSHOT: jump_up_global_second_jump
Size: 24x80
Cursor: [2, 8] (line 2, col 8)
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
24|                                                               2,9-5         All
]]

--[[ TERMINAL SNAPSHOT: jump_up_global_scope_level
Size: 24x80
Cursor: [2, 4] (line 2, col 4)
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
24|                                                               2,5-3         All
]]

--[[ TERMINAL SNAPSHOT: jump_up_rapid_test_setup
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