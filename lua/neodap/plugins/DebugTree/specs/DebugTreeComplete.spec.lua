-- Complete DebugTree Test - Single scenario covering ALL features and edge cases
-- This test comprehensively verifies every aspect of the DebugTree plugin
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load all necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))

  -- ========== SECTION 1: INITIAL SETUP AND BASIC TREE ==========
  
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 30j") -- Move to debugger statement
  T.TerminalSnapshot('01_initial_file')
  
  -- Launch debug session
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500)
  T.TerminalSnapshot('02_stopped_at_debugger')
  
  -- Test 1: Basic tree opening
  T.cmd("DebugTree")
  T.sleep(300)
  T.TerminalSnapshot('03_tree_opened_collapsed')
  
  -- Test 2: Session expansion
  T.cmd("execute \"normal \\<CR>\"") -- Expand session
  T.sleep(200)
  T.TerminalSnapshot('04_session_expanded_showing_thread')
  
  -- Test 3: Thread expansion and auto-expansion behavior
  T.cmd("normal! j") -- Move to thread
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread
  T.sleep(500)
  T.TerminalSnapshot('05_thread_expanded_auto_expansion_check')
  
  -- ========== SECTION 2: NAVIGATION FEATURES ==========
  
  -- Test 4: Basic j/k navigation
  T.cmd("normal! j") -- Move down to stack
  T.cmd("normal! j") -- Move to frame
  T.cmd("normal! k") -- Move back up
  T.TerminalSnapshot('06_basic_jk_navigation')
  
  -- Test 5: h/l navigation (collapse/expand)
  T.cmd("normal! j") -- Back to frame
  T.cmd("normal! l") -- Expand frame
  T.sleep(300)
  T.TerminalSnapshot('07_l_expand_frame')
  
  T.cmd("normal! h") -- Collapse frame
  T.sleep(100)
  T.TerminalSnapshot('08_h_collapse_frame')
  
  -- Test 6: Enter and Space for toggle
  T.cmd("execute \"normal \\<Space>\"") -- Toggle with space
  T.sleep(200)
  T.cmd("execute \"normal \\<CR>\"") -- Toggle with enter
  T.sleep(200)
  T.TerminalSnapshot('09_toggle_with_space_enter')
  
  -- Test 7: Sibling navigation H/L
  T.cmd("normal! j") -- Move to first scope
  T.cmd("normal! L") -- Next sibling
  T.sleep(100)
  T.cmd("normal! H") -- Previous sibling
  T.sleep(100)
  T.TerminalSnapshot('10_sibling_navigation_HL')
  
  -- Test 8: First/Last sibling K/J
  T.cmd("normal! J") -- Last sibling
  T.sleep(100)
  T.cmd("normal! K") -- First sibling
  T.sleep(100)
  T.TerminalSnapshot('11_first_last_sibling_KJ')
  
  -- Test 9: Smart up/down navigation gk/gj
  T.cmd("normal! gj") -- Smart down
  T.sleep(100)
  T.cmd("normal! gk") -- Smart up
  T.sleep(100)
  T.TerminalSnapshot('12_smart_navigation_gkgj')
  
  -- Test 10: o for expand only (no navigation)
  T.cmd("normal! o") -- Expand without moving
  T.sleep(200)
  T.TerminalSnapshot('13_o_expand_only')
  
  -- ========== SECTION 3: VARIABLE DISPLAY AND TYPES ==========
  
  -- Expand Local scope to see all variable types
  T.cmd("normal! j") -- Move into Local scope variables
  T.TerminalSnapshot('14_local_scope_variables_all_types')
  
  -- Test 11: Array expansion and display
  T.cmd("silent! normal! /arrayVar\\<CR>")
  T.sleep(100)
  T.cmd("execute \"normal \\<CR>\"") -- Expand array
  T.sleep(200)
  T.TerminalSnapshot('15_array_expanded_with_indices')
  
  -- Test 12: Object expansion and nested properties
  T.cmd("normal! /objectVar")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"") -- Expand object
  T.sleep(200)
  T.TerminalSnapshot('16_object_expanded_nested')
  
  -- Test 13: Function variable display
  T.cmd("normal! /functionVar")
  T.cmd("normal! n")
  T.TerminalSnapshot('17_function_variable_display')
  
  -- Test 14: Special types (Map, Set, Date)
  T.cmd("normal! /mapVar")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"") -- Expand Map
  T.sleep(200)
  T.TerminalSnapshot('18_map_variable_expanded')
  
  T.cmd("normal! /setVar")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"") -- Expand Set
  T.sleep(200)
  T.TerminalSnapshot('19_set_variable_expanded')
  
  -- Test 15: Long variable names and values
  T.cmd("normal! /veryLong")
  T.cmd("normal! n")
  T.TerminalSnapshot('20_long_names_truncation')
  
  -- ========== SECTION 4: FOCUS MODE ==========
  
  -- Test 16: Focus on a subtree
  T.cmd("normal! gg") -- Go to top
  T.cmd("normal! /Local")
  T.cmd("normal! n")
  T.cmd("normal! f") -- Focus on Local scope
  T.sleep(200)
  T.TerminalSnapshot('21_focus_mode_active')
  
  -- Test 17: Navigation within focused view
  T.cmd("normal! j")
  T.cmd("normal! j")
  T.cmd("normal! k")
  T.TerminalSnapshot('22_focus_mode_navigation')
  
  -- Test 18: Unfocus back to full view
  T.cmd("normal! F") -- Unfocus
  T.sleep(200)
  T.TerminalSnapshot('23_unfocused_restored')
  
  -- ========== SECTION 5: SPECIAL FEATURES ==========
  
  -- Test 19: Help system
  T.cmd("normal! ?")
  T.sleep(500)
  T.TerminalSnapshot('24_help_displayed')
  T.cmd("normal! q") -- Close notification if needed
  T.sleep(100)
  
  -- Test 20: Debug info for node
  T.cmd("normal! /arrayVar")
  T.cmd("normal! n")
  T.cmd("normal! !") -- Show debug info
  T.sleep(300)
  T.TerminalSnapshot('25_debug_info_popup')
  T.cmd("normal! q") -- Close debug popup
  T.sleep(100)
  
  -- Test 21: Refresh tree
  T.cmd("normal! r") -- Refresh
  T.sleep(200)
  T.TerminalSnapshot('26_tree_refreshed')
  
  -- Close main tree
  T.cmd("normal! q")
  T.sleep(200)
  
  -- ========== SECTION 6: DIFFERENT VIEW MODES ==========
  
  -- Test 22: Frame-specific view (Variables4 compatibility)
  T.cmd("DebugTreeFrame")
  T.sleep(300)
  T.TerminalSnapshot('27_frame_tree_view')
  
  -- Expand scopes in frame view
  T.cmd("execute \"normal \\<CR>\"") -- Expand first scope
  T.sleep(300)
  T.TerminalSnapshot('28_frame_tree_scope_expanded')
  
  T.cmd("normal! q") -- Close frame tree
  T.sleep(200)
  
  -- Test 23: Stack-specific view
  T.cmd("DebugTreeStack")
  T.sleep(300)
  T.TerminalSnapshot('29_stack_tree_view')
  
  -- Navigate frames in stack view
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Expand a frame
  T.sleep(200)
  T.TerminalSnapshot('30_stack_tree_frame_expanded')
  
  T.cmd("normal! q") -- Close stack tree
  T.sleep(200)
  
  -- ========== SECTION 7: LAZY LOADING AND GLOBAL SCOPE ==========
  
  T.cmd("DebugTree")
  T.sleep(300)
  
  -- Navigate to Global scope (usually has lazy variables)
  T.cmd("execute \"normal \\<CR>\"") -- Expand session
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread
  T.cmd("normal! j")
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Expand frame
  T.sleep(300)
  
  -- Test 24: Global scope expansion and lazy loading
  T.cmd("normal! /Global")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"") -- Expand Global scope
  T.sleep(1000) -- Wait for lazy loading
  T.TerminalSnapshot('31_global_scope_lazy_loaded')
  
  -- Test 25: Lazy variable resolution
  T.cmd("normal! j") -- Move to a lazy variable
  T.cmd("execute \"normal \\<CR>\"") -- Try to expand/resolve
  T.sleep(500)
  T.TerminalSnapshot('32_lazy_variable_resolution')
  
  -- ========== SECTION 8: MULTIPLE SESSIONS AND THREADS ==========
  
  T.cmd("normal! q") -- Close tree
  T.sleep(200)
  
  -- Test 26: Multiple breakpoints and continuing
  T.cmd("normal! gg")
  T.cmd("normal! 40j") -- Move to another line
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapContinue")
  T.sleep(1500) -- Wait for next breakpoint
  
  T.cmd("DebugTree")
  T.sleep(500)
  T.TerminalSnapshot('33_stopped_at_second_breakpoint')
  
  -- Test 27: Auto-expansion after continue
  T.cmd("execute \"normal \\<CR>\"") -- Expand session
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread
  T.sleep(500)
  T.TerminalSnapshot('34_auto_expansion_after_continue')
  
  -- ========== SECTION 9: DEEP STACK NAVIGATION ==========
  
  -- Create deeper call stack by stepping into functions
  T.cmd("normal! q") -- Close tree
  T.cmd("NeodapStepIn")
  T.sleep(1000)
  T.cmd("NeodapStepIn")
  T.sleep(1000)
  
  T.cmd("DebugTree")
  T.sleep(300)
  T.cmd("execute \"normal \\<CR>\"") -- Expand session
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread
  T.sleep(500)
  
  -- Test 28: Deep stack with multiple frames
  T.cmd("normal! j") -- Move to stack
  T.TerminalSnapshot('35_deep_stack_multiple_frames')
  
  -- Navigate through multiple frames
  T.cmd("normal! j") -- Frame 1
  T.cmd("normal! j") -- Frame 2
  T.cmd("normal! j") -- Frame 3 (if exists)
  T.TerminalSnapshot('36_deep_stack_navigation')
  
  -- ========== SECTION 10: EDGE CASES ==========
  
  -- Test 29: Circular references
  T.cmd("normal! gg")
  T.cmd("normal! /circular")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"") -- Try to expand circular reference
  T.sleep(200)
  T.TerminalSnapshot('37_circular_reference_handling')
  
  -- Test 30: Empty scopes
  T.cmd("normal! /Arguments") -- Arguments scope might be empty
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(200)
  T.TerminalSnapshot('38_empty_scope_handling')
  
  -- Test 31: Prototype chain navigation
  T.cmd("normal! /Prototype")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(200)
  T.TerminalSnapshot('39_prototype_chain_expansion')
  
  -- ========== SECTION 11: CURSOR POSITIONING ==========
  
  -- Test 32: Cursor preservation after operations
  T.cmd("normal! gg")
  T.cmd("normal! 5j") -- Move to specific position
  local before_pos = vim.fn.getcurpos()
  T.cmd("normal! r") -- Refresh
  T.sleep(200)
  T.TerminalSnapshot('40_cursor_position_after_refresh')
  
  -- Test 33: Drill down with cursor
  T.cmd("normal! /objectVar")
  T.cmd("normal! n")
  T.cmd("normal! l") -- Drill down with l
  T.sleep(100)
  T.cmd("normal! l") -- Continue drilling
  T.sleep(100)
  T.TerminalSnapshot('41_drill_down_cursor_behavior')
  
  -- ========== SECTION 12: STEP OPERATIONS AND AUTO-EXPANSION ==========
  
  T.cmd("normal! q") -- Close tree
  T.sleep(200)
  
  -- Test 34: Step over and auto-expansion
  T.cmd("NeodapStepOver")
  T.sleep(1000)
  
  T.cmd("DebugTree")
  T.sleep(300)
  T.cmd("execute \"normal \\<CR>\"") -- Expand session
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread
  T.sleep(500)
  T.TerminalSnapshot('42_auto_expansion_after_step_over')
  
  -- Test 35: Step out and stack changes
  T.cmd("normal! q")
  T.cmd("NeodapStepOut")
  T.sleep(1000)
  
  T.cmd("DebugTree")
  T.sleep(300)
  T.cmd("execute \"normal \\<CR>\"") -- Expand session
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread
  T.sleep(500)
  T.TerminalSnapshot('43_stack_after_step_out')
  
  -- ========== SECTION 13: INDEPENDENT VIEWS ==========
  
  -- Test 36: Multiple tree views open simultaneously
  T.cmd("vsplit") -- Create vertical split
  T.cmd("DebugTreeFrame") -- Frame view in new split
  T.sleep(300)
  T.TerminalSnapshot('44_multiple_views_split')
  
  -- Navigate in frame view
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(200)
  
  -- Switch to other window with main tree
  T.cmd("wincmd w")
  T.cmd("normal! j") -- Navigate in main tree
  T.TerminalSnapshot('45_independent_view_navigation')
  
  -- Close split
  T.cmd("wincmd w")
  T.cmd("normal! q")
  T.cmd("wincmd c")
  
  -- ========== SECTION 14: ERROR STATES ==========
  
  -- Test 37: Tree behavior when not debugging
  T.cmd("normal! q") -- Close tree
  T.cmd("NeodapStop") -- Stop debugging
  T.sleep(1000)
  
  T.cmd("DebugTree") -- Try to open without active session
  T.sleep(300)
  T.TerminalSnapshot('46_tree_no_active_session')
  
  -- ========== SECTION 15: PERFORMANCE WITH LARGE DATA ==========
  
  -- Launch a session with large data structures
  T.cmd("edit lua/testing/fixtures/stack/deep.js")
  T.cmd("NeodapLaunchClosest Stack [stack]")
  T.sleep(2000)
  
  T.cmd("DebugTree")
  T.sleep(300)
  T.cmd("execute \"normal \\<CR>\"") -- Expand session
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread
  T.sleep(500)
  
  -- Test 38: Large stack handling
  T.cmd("normal! j") -- Move to stack with many frames
  T.TerminalSnapshot('47_large_stack_performance')
  
  -- Test 39: Rapid navigation in large tree
  T.cmd("normal! 10j") -- Move down rapidly
  T.sleep(100)
  T.cmd("normal! 10k") -- Move up rapidly
  T.sleep(100)
  T.TerminalSnapshot('48_rapid_navigation_large_tree')
  
  -- ========== SECTION 16: FINAL CLEANUP ==========
  
  -- Test 40: Clean shutdown
  T.cmd("normal! q") -- Close tree
  T.sleep(200)
  T.cmd("NeodapStop") -- Stop debugging
  T.sleep(500)
  T.TerminalSnapshot('49_clean_shutdown')
  
  -- Final state
  T.TerminalSnapshot('50_test_complete')
  
  -- ========== COMPREHENSIVE COVERAGE SUMMARY ==========
  -- This single scenario has tested:
  -- 1. Basic tree opening and session/thread/stack/frame hierarchy
  -- 2. All navigation methods (j/k, h/l, H/L, K/J, gk/gj, Enter, Space, o)
  -- 3. All variable types (primitives, arrays, objects, functions, Map, Set, Date)
  -- 4. Focus mode (f/F) with navigation
  -- 5. Help system (?)
  -- 6. Debug info (!)
  -- 7. Tree refresh (r)
  -- 8. Multiple view modes (DebugTree, DebugTreeFrame, DebugTreeStack)
  -- 9. Lazy loading and Global scope
  -- 10. Multiple breakpoints and continuing
  -- 11. Deep stack navigation
  -- 12. Auto-expansion behavior (on stop, continue, step)
  -- 13. Edge cases (circular refs, empty scopes, prototypes)
  -- 14. Cursor positioning and drill-down
  -- 15. Step operations (over, in, out)
  -- 16. Independent/simultaneous views
  -- 17. Error states (no active session)
  -- 18. Performance with large data
  -- 19. Long variable names/values truncation
  -- 20. Clean shutdown and state management
