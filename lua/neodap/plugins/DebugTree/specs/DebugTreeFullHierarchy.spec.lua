-- DebugTree Plugin Full Hierarchy Test
-- Shows complete DAP hierarchy: Session → Thread → Stack → Frame → Scope → Variables

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load all required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables4'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Set up debugging session with breakpoint
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j") -- Go to line 7 (booleanVar = true)
  T.cmd("NeodapToggleBreakpoint")
  T.TerminalSnapshot('setup_breakpoint')
  
  -- Launch debugging session
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(2000) -- Wait for session to start and hit breakpoint
  
  -- PHASE 1: Start with session-level view
  T.cmd("DebugTree")
  T.sleep(500)
  T.TerminalSnapshot('01_session_level_root')
  
  -- PHASE 2: Expand session to show threads
  T.cmd("execute \"normal \\<CR>\"") -- Expand session
  T.sleep(500)
  T.TerminalSnapshot('02_session_expanded_threads')
  
  -- PHASE 3: Navigate to and expand first thread
  T.cmd("normal! j") -- Move to thread
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread
  T.sleep(500)
  T.TerminalSnapshot('03_thread_expanded_stack')
  
  -- PHASE 4: Navigate to and expand stack
  T.cmd("normal! j") -- Move to stack
  T.cmd("execute \"normal \\<CR>\"") -- Expand stack
  T.sleep(500)
  T.TerminalSnapshot('04_stack_expanded_frames')
  
  -- PHASE 5: Navigate to and expand frame
  T.cmd("normal! j") -- Move to frame
  T.cmd("execute \"normal \\<CR>\"") -- Expand frame
  T.sleep(500)
  T.TerminalSnapshot('05_frame_expanded_scopes')
  
  -- PHASE 6: Navigate to and expand first scope (Local)
  T.cmd("normal! j") -- Move to Local scope
  T.cmd("execute \"normal \\<CR>\"") -- Expand scope
  T.sleep(800) -- Extra time for variable loading
  T.TerminalSnapshot('06_scope_expanded_variables')
  
  -- PHASE 7: Navigate to and expand a complex variable
  T.cmd("normal! j") -- Move to first variable
  T.cmd("normal! j") -- Move to next variable (might be arrayVar)
  T.cmd("execute \"normal \\<CR>\"") -- Expand variable if it's expandable
  T.sleep(500)
  T.TerminalSnapshot('07_variable_expanded_children')
  
  -- PHASE 8: Navigate deeper into nested variable
  T.cmd("normal! j") -- Move to child variable
  T.cmd("execute \"normal \\<CR>\"") -- Try to expand if possible
  T.sleep(500)
  T.TerminalSnapshot('08_deep_variable_nesting')
  
  -- PHASE 9: Use focus mode to see clean hierarchy
  T.cmd("normal! f") -- Focus mode
  T.sleep(300)
  T.TerminalSnapshot('09_focus_mode_clean_view')
  
  -- PHASE 10: Navigate back up the tree
  T.cmd("normal! h") -- Collapse current
  T.cmd("normal! k") -- Move up
  T.cmd("normal! h") -- Collapse parent
  T.sleep(300)
  T.TerminalSnapshot('10_collapsed_navigation')
  
  -- PHASE 11: Show full tree with all levels expanded
  T.cmd("normal! q") -- Close current tree
  T.sleep(200)
  
  -- Open with maximum expansion
  T.cmd("DebugTree")
  T.sleep(500)
  
  -- Expand everything step by step for full hierarchy
  T.cmd("execute \"normal \\<CR>\"") -- Expand session
  T.sleep(200)
  T.cmd("normal! j") -- Move to thread
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread
  T.sleep(200)
  T.cmd("normal! j") -- Move to stack
  T.cmd("execute \"normal \\<CR>\"") -- Expand stack
  T.sleep(200)
  T.cmd("normal! j") -- Move to frame
  T.cmd("execute \"normal \\<CR>\"") -- Expand frame
  T.sleep(200)
  T.cmd("normal! j") -- Move to scope
  T.cmd("execute \"normal \\<CR>\"") -- Expand scope
  T.sleep(800) -- Wait for variables
  T.TerminalSnapshot('11_complete_hierarchy_expanded')
  
  -- PHASE 12: Demonstrate help system
  T.cmd("normal! ?")
  T.sleep(200)
  T.TerminalSnapshot('12_help_system_full_tree')
  
  -- PHASE 13: Compare with dedicated frame-level tree
  T.cmd("normal! q") -- Close help
  T.cmd("normal! q") -- Close main tree
  T.sleep(200)
  
  T.cmd("DebugTreeFrame") -- Open frame-specific tree
  T.sleep(500)
  T.TerminalSnapshot('13_frame_specific_tree')
  
  -- PHASE 14: Compare with Variables4 (should be identical)
  T.cmd("normal! q")
  T.sleep(200)
  
  T.cmd("Variables4Tree")
  T.sleep(500)
  T.TerminalSnapshot('14_variables4_comparison')
  
  -- PHASE 15: Final cleanup
  T.cmd("normal! q")
  T.sleep(200)
  T.TerminalSnapshot('15_cleanup_complete')
