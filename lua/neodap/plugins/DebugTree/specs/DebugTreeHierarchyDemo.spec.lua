-- DebugTree Plugin Hierarchy Demonstration
-- Shows session to variables hierarchy using frame-level debugging

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load all required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables4'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Set up debugging session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j") -- Go to line 7
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500) -- Wait for session
  
  -- DEMO 1: Session-Level View (shows top of hierarchy)
  T.cmd("DebugTree")
  T.sleep(500)
  T.TerminalSnapshot('hierarchy_01_session_root')
  
  -- DEMO 2: Show session commands work
  T.cmd("normal! q") -- Close current
  T.cmd("DebugTreeSession")
  T.sleep(500)
  T.TerminalSnapshot('hierarchy_02_session_command')
  
  -- DEMO 3: Frame-Level View (shows Variables4 equivalent)
  T.cmd("normal! q")
  T.cmd("DebugTreeFrame")
  T.sleep(500)
  T.TerminalSnapshot('hierarchy_03_frame_level')
  
  -- DEMO 4: Expand frame to show scopes
  T.cmd("execute \"normal \\<CR>\"") -- Expand frame
  T.sleep(500)
  T.TerminalSnapshot('hierarchy_04_frame_expanded')
  
  -- DEMO 5: Navigate to scope and expand variables
  T.cmd("normal! j") -- Move to scope
  T.cmd("execute \"normal \\<CR>\"") -- Expand scope
  T.sleep(800) -- Wait for variables to load
  T.TerminalSnapshot('hierarchy_05_variables_loaded')
  
  -- DEMO 6: Navigate through variables
  T.cmd("normal! j") -- Move to first variable
  T.cmd("normal! j") -- Move to next variable 
  T.TerminalSnapshot('hierarchy_06_variable_navigation')
  
  -- DEMO 7: Compare with Variables4Tree (should be equivalent)
  T.cmd("normal! q")
  T.sleep(200)
  T.cmd("Variables4Tree")
  T.sleep(500)
  T.TerminalSnapshot('hierarchy_07_variables4_equivalent')
  
  -- DEMO 8: Show Variables4 expansion
  T.cmd("execute \"normal \\<CR>\"") -- Expand scope in Variables4
  T.sleep(500)
  T.TerminalSnapshot('hierarchy_08_variables4_expanded')
  
  -- DEMO 9: Navigate Variables4 variables 
  T.cmd("normal! j") -- Move to variable
  T.cmd("normal! j") -- Move to next variable
  T.TerminalSnapshot('hierarchy_09_variables4_navigation')
  
  -- DEMO 10: Expand complex variable in Variables4
  T.cmd("execute \"normal \\<CR>\"") -- Try to expand variable
  T.sleep(500)
  T.TerminalSnapshot('hierarchy_10_complex_variable')
  
  -- DEMO 11: Multi-layer demonstration
  T.cmd("normal! q") -- Close Variables4
  T.sleep(200)
  
  -- Open session tree first
  T.cmd("DebugTreeSession")
  T.sleep(300)
  
  -- Then open frame tree on top
  T.cmd("DebugTreeFrame") 
  T.sleep(300)
  
  -- Then open Variables4 on top
  T.cmd("Variables4Tree")
  T.sleep(500)
  T.TerminalSnapshot('hierarchy_11_three_layer_stack')
  
  -- DEMO 12: Navigate the stack
  T.cmd("execute \"normal \\<CR>\"") -- Expand in Variables4
  T.sleep(300)
  T.TerminalSnapshot('hierarchy_12_stack_interaction')
  
  -- DEMO 13: Show help system
  T.cmd("normal! ?")
  T.sleep(200)
  T.TerminalSnapshot('hierarchy_13_help_system')
  
  -- DEMO 14: Close layers one by one
  T.cmd("normal! q") -- Close help
  T.cmd("normal! q") -- Close Variables4
  T.sleep(200)
  T.TerminalSnapshot('hierarchy_14_close_variables4')
  
  T.cmd("normal! q") -- Close DebugTreeFrame
  T.sleep(200)
  T.TerminalSnapshot('hierarchy_15_close_frame')
  
  T.cmd("normal! q") -- Close DebugTreeSession
  T.sleep(200)
  T.TerminalSnapshot('hierarchy_16_all_closed')
end)

