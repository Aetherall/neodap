-- DebugTree All Features Test - Complete coverage in one scenario
-- Tests all features systematically without search commands
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load all necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))

  -- ========== PART 1: SETUP AND BASIC HIERARCHY ==========

  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 30gg") -- Go to line 30 (debugger statement)
  T.TerminalSnapshot('01_file_opened')

  -- Launch debug session
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(2000) -- Wait for debugger
  T.TerminalSnapshot('02_stopped_at_debugger')

  -- Open DebugTree
  T.cmd("DebugTree")
  T.sleep(500)
  T.TerminalSnapshot('03_debugtree_initial')

  -- Expand session to show thread
  T.cmd("normal! j")                 -- Move to Session 2
  T.cmd("execute \"normal \\<CR>\"") -- Expand Session 2
  T.sleep(200)
  T.TerminalSnapshot('04_session_expanded')

  -- Expand thread to show stack (should auto-expand)
  T.cmd("normal! j")                 -- Move to thread
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread
  T.sleep(500)
  T.TerminalSnapshot('05_thread_expanded_auto_stack')

  -- Navigate to stack and frame
  T.cmd("normal! j")                 -- Move to stack
  T.cmd("execute \"normal \\<CR>\"") -- Expand stack
  T.cmd("normal! j")                 -- Move to frame #1
  T.TerminalSnapshot('06_at_first_frame')

  -- Expand frame to show scopes
  T.cmd("execute \"normal \\<CR>\"") -- Expand frame
  T.sleep(300)
  T.TerminalSnapshot('07_frame_expanded_scopes')

  -- ========== PART 2: NAVIGATION TESTS ==========

  -- Test h/l navigation
  T.cmd("normal! l") -- Try to enter (already expanded)
  T.sleep(100)
  T.TerminalSnapshot('08_after_l_enter')
  
  T.cmd("normal! h") -- Collapse
  T.cmd("normal! h") -- Collapse
  T.cmd("normal! h") -- Collapse
  T.sleep(200)
  T.TerminalSnapshot('09_h_collapsed')

  T.cmd("normal! l") -- Re-expand and enter
  T.sleep(100)
  T.TerminalSnapshot('10_l_expanded_entered')

  -- Test sibling navigation
  T.cmd("normal! j") -- Move to next scope
  T.cmd("normal! H") -- Previous sibling
  T.sleep(100)
  T.cmd("normal! L") -- Next sibling
  T.sleep(100)
  T.TerminalSnapshot('11_sibling_nav_HL')

  -- Test first/last sibling
  T.cmd("normal! K") -- First sibling
  T.sleep(100)
  T.cmd("normal! J") -- Last sibling
  T.sleep(100)
  T.TerminalSnapshot('12_first_last_KJ')

  -- Test smart navigation
  T.cmd("normal! gk") -- Smart up
  T.cmd("normal! gj") -- Smart down
  T.TerminalSnapshot('13_smart_nav_gkgj')

  -- ========== PART 3: VARIABLE INSPECTION ==========

  -- Expand Local scope
  T.cmd("normal! K")                 -- Back to first scope (Local)
  T.cmd("execute \"normal \\<CR>\"") -- Expand Local
  T.sleep(500)
  T.TerminalSnapshot('14_local_scope_expanded')

  -- Navigate through variables
  T.cmd("normal! j") -- First variable
  T.cmd("normal! j") -- Second variable
  T.cmd("normal! j") -- Third variable
  T.TerminalSnapshot('15_navigating_variables')

  -- Find and expand an array variable
  T.cmd("normal! 5j")                -- Move down to find array
  T.cmd("execute \"normal \\<CR>\"") -- Try to expand
  T.sleep(200)
  T.TerminalSnapshot('16_array_expanded')

  -- Collapse and continue
  T.cmd("normal! h")                 -- Collapse array
  T.cmd("normal! 3j")                -- Move to find object
  T.cmd("execute \"normal \\<CR>\"") -- Expand object
  T.sleep(200)
  T.TerminalSnapshot('17_object_expanded')

  -- ========== PART 4: FOCUS MODE ==========

  -- Focus on current node
  T.cmd("normal! f") -- Focus mode
  T.sleep(200)
  T.TerminalSnapshot('19_focus_mode_active')

  -- Navigate in focused view
  T.cmd("normal! j")
  T.cmd("normal! k")
  T.TerminalSnapshot('19_focus_navigation')

  -- Unfocus
  T.cmd("normal! F") -- Unfocus
  T.sleep(200)
  T.TerminalSnapshot('20_unfocused')

  -- ========== PART 5: SPECIAL KEYS ==========

  -- Help system
  T.cmd("normal! ?") -- Show help
  T.sleep(500)
  T.TerminalSnapshot('21_help_shown')

  -- Debug info
  T.cmd("normal! !") -- Show debug info
  T.sleep(300)
  T.TerminalSnapshot('22_debug_info')
  T.cmd("normal! q") -- Close debug popup
  T.sleep(100)

  -- Refresh
  T.cmd("normal! r") -- Refresh tree
  T.sleep(200)
  T.TerminalSnapshot('23_refreshed')

  -- Close main tree
  T.cmd("normal! q") -- Quit
  T.sleep(200)
  T.TerminalSnapshot('24_tree_closed')

  -- ========== PART 6: OTHER VIEW MODES ==========

  -- Frame-specific view
  T.cmd("DebugTreeFrame")
  T.sleep(300)
  T.TerminalSnapshot('25_frame_tree')

  -- Expand scope in frame view
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(300)
  T.TerminalSnapshot('26_frame_tree_expanded')

  -- Navigate variables
  T.cmd("normal! 3j")                -- Move down
  T.cmd("execute \"normal \\<CR>\"") -- Expand if possible
  T.sleep(200)
  T.TerminalSnapshot('27_frame_tree_navigation')

  T.cmd("normal! q") -- Close frame tree
  T.sleep(200)

  -- Stack view
  T.cmd("DebugTreeStack")
  T.sleep(300)
  T.TerminalSnapshot('28_stack_tree')

  T.cmd("normal! j")                 -- Navigate frames
  T.cmd("execute \"normal \\<CR>\"") -- Expand frame
  T.sleep(200)
  T.TerminalSnapshot('29_stack_tree_frame')

  T.cmd("normal! q") -- Close stack tree
  T.sleep(200)

  -- ========== PART 7: GLOBAL SCOPE AND LAZY LOADING ==========

  T.cmd("DebugTree")
  T.sleep(300)

  -- Navigate to Global scope
  T.cmd("execute \"normal \\<CR>\"") -- Session
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Thread
  T.cmd("normal! j")
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Frame
  T.cmd("normal! j")
  T.cmd("normal! j")                 -- Move to Global scope
  T.cmd("execute \"normal \\<CR>\"") -- Expand Global
  T.sleep(1000)                      -- Wait for lazy loading
  T.TerminalSnapshot('30_global_scope_lazy')

  -- ========== PART 8: DEBUGGING FLOW ==========

  T.cmd("normal! q") -- Close tree
  T.sleep(200)

  -- Add another breakpoint and continue
  T.cmd("normal! 10j") -- Move down in file
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapContinue")
  T.sleep(1500)

  -- Reopen tree to check auto-expansion
  T.cmd("DebugTree")
  T.sleep(300)
  T.cmd("execute \"normal \\<CR>\"") -- Session
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Thread
  T.sleep(500)
  T.TerminalSnapshot('31_auto_expansion_continue')

  -- ========== PART 9: STEP OPERATIONS ==========

  T.cmd("normal! q") -- Close tree
  T.sleep(200)

  -- Step over
  T.cmd("NeodapStepOver")
  T.sleep(1000)

  T.cmd("DebugTree")
  T.sleep(300)
  T.cmd("execute \"normal \\<CR>\"") -- Session
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Thread
  T.sleep(500)
  T.TerminalSnapshot('32_after_step_over')

  -- ========== PART 10: MULTIPLE VIEWS ==========

  -- Create split with different view
  T.cmd("vsplit")
  T.cmd("DebugTreeFrame")
  T.sleep(300)
  T.TerminalSnapshot('33_split_views')

  -- Navigate in each view
  T.cmd("execute \"normal \\<CR>\"") -- Expand in frame view
  T.cmd("wincmd w")                  -- Switch window
  T.cmd("normal! j")                 -- Navigate in main view
  T.TerminalSnapshot('34_independent_navigation')

  -- Clean up split
  T.cmd("wincmd w")
  T.cmd("normal! q")
  T.cmd("wincmd c")

  -- ========== PART 11: EDGE CASES ==========

  -- Expand/collapse rapidly
  T.cmd("execute \"normal \\<Space>\"") -- Toggle
  T.cmd("execute \"normal \\<Space>\"") -- Toggle
  T.cmd("execute \"normal \\<Space>\"") -- Toggle
  T.TerminalSnapshot('35_rapid_toggle')

  -- Try o for expand only
  T.cmd("normal! o") -- Expand without navigation
  T.sleep(200)
  T.TerminalSnapshot('36_o_expand_only')

  -- Navigate to deeply nested item
  T.cmd("normal! j")
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Expand nested
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Continue expanding
  T.sleep(200)
  T.TerminalSnapshot('37_deep_nesting')

  -- ========== PART 12: ERROR STATES ==========

  -- Close tree and stop debugging
  T.cmd("normal! q")
  T.cmd("NeodapStop")
  T.sleep(1000)

  -- Try to open tree without session
  T.cmd("DebugTree")
  T.sleep(300)
  T.TerminalSnapshot('38_no_active_session')

  -- ========== PART 13: CLEAN SHUTDOWN ==========

  T.cmd("normal! q") -- Close if opened
  T.sleep(200)
  T.TerminalSnapshot('39_final_state')