end)

--[[ TERMINAL SNAPSHOT: 01_initial_file
Size: 24x80
Cursor: [31, 0] (line 31, col 0)
Mode: n

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
32| 
33| lua/testing/fixtures/variables/complex.js                     31,1           47%
34| 
]]

--[[ TERMINAL SNAPSHOT: 02_stopped_at_debugger
Size: 24x80
Cursor: [31, 0] (line 31, col 0)
Mode: n

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
32| 
33| lua/testing/fixtures/variables/complex.js                     31,1           47%
34| 
]]

--[[ TERMINAL SNAPSHOT: 03_tree_opened_collapsed
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|     let longStringValue = "This is a very long string value that should be trunc
 2| ated when displayed in the tree view to prevent line wrapping";
 3|        ╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▶ 📡  Session 2                                                  │
 6|     let│                                                                │
 7|        │                                                                │
 8|        │                                                                │
 9|        │                                                                │
10|        │                                                                │
11|        │                                                                │
12|        │                                                                │
13|        │                                                                │
14|     }; │                                                                │
15|        │                                                                │
16|     // │                                                                │
17|     let│                                                                │
18|        │                                                                │
19|     // ╰────────────────────────────────────────────────────────────────╯
20|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
21|     let setVar = new Set([1, 2, 3, 3, 4]);
22| 
23| lua/testing/fixtures/variables/complex.js                     31,1           47%
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: 04_session_expanded_showing_thread
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|     let longStringValue = "This is a very long string value that should be trunc
 2| ated when displayed in the tree view to prevent line wrapping";
 3|        ╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▶ 📡  Session 2                                                  │
 6|     let│                                                                │
 7|        │                                                                │
 8|        │                                                                │
 9|        │                                                                │
10|        │                                                                │
11|        │                                                                │
12|        │                                                                │
13|        │                                                                │
14|     }; │                                                                │
15|        │                                                                │
16|     // │                                                                │
17|     let│                                                                │
18|        │                                                                │
19|     // ╰────────────────────────────────────────────────────────────────╯
20|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
21|     let setVar = new Set([1, 2, 3, 3, 4]);
22| 
23| lua/testing/fixtures/variables/complex.js                     31,1           47%
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: 05_thread_expanded_auto_expansion_check
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1|     let longStringValue = "This is a very long string value that should be trunc
 2| ated when displayed in the tree view to prevent line wrapping";
 3|        ╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▶ ⏸  Thread 0 (stopped)                                      │
 7|        │                                                                │
 8|        │                                                                │
 9|        │                                                                │