end)

--[[ TERMINAL SNAPSHOT: setup_breakpoint
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| function testVariables() {
 4|     // Primitive types
 5|     let numberVar = 42;
 6|     let stringVar = "Hello, Debug!";
 7|     let booleanVar = true;
 8|     let nullVar = null;
 9|     let undefinedVar = undefined;
10|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
11|     let longStringValue = "This is a very long string value that should be trunc
12| ated when displayed in the tree view to prevent line wrapping";
13| 
14|     // Complex types
15|     let arrayVar = [1, 2, 3, "four", { five: 5 }];
16|     let objectVar = {
17|         name: "Test Object",
18|         count: 100,
19|         nested: {
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: 01_session_level_root
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│                                                                │
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

--[[ TERMINAL SNAPSHOT: 02_session_expanded_threads
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│                                                                │
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

--[[ TERMINAL SNAPSHOT: 03_thread_expanded_stack
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│                                                                │
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

--[[ TERMINAL SNAPSHOT: 04_stack_expanded_frames
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│                                                                │
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

--[[ TERMINAL SNAPSHOT: 05_frame_expanded_scopes
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│                                                                │
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

--[[ TERMINAL SNAPSHOT: 06_scope_expanded_variables
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│                                                                │
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

--[[ TERMINAL SNAPSHOT: 07_variable_expanded_children
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│                                                                │
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

--[[ TERMINAL SNAPSHOT: 08_deep_variable_nesting
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│                                                                │
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

--[[ TERMINAL SNAPSHOT: 09_focus_mode_clean_view
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│                                                                │
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

--[[ TERMINAL SNAPSHOT: 10_collapsed_navigation
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│                                                                │
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

--[[ TERMINAL SNAPSHOT: 11_complete_hierarchy_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────────── Debug Tree - Session 1 ──────────────╮      │
 6|     let│     │  📡  Session 1 (no activity)                       │      │
 7|     let│     │                                                   │      │
 8|     let│     │                                                   │      │
 9|     let│     │                                                   │      │
10|     let│     │                                                   │      │lue";
11|     let│     │                                                   │      │e trunc
12| ated wh│     │                                                   │      │
13|        │     │                                                   │      │
14|     // │     │                                                   │      │
15|     let│     │                                                   │      │
16|     let│     ╰───────────────────────────────────────────────────╯      │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: 12_help_system_full_tree
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────────── Debug Tree - Session 1 ──────────────╮      │
 6|     let│     │  📡  Session 1 (no activity)                       │      │
 7|     let│     │                                                   │      │
 8|     let│     │                                                   │      │
 9|     let│     │                                                   │      │
10|     let│     │                                                   │      │lue";
11|     let│     │                                                   │      │e trunc
12| ated wh│     │                                                   │      │
13|        │     │                                                   │      │
14|     // │     │                                                   │      │
15|     let│     │                                                   │      │
16|     let│     ╰───────────────────────────────────────────────────╯      │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: 13_frame_specific_tree
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────────── Debug Tree - Session 1 ──────────────╮      │
 6|     let│     │  📡 ╭───── Debug Tree - Frame Variables ─────╮     │      │
 7|     let│     │    │▶ 📄  global.testVariables @ /home/aether│     │      │
 8|     let│     │    │                                        │     │      │
 9|     let│     │    │                                        │     │      │
10|     let│     │    │                                        │     │      │lue";
11|     let│     │    │                                        │     │      │e trunc
12| ated wh│     │    │                                        │     │      │
13|        │     │    │                                        │     │      │
14|     // │     │    ╰────────────────────────────────────────╯     │      │
15|     let│     │                                                   │      │
16|     let│     ╰───────────────────────────────────────────────────╯      │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: 14_variables4_comparison
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────────── Debug Tree - Session 1 ──────────────╮      │
 6|     let│     │  📡 ╭───── Debug Tree - Frame Variables ─────╮     │      │
 7|     let│     │    │▶ 📄╭──── Variables4 Debug Tree ─────╮her│     │      │
 8|     let│     │    │   │▼ 📁  Local: testVariables       │   │     │      │
 9|     let│     │    │   │╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, '│   │     │      │
10|     let│     │    │   │╰─   ◐ booleanVar: true         │   │     │      │lue";
11|     let│     │    │   │╰─   󰅩 dateVar: Mon Jan 01 2024 │   │     │      │e trunc
12| ated wh│     │    │   ╰────────────────────────────────╯   │     │      │
13|        │     │    │                                        │     │      │
14|     // │     │    ╰────────────────────────────────────────╯     │      │
15|     let│     │                                                   │      │
16|     let│     ╰───────────────────────────────────────────────────╯      │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24| W10: Warning: Changing a readonly file                        1,1           Top
]]