end, 60000) -- 60 seconds for the entire scenario










--[[ TERMINAL SNAPSHOT: 01_file_opened
Size: 24x80
Cursor: [30, 0] (line 30, col 0)
Mode: n

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
23|         method: function() { return "method"; }
24|     };
25| 
26|     // Function
27|     let functionVar = function(x) { return x * 2; };
28| 
29|     // Map and Set
30|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
31|     let setVar = new Set([1, 2, 3, 3, 4]);
32| lua/testing/fixtures/variables/complex.js                     30,1           42%
33| 
]]









--[[ TERMINAL SNAPSHOT: 02_stopped_at_debugger
Size: 24x80
Cursor: [30, 0] (line 30, col 0)
Mode: n

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
23|         method: function() { return "method"; }
24|     };
25| 
26|     // Function
27|     let functionVar = function(x) { return x * 2; };
28| 
29|     // Map and Set
30|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
31|     let setVar = new Set([1, 2, 3, 3, 4]);
32| lua/testing/fixtures/variables/complex.js                     30,1           42%
33| 
]]

--[[ TERMINAL SNAPSHOT: 03_debugtree_initial
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
 2|     let longStringValue = "This is a very long string value that should be trunc
 3| ated wh╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|        │▶ 📡  Session 1                                                  │
 5|     // │▶ 📡  Session 2                                                  │
 6|     let│                                                                │
 7|     let│                                                                │
 8|        │                                                                │
 9|        │                                                                │
10|        │                                                                │
11|        │                                                                │
12|        │                                                                │
13|        │                                                                │
14|        │                                                                │
15|     }; │                                                                │
16|        │                                                                │
17|     // │                                                                │
18|     let│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|     // Map and Set
21|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
22|     let setVar = new Set([1, 2, 3, 3, 4]);
23| lua/testing/fixtures/variables/complex.js                     30,1           42%
24|                                                               1,1           All
]]