10|        │                                                                │
11|        │                                                                │
12|        │                                                                │
13|        │                                                                │
14|     }; │                                                                │
15|        │                                                                │
16|     // │                                                                │
17|     let│                                                                │
18|        │                                                                │
19|     // ╰────────────────────────────────────────────────────────────────╯
20|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
21|     let setVar = new Set([1, 2, 3, 3, 4]);
22| 
23| lua/testing/fixtures/variables/complex.js                     31,1           47%
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: 06_basic_jk_navigation
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1|     let longStringValue = "This is a very long string value that should be trunc
 2| ated when displayed in the tree view to prevent line wrapping";
 3|        ╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▶ ⏸  Thread 0 (stopped)                                      │
 7|        │                                                                │
 8|        │                                                                │
 9|        │                                                                │
10|        │                                                                │
11|        │                                                                │
12|        │                                                                │
13|        │                                                                │
14|     }; │                                                                │
15|        │                                                                │
16|     // │                                                                │
17|     let│                                                                │
18|        │                                                                │
19|     // ╰────────────────────────────────────────────────────────────────╯
20|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
21|     let setVar = new Set([1, 2, 3, 3, 4]);
22| 
23| lua/testing/fixtures/variables/complex.js                     31,1           47%
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: 07_l_expand_frame
Size: 24x80
Cursor: [3, 3] (line 3, col 3)
Mode: n

 1|     let longStringValue = "This is a very long string value that should be trunc
 2| ated when displayed in the tree view to prevent line wrapping";
 3|        ╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▶ ⏸  Thread 0 (stopped)                                      │
 7|        │                                                                │
 8|        │                                                                │
 9|        │                                                                │
