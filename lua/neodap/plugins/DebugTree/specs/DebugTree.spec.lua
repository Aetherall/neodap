-- DebugTree Plugin Comprehensive Tests
-- Tests unified DAP hierarchy navigation and rendering

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load all required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables4'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Set up debugging session with complex state
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j")
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500) -- Wait for session to start and hit breakpoint
  
  -- Test 1: Full debug tree at session level
  T.TerminalSnapshot('before_debug_tree')
  
  T.cmd("DebugTree")
  T.sleep(500)
  T.TerminalSnapshot('debug_tree_session_level')
  
  -- Test 2: Navigate to thread level
  T.cmd("normal! j") -- Move to first thread
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread
  T.sleep(300)
  T.TerminalSnapshot('debug_tree_thread_expanded')
  
  -- Test 3: Navigate to stack level
  T.cmd("normal! j") -- Move to stack
  T.cmd("execute \"normal \\<CR>\"") -- Expand stack
  T.sleep(300) 
  T.TerminalSnapshot('debug_tree_stack_expanded')
  
  -- Test 4: Navigate to frame level (should show Variables4-level detail)
  T.cmd("normal! j") -- Move to frame
  T.cmd("execute \"normal \\<CR>\"") -- Expand frame
  T.sleep(300)
  T.TerminalSnapshot('debug_tree_frame_expanded')
  
  -- Test 5: Navigate to scope level
  T.cmd("normal! j") -- Move to first scope
  T.cmd("execute \"normal \\<CR>\"") -- Expand scope
  T.sleep(300)
  T.TerminalSnapshot('debug_tree_scope_expanded')
  
  -- Test 6: Test focus mode (Variables4 feature)
  T.cmd("normal! f") -- Focus on current scope
  T.sleep(300)
  T.TerminalSnapshot('debug_tree_focus_mode')
  
  -- Test 7: Test sophisticated variable rendering
  T.cmd("normal! j") -- Move to variable
  T.cmd("execute \"normal \\<CR>\"") -- Expand variable
  T.sleep(300)
  T.TerminalSnapshot('debug_tree_variable_detail')
  
  -- Test 8: Frame-level tree (equivalent to Variables4)
  T.cmd("normal! q") -- Close current tree
  T.sleep(200)
  
  T.cmd("DebugTreeFrame")
  T.sleep(500)
  T.TerminalSnapshot('debug_tree_frame_level')
  
  -- Test 9: Compare with Variables4Tree (should be equivalent at frame level)
  T.cmd("normal! q")
  T.sleep(200)
  
  T.cmd("Variables4Tree")
  T.sleep(500)
  T.TerminalSnapshot('variables4_comparison')
  
  -- Test 10: Help system
  T.cmd("normal! ?")
  T.sleep(200)
  T.TerminalSnapshot('debug_tree_help')
  
  -- Cleanup
  T.cmd("normal! q")
  T.sleep(200)
  T.TerminalSnapshot('debug_tree_cleanup')
end)



--[[ TERMINAL SNAPSHOT: before_debug_tree
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


--[[ TERMINAL SNAPSHOT: debug_tree_session_level
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


--[[ TERMINAL SNAPSHOT: debug_tree_thread_expanded
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


--[[ TERMINAL SNAPSHOT: debug_tree_stack_expanded
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


--[[ TERMINAL SNAPSHOT: debug_tree_frame_expanded
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


--[[ TERMINAL SNAPSHOT: debug_tree_scope_expanded
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


--[[ TERMINAL SNAPSHOT: debug_tree_focus_mode
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


--[[ TERMINAL SNAPSHOT: debug_tree_variable_detail
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

--[[ TERMINAL SNAPSHOT: debug_tree_frame_level
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭────────── Debug Tree - Frame Variables ───────────╮      │
 6|     let│     │▶ 📄  global.testVariables @ /home/aetherall/workspa│      │
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

--[[ TERMINAL SNAPSHOT: variables4_comparison
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭────────── Debug Tree - Frame Variables ───────────╮      │
 6|     let│     │▶ 📄 ╭──────── Variables4 Debug Tree ─────────╮rkspa│      │
 7|     let│     │    │▼ 📁  Local: testVariables               │     │      │
 8|     let│     │    │╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {│     │      │
 9|     let│     │    │╰─   ◐ booleanVar: true                 │     │      │
10|     let│     │    │╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00│     │      │lue";
11|     let│     │    │╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2│     │      │e trunc
12| ated wh│     │    │╰─   󰉿 longStringValue: "'This is a very│     │      │
13|        │     │    │╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => │     │      │
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

--[[ TERMINAL SNAPSHOT: debug_tree_help
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭────────── Debug Tree - Frame Variables ───────────╮      │
 6|     let│     │▶ 📄 ╭──────── Variables4 Debug Tree ─────────╮rkspa│      │
 7|     let│     │    │▼ 📁  Local: testVariables               │     │      │
 8|     let│     │    │╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {│     │      │
 9|     let│     │    │╰─   ◐ booleanVar: true                 │     │      │
10|     let│     │    │╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00│     │      │lue";
11|     let│     │    │╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2│     │      │e trunc
12| ated wh│     │    │╰─   󰉿 longStringValue: "'This is a very│     │      │
13|        │     │    │╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => │     │      │
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
24|                                                               1,1           Top
]]

--[[ TERMINAL SNAPSHOT: debug_tree_cleanup
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭────────── Debug Tree - Frame Variables ───────────╮      │
 6|     let│     │▶ 📄 ╭──────── Variables4 Debug Tree ─────────╮rkspa│      │
 7|     let│     │    │▼ 📁  Local: testVariables               │     │      │
 8|     let│     │    │╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {│     │      │
 9|     let│     │    │╰─   ◐ booleanVar: true                 │     │      │
10|     let│     │    │╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00│     │      │lue";
11|     let│     │    │╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2│     │      │e trunc
12| ated wh│     │    │╰─   󰉿 longStringValue: "'This is a very│     │      │
13|        │     │    │╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => │     │      │
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
24|                                                               1,1           Top
]]