--[[ TERMINAL SNAPSHOT: 04_session_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
 2|     let longStringValue = "This is a very long string value that should be trunc
 3| ated wh╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|        │▶ 📡  Session 1                                                  │
 5|     // │▼ 📡  Session 2                                                  │
 6|     let│╰─ ▶ ⏸  Thread 0 (stopped)                                      │
 7|     let│                                                                │
 8|        │                                                                │
 9|        │                                                                │
10|        │                                                                │
11|        │                                                                │
12|        │                                                                │
13|        │                                                                │
14|        │                                                                │
15|     }; │                                                                │
16|        │                                                                │
17|     // │                                                                │
18|     let│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|     // Map and Set
21|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
22|     let setVar = new Set([1, 2, 3, 3, 4]);
23| lua/testing/fixtures/variables/complex.js                     30,1           42%
24|                                                               2,1           All
]]


--[[ TERMINAL SNAPSHOT: 05_thread_expanded_auto_stack
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
 2|     let longStringValue = "This is a very long string value that should be trunc
 3| ated wh╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|        │▶ 📡  Session 1                                                  │
 5|     // │▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▶ 📚  Stack (8 frames)                                     │
 8|        │                                                                │
 9|        │                                                                │
10|        │                                                                │
11|        │                                                                │
12|        │                                                                │
13|        │                                                                │
14|        │                                                                │
15|     }; │                                                                │
16|        │                                                                │
17|     // │                                                                │
18|     let│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|     // Map and Set
21|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
22|     let setVar = new Set([1, 2, 3, 3, 4]);
23| lua/testing/fixtures/variables/complex.js                     30,1           42%
24|                                                               3,1           All
]]