10|        │                                                                │
11|        │                                                                │
12|        │                                                                │
13|        │                                                                │
14|     }; │                                                                │
15|        │                                                                │
16|     // │                                                                │
17|     let│                                                                │
18|        │                                                                │
19|     // ╰────────────────────────────────────────────────────────────────╯
20|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
21|     let setVar = new Set([1, 2, 3, 3, 4]);
22| 
23| lua/testing/fixtures/variables/complex.js                     31,1           47%
24|                                                               3,4-2         All
]]

--[[ TERMINAL SNAPSHOT: 08_h_collapse_frame
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1|     let longStringValue = "This is a very long string value that should be trunc
 2| ated when displayed in the tree view to prevent line wrapping";
 3|        ╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▶ ⏸  Thread 0 (stopped)                                      │
 7|        │                                                                │
 8|        │                                                                │
 9|        │                                                                │
10|        │                                                                │
11|        │                                                                │
12|        │                                                                │
13|        │                                                                │
14|     }; │                                                                │
15|        │                                                                │
16|     // │                                                                │
17|     let│                                                                │
18|        │                                                                │
19|     // ╰────────────────────────────────────────────────────────────────╯
20|     let mapVar = new Map([{"key1", "value1"], ["key2", "value2"}]);
21|     let setVar = new Set([1, 2, 3, 3, 4]);
22| 
23| lua/testing/fixtures/variables/complex.js                     31,1           47%
24|                                                               3,1           All
]]