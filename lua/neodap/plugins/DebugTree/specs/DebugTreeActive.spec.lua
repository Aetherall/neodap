-- DebugTree Plugin Active Debugging Tests
-- Tests unified DAP hierarchy navigation with active debugging session

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load all required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables4'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Set up active debugging session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j") -- Go to line 7
  T.cmd("NeodapToggleBreakpoint")
  T.TerminalSnapshot('before_active_debug')
  
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(2000) -- Wait for session to start and hit breakpoint
  
  -- Test 1: Active session with threads
  T.cmd("DebugTree")
  T.sleep(500)
  T.TerminalSnapshot('active_session_with_threads')
  
  -- Test 2: Expand active thread
  T.cmd("execute \"normal \\<CR>\"") -- Expand first node (should be thread)
  T.sleep(300)
  T.TerminalSnapshot('active_thread_expanded')
  
  -- Test 3: Navigate to stack
  T.cmd("normal! j") -- Move to stack
  T.cmd("execute \"normal \\<CR>\"") -- Expand stack
  T.sleep(300)
  T.TerminalSnapshot('active_stack_expanded')
  
  -- Test 4: Navigate to frame and expand
  T.cmd("normal! j") -- Move to frame
  T.cmd("execute \"normal \\<CR>\"") -- Expand frame
  T.sleep(500)
  T.TerminalSnapshot('active_frame_with_scopes')
  
  -- Test 5: Navigate to scope and expand variables
  T.cmd("normal! j") -- Move to scope
  T.cmd("execute \"normal \\<CR>\"") -- Expand scope
  T.sleep(500)
  T.TerminalSnapshot('active_scope_with_variables')
  
  -- Test 6: Test focus mode on variable
  T.cmd("normal! j") -- Move to variable
  T.cmd("normal! f") -- Focus mode
  T.sleep(300)
  T.TerminalSnapshot('active_variable_focus')
  
  -- Test 7: Dedicated frame-level tree 
  T.cmd("normal! q") -- Close current tree
  T.sleep(200)
  
  T.cmd("DebugTreeFrame")
  T.sleep(500)
  T.TerminalSnapshot('debugtree_frame_level_active')
  
  -- Test 8: Compare with Variables4Tree
  T.cmd("normal! q")
  T.sleep(200)
  
  T.cmd("Variables4Tree") 
  T.sleep(500)
  T.TerminalSnapshot('variables4_active_comparison')
  
  -- Test 9: Session-level tree command
  T.cmd("normal! q")
  T.sleep(200)
  
  T.cmd("DebugTreeSession")
  T.sleep(500)
  T.TerminalSnapshot('session_level_command')
  
  -- Test 10: Thread-level tree command
  T.cmd("normal! q")
  T.sleep(200)
  
  T.cmd("DebugTreeThread")
  T.sleep(500)
  T.TerminalSnapshot('thread_level_command')
  
  -- Test 11: Help system in active state
  T.cmd("normal! ?")
  T.sleep(200)
  T.TerminalSnapshot('active_help_system')
  
  -- Cleanup
  T.cmd("normal! q")
  T.sleep(200)
  T.TerminalSnapshot('active_cleanup')
end)


--[[ TERMINAL SNAPSHOT: before_active_debug
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

--[[ TERMINAL SNAPSHOT: active_session_with_threads
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

--[[ TERMINAL SNAPSHOT: active_thread_expanded
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

--[[ TERMINAL SNAPSHOT: active_stack_expanded
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

--[[ TERMINAL SNAPSHOT: active_frame_with_scopes
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

--[[ TERMINAL SNAPSHOT: active_scope_with_variables
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

--[[ TERMINAL SNAPSHOT: active_variable_focus
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

--[[ TERMINAL SNAPSHOT: debugtree_frame_level_active
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

--[[ TERMINAL SNAPSHOT: variables4_active_comparison
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

--[[ TERMINAL SNAPSHOT: session_level_command
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭────────── Debug Tree - Frame Variables ───────────╮      │
 6|     let│     │▶ 📄 ╭──────── Variables4 Debug Tree ─────────╮rkspa│      │
 7|     let│     │    │▼ 📁╭ Debug Tree - Session Hierarchy ╮   │     │      │
 8|     let│     │    │╰─ │  📡  Session 1 (no activity)    │, {│     │      │
 9|     let│     │    │╰─ │                                │   │     │      │
10|     let│     │    │╰─ │                                │:00│     │      │lue";
11|     let│     │    │╰─ │                                │* 2│     │      │e trunc
12| ated wh│     │    │╰─ ╰────────────────────────────────╯ery│     │      │
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
24| W10: Warning: Changing a readonly file                        1,1           All
]]

--[[ TERMINAL SNAPSHOT: thread_level_command
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭────────── Debug Tree - Frame Variables ───────────╮      │
 6|     let│     │▶ 📄 ╭──────── Variables4 Debug Tree ─────────╮rkspa│      │
 7|     let│     │    │▼ 📁╭ Debug Tree - Session Hierarchy ╮   │     │      │
 8|     let│     │    │╰─ │  📡  Session 1 (no activity)    │, {│     │      │
 9|     let│     │    │╰─ │                                │   │     │      │
10|     let│     │    │╰─ │                                │:00│     │      │lue";
11|     let│     │    │╰─ │                                │* 2│     │      │e trunc
12| ated wh│     │    │╰─ ╰────────────────────────────────╯ery│     │      │
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
24| No stopped thread available                                   1,1           All
]]

--[[ TERMINAL SNAPSHOT: active_help_system
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭────────── Debug Tree - Frame Variables ───────────╮      │
 6|     let│     │▶ 📄 ╭──────── Variables4 Debug Tree ─────────╮rkspa│      │
 7|     let│     │    │▼ 📁╭ Debug Tree - Session Hierarchy ╮   │     │      │
 8|     let│     │    │╰─ │  📡  Session 1 (no activity)    │, {│     │      │
 9|     let│     │    │╰─ │                                │   │     │      │
10|     let│     │    │╰─ │                                │:00│     │      │lue";
11|     let│     │    │╰─ │                                │* 2│     │      │e trunc
12| ated wh│     │    │╰─ ╰────────────────────────────────╯ery│     │      │
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
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: active_cleanup
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Debug Tree - Session 1 ────────────────────╮
 4|     // │  📡  Session 1 (no activity)                                    │
 5|     let│     ╭────────── Debug Tree - Frame Variables ───────────╮      │
 6|     let│     │▶ 📄 ╭──────── Variables4 Debug Tree ─────────╮rkspa│      │
 7|     let│     │    │▼ 📁╭ Debug Tree - Session Hierarchy ╮   │     │      │
 8|     let│     │    │╰─ │  📡  Session 1 (no activity)    │, {│     │      │
 9|     let│     │    │╰─ │                                │   │     │      │
10|     let│     │    │╰─ │                                │:00│     │      │lue";
11|     let│     │    │╰─ │                                │* 2│     │      │e trunc
12| ated wh│     │    │╰─ ╰────────────────────────────────╯ery│     │      │
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
24|                                                               1,1           All
]]