--[[ TERMINAL SNAPSHOT: 06_at_first_frame
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
 2|     let longStringValue = "This is a very long string value that should be trunc
 3| ated wh╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|        │▶ 📡  Session 1                                                  │
 5|     // │▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|        ││  │  ╰─ ▶ #1 🖼   global.testVariables                          │
 9|        ││  │  ╰─ ▶ #2 🖼   <anonymous>                                   │
10|        ││  │  ╰─ ▶ #3 🖼   Module._compile                               │
11|        ││  │  ╰─ ▶ #4 🖼   Module._extensions..js                        │
12|        ││  │  ╰─ ▶ #5 🖼   Module.load                                   │
13|        ││  │  ╰─ ▶ #6 🖼   Module._load                                  │
14|        ││  │  ╰─ ▶ #7 🖼   function Module(id = '', parent) {.executeUser│
15|     }; ││  │  ╰─ ▶ #8 🖼   <anonymous>                                   │
16|        │                                                                │
17|     // │                                                                │
18|     let│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|     // Map and Set
21|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
22|     let setVar = new Set([1, 2, 3, 3, 4]);
23| lua/testing/fixtures/variables/complex.js                     30,1           42%
24|                                                               5,1           All
]]



--[[ TERMINAL SNAPSHOT: 07_frame_expanded_scopes
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
 2|     let longStringValue = "This is a very long string value that should be trunc
 3| ated wh╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|        │▶ 📡  Session 1                                                  │
 5|     // │▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|        ││  │  ╰─ ▼ #1 🖼   global.testVariables                          │
 9|        ││  │  │  ╰─ ▶ 📁  Local: testVariables                           │
10|        ││  │  │  ╰─ ▶ 🌍  Global                                         │
11|        ││  │  ╰─ ▶ #2 🖼   <anonymous>                                   │
12|        ││  │  ╰─ ▶ #3 🖼   Module._compile                               │
13|        ││  │  ╰─ ▶ #4 🖼   Module._extensions..js                        │
14|        ││  │  ╰─ ▶ #5 🖼   Module.load                                   │
15|     }; ││  │  ╰─ ▶ #6 🖼   Module._load                                  │
16|        ││  │  ╰─ ▶ #7 🖼   function Module(id = '', parent) {.executeUser│
17|     // ││  │  ╰─ ▶ #8 🖼   <anonymous>                                   │
18|     let│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|     // Map and Set
21|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
22|     let setVar = new Set([1, 2, 3, 3, 4]);
23| lua/testing/fixtures/variables/complex.js                     30,1           42%
24|                                                               5,1           All
]]



--[[ TERMINAL SNAPSHOT: 08_h_collapsed
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
 2|     let longStringValue = "This is a very long string value that should be trunc
 3| ated wh╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|        │▶ 📡  Session 1                                                  │
 5|     // │▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|        ││  │  ╰─ ▼ #1 🖼   global.testVariables                          │
 9|        ││  │  │  ╰─ ▶ 📁  Local: testVariables                           │
10|        ││  │  │  ╰─ ▶ 🌍  Global                                         │
11|        ││  │  ╰─ ▶ #2 🖼   <anonymous>                                   │
12|        ││  │  ╰─ ▶ #3 🖼   Module._compile                               │
13|        ││  │  ╰─ ▶ #4 🖼   Module._extensions..js                        │
14|        ││  │  ╰─ ▶ #5 🖼   Module.load                                   │
15|     }; ││  │  ╰─ ▶ #6 🖼   Module._load                                  │
16|        ││  │  ╰─ ▶ #7 🖼   function Module(id = '', parent) {.executeUser│
17|     // ││  │  ╰─ ▶ #8 🖼   <anonymous>                                   │
18|     let│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|     // Map and Set
21|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
22|     let setVar = new Set([1, 2, 3, 3, 4]);
23| lua/testing/fixtures/variables/complex.js                     30,1           42%
24|                                                               5,1           All
]]