--[[ TERMINAL SNAPSHOT: hierarchy_01_session_root
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

--[[ TERMINAL SNAPSHOT: hierarchy_02_session_command
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────── Debug Tree - Session Hierarchy ──────────╮      │
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

--[[ TERMINAL SNAPSHOT: hierarchy_03_frame_level
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────── Debug Tree - Session Hierarchy ──────────╮      │
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

--[[ TERMINAL SNAPSHOT: hierarchy_04_frame_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────── Debug Tree - Session Hierarchy ──────────╮      │
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

--[[ TERMINAL SNAPSHOT: hierarchy_05_variables_loaded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────── Debug Tree - Session Hierarchy ──────────╮      │
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

--[[ TERMINAL SNAPSHOT: hierarchy_06_variable_navigation
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────── Debug Tree - Session Hierarchy ──────────╮      │
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

--[[ TERMINAL SNAPSHOT: hierarchy_07_variables4_equivalent
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────── Debug Tree - Session Hierarchy ──────────╮      │
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

--[[ TERMINAL SNAPSHOT: hierarchy_08_variables4_expanded
Size: 24x80
Cursor: [1, 4] (line 1, col 4)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────── Debug Tree - Session Hierarchy ──────────╮      │
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
24| W10: Warning: Changing a readonly file                        1,5-3         Top
]]

--[[ TERMINAL SNAPSHOT: hierarchy_09_variables4_navigation
Size: 24x80
Cursor: [3, 6] (line 3, col 6)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────── Debug Tree - Session Hierarchy ──────────╮      │
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
24| W10: Warning: Changing a readonly file                        3,7-3         Top
]]

--[[ TERMINAL SNAPSHOT: hierarchy_10_complex_variable
Size: 24x80
Cursor: [3, 6] (line 3, col 6)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────── Debug Tree - Session Hierarchy ──────────╮      │
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
24| W10: Warning: Changing a readonly file                        3,7-3         Top
]]

--[[ TERMINAL SNAPSHOT: hierarchy_11_three_layer_stack
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────── Debug Tree - Session Hierarchy ──────────╮      │
 6|     let│     │  📡 ╭───── Debug Tree - Frame Variables ─────╮     │      │
 7|     let│     │    │▶ 📄  global.testVariables @ /home/aether│     │      │
 8|     let│     │    │      ╭ ╭ ╭ Variables4 Deb…╮…╮i…╮       │     │      │
 9|     let│     │    │      │ │▶ 📄  global.testVari│vi│       │     │      │
10|     let│     │    │      │ ╰────────────────────╯  │       │     │      │lue";
11|     let│     │    │      ╰─────────────────────────╯       │     │      │e trunc
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

--[[ TERMINAL SNAPSHOT: hierarchy_12_stack_interaction
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────── Debug Tree - Session Hierarchy ──────────╮      │
 6|     let│     │  📡 ╭───── Debug Tree - Frame Variables ─────╮     │      │
 7|     let│     │    │▶ 📄  global.testVariables @ /home/aether│     │      │
 8|     let│     │    │      ╭ ╭ ╭ Variables4 Deb…╮…╮i…╮       │     │      │
 9|     let│     │    │      │ │▶ 📄  global.testVari│vi│       │     │      │
10|     let│     │    │      │ ╰────────────────────╯  │       │     │      │lue";
11|     let│     │    │      ╰─────────────────────────╯       │     │      │e trunc
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

--[[ TERMINAL SNAPSHOT: hierarchy_13_help_system
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────── Debug Tree - Session Hierarchy ──────────╮      │
 6|     let│     │  📡 ╭───── Debug Tree - Frame Variables ─────╮     │      │
 7|     let│     │    │▶ 📄  global.testVariables @ /home/aether│     │      │
 8|     let│     │    │      ╭ ╭ ╭ Variables4 Deb…╮…╮i…╮       │     │      │
 9|     let│     │    │      │ │▶ 📄  global.testVari│vi│       │     │      │
10|     let│     │    │      │ ╰────────────────────╯  │       │     │      │lue";
11|     let│     │    │      ╰─────────────────────────╯       │     │      │e trunc
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

--[[ TERMINAL SNAPSHOT: hierarchy_14_close_variables4
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────── Debug Tree - Session Hierarchy ──────────╮      │
 6|     let│     │  📡 ╭───── Debug Tree - Frame Variables ─────╮     │      │
 7|     let│     │    │▶ 📄  global.testVariables @ /home/aether│     │      │
 8|     let│     │    │      ╭ ╭ ╭ Variables4 Deb…╮…╮i…╮       │     │      │
 9|     let│     │    │      │ │▶ 📄  global.testVari│vi│       │     │      │
10|     let│     │    │      │ ╰────────────────────╯  │       │     │      │lue";
11|     let│     │    │      ╰─────────────────────────╯       │     │      │e trunc
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

--[[ TERMINAL SNAPSHOT: hierarchy_15_close_frame
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────── Debug Tree - Session Hierarchy ──────────╮      │
 6|     let│     │  📡 ╭───── Debug Tree - Frame Variables ─────╮     │      │
 7|     let│     │    │▶ 📄  global.testVariables @ /home/aether│     │      │
 8|     let│     │    │      ╭ ╭ ╭ Variables4 Deb…╮…╮i…╮       │     │      │
 9|     let│     │    │      │ │▶ 📄  global.testVari│vi│       │     │      │
10|     let│     │    │      │ ╰────────────────────╯  │       │     │      │lue";
11|     let│     │    │      ╰─────────────────────────╯       │     │      │e trunc
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

--[[ TERMINAL SNAPSHOT: hierarchy_16_all_closed
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭───────── Debug Tree - Session Hierarchy ──────────╮      │
 6|     let│     │  📡 ╭───── Debug Tree - Frame Variables ─────╮     │      │
 7|     let│     │    │▶ 📄  global.testVariables @ /home/aether│     │      │
 8|     let│     │    │      ╭ ╭ ╭ Variables4 Deb…╮…╮i…╮       │     │      │
 9|     let│     │    │      │ │▶ 📄  global.testVari│vi│       │     │      │
10|     let│     │    │      │ ╰────────────────────╯  │       │     │      │lue";
11|     let│     │    │      ╰─────────────────────────╯       │     │      │e trunc
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