--[[ TERMINAL SNAPSHOT: 09_l_expanded_entered
Size: 24x80
Cursor: [5, 3] (line 5, col 3)
Mode: n

 1|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
 2|     let longStringValue = "This is a very long string value that should be trunc
 3| ated wh╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|        │▶ 📡  Session 1                                                  │
 5|     // │▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|        ││  │  ╰─ ▼ #1 🖼   global.testVariables                          │
 9|        ││  │  │  ╰─ ▶ 📁  Local: testVariables                           │
10|        ││  │  │  ╰─ ▶ 🌍  Global                                         │
11|        ││  │  ╰─ ▶ #2 🖼   <anonymous>                                   │
12|        ││  │  ╰─ ▶ #3 🖼   Module._compile                               │
13|        ││  │  ╰─ ▶ #4 🖼   Module._extensions..js                        │
14|        ││  │  ╰─ ▶ #5 🖼   Module.load                                   │
15|     }; ││  │  ╰─ ▶ #6 🖼   Module._load                                  │
16|        ││  │  ╰─ ▶ #7 🖼   function Module(id = '', parent) {.executeUser│
17|     // ││  │  ╰─ ▶ #8 🖼   <anonymous>                                   │
18|     let│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|     // Map and Set
21|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
22|     let setVar = new Set([1, 2, 3, 3, 4]);
23| lua/testing/fixtures/variables/complex.js                     30,1           42%
24|                                                               5,4-2         All
]]



--[[ TERMINAL SNAPSHOT: 10_sibling_nav_HL
Size: 24x80
Cursor: [14, 3] (line 14, col 3)
Mode: n

 1|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
 2|     let longStringValue = "This is a very long string value that should be trunc
 3| ated wh╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|        │▶ 📡  Session 1                                                  │
 5|     // │▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|        ││  │  ╰─ ▼ #1 🖼   global.testVariables                          │
 9|        ││  │  │  ╰─ ▶ 📁  Local: testVariables                           │
10|        ││  │  │  ╰─ ▶ 🌍  Global                                         │
11|        ││  │  ╰─ ▶ #2 🖼   <anonymous>                                   │
12|        ││  │  ╰─ ▶ #3 🖼   Module._compile                               │
13|        ││  │  ╰─ ▶ #4 🖼   Module._extensions..js                        │
14|        ││  │  ╰─ ▶ #5 🖼   Module.load                                   │
15|     }; ││  │  ╰─ ▶ #6 🖼   Module._load                                  │
16|        ││  │  ╰─ ▶ #7 🖼   function Module(id = '', parent) {.executeUser│
17|     // ││  │  ╰─ ▶ #8 🖼   <anonymous>                                   │
18|     let│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|     // Map and Set
21|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
22|     let setVar = new Set([1, 2, 3, 3, 4]);
23| lua/testing/fixtures/variables/complex.js                     30,1           42%
24|                                                               14,4-2        All
]]


--[[ TERMINAL SNAPSHOT: 08_after_l_enter
Size: 24x80
Cursor: [5, 3] (line 5, col 3)
Mode: n

 1|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
 2|     let longStringValue = "This is a very long string value that should be trunc
 3| ated wh╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|        │▶ 📡  Session 1                                                  │
 5|     // │▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|        ││  │  ╰─ ▼ #1 🖼   global.testVariables                          │
 9|        ││  │  │  ╰─ ▶ 📁  Local: testVariables                           │
10|        ││  │  │  ╰─ ▶ 🌍  Global                                         │
11|        ││  │  ╰─ ▶ #2 🖼   <anonymous>                                   │
12|        ││  │  ╰─ ▶ #3 🖼   Module._compile                               │
13|        ││  │  ╰─ ▶ #4 🖼   Module._extensions..js                        │
14|        ││  │  ╰─ ▶ #5 🖼   Module.load                                   │
15|     }; ││  │  ╰─ ▶ #6 🖼   Module._load                                  │
16|        ││  │  ╰─ ▶ #7 🖼   function Module(id = '', parent) {.executeUser│
17|     // ││  │  ╰─ ▶ #8 🖼   <anonymous>                                   │
18|     let│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|     // Map and Set
21|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
22|     let setVar = new Set([1, 2, 3, 3, 4]);
23| lua/testing/fixtures/variables/complex.js                     30,1           42%
24|                                                               5,4-2         All
]]

--[[ TERMINAL SNAPSHOT: 09_h_collapsed
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
 2|     let longStringValue = "This is a very long string value that should be trunc
 3| ated wh╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|        │▶ 📡  Session 1                                                  │
 5|     // │▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|        ││  │  ╰─ ▼ #1 🖼   global.testVariables                          │
 9|        ││  │  │  ╰─ ▶ 📁  Local: testVariables                           │
10|        ││  │  │  ╰─ ▶ 🌍  Global                                         │
11|        ││  │  ╰─ ▶ #2 🖼   <anonymous>                                   │
12|        ││  │  ╰─ ▶ #3 🖼   Module._compile                               │
13|        ││  │  ╰─ ▶ #4 🖼   Module._extensions..js                        │
14|        ││  │  ╰─ ▶ #5 🖼   Module.load                                   │
15|     }; ││  │  ╰─ ▶ #6 🖼   Module._load                                  │
16|        ││  │  ╰─ ▶ #7 🖼   function Module(id = '', parent) {.executeUser│
17|     // ││  │  ╰─ ▶ #8 🖼   <anonymous>                                   │
18|     let│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|     // Map and Set
21|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
22|     let setVar = new Set([1, 2, 3, 3, 4]);
23| lua/testing/fixtures/variables/complex.js                     30,1           42%
24|                                                               5,1           All
]]

--[[ TERMINAL SNAPSHOT: 10_l_expanded_entered
Size: 24x80
Cursor: [5, 3] (line 5, col 3)
Mode: n

 1|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
 2|     let longStringValue = "This is a very long string value that should be trunc
 3| ated wh╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|        │▶ 📡  Session 1                                                  │
 5|     // │▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|        ││  │  ╰─ ▼ #1 🖼   global.testVariables                          │
 9|        ││  │  │  ╰─ ▶ 📁  Local: testVariables                           │
10|        ││  │  │  ╰─ ▶ 🌍  Global                                         │
11|        ││  │  ╰─ ▶ #2 🖼   <anonymous>                                   │
12|        ││  │  ╰─ ▶ #3 🖼   Module._compile                               │
13|        ││  │  ╰─ ▶ #4 🖼   Module._extensions..js                        │
14|        ││  │  ╰─ ▶ #5 🖼   Module.load                                   │
15|     }; ││  │  ╰─ ▶ #6 🖼   Module._load                                  │
16|        ││  │  ╰─ ▶ #7 🖼   function Module(id = '', parent) {.executeUser│
17|     // ││  │  ╰─ ▶ #8 🖼   <anonymous>                                   │
18|     let│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|     // Map and Set
21|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
22|     let setVar = new Set([1, 2, 3, 3, 4]);
23| lua/testing/fixtures/variables/complex.js                     30,1           42%
24|                                                               5,4-2         All
]]

--[[ TERMINAL SNAPSHOT: 11_sibling_nav_HL
Size: 24x80
Cursor: [14, 3] (line 14, col 3)
Mode: n

 1|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
 2|     let longStringValue = "This is a very long string value that should be trunc
 3| ated wh╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|        │▶ 📡  Session 1                                                  │
 5|     // │▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|        ││  │  ╰─ ▼ #1 🖼   global.testVariables                          │
 9|        ││  │  │  ╰─ ▶ 📁  Local: testVariables                           │
10|        ││  │  │  ╰─ ▶ 🌍  Global                                         │
11|        ││  │  ╰─ ▶ #2 🖼   <anonymous>                                   │
12|        ││  │  ╰─ ▶ #3 🖼   Module._compile                               │
13|        ││  │  ╰─ ▶ #4 🖼   Module._extensions..js                        │
14|        ││  │  ╰─ ▶ #5 🖼   Module.load                                   │
15|     }; ││  │  ╰─ ▶ #6 🖼   Module._load                                  │
16|        ││  │  ╰─ ▶ #7 🖼   function Module(id = '', parent) {.executeUser│
17|     // ││  │  ╰─ ▶ #8 🖼   <anonymous>                                   │
18|     let│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|     // Map and Set
21|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
22|     let setVar = new Set([1, 2, 3, 3, 4]);
23| lua/testing/fixtures/variables/complex.js                     30,1           42%
24|                                                               14,4-2        All
]]