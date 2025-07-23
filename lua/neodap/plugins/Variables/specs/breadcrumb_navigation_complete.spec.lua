-- Comprehensive test for Variables plugin breadcrumb navigation
-- This test demonstrates all navigation features working correctly

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.Variables'))

  -- Set up initial state and launch session
  T.cmd("edit lua/testing/fixtures/variables/deep_nested.js")
  T.cmd("NeodapLaunchClosest Deep Nested")

  -- Wait for session to start and hit breakpoint
  T.sleep(2000)

  -- Open Variables window
  T.cmd("VariablesShow")
  T.sleep(300)

  -- Navigate to Variables window
  T.cmd("wincmd h")
  T.TerminalSnapshot('01_normal_tree_mode')

  -- === PHASE 1: Enter Breadcrumb Mode ===
  T.cmd("VariablesBreadcrumb")
  T.sleep(300)
  T.TerminalSnapshot('02_breadcrumb_mode_root')

  -- === PHASE 2: Navigate Down - Local Scope ===
  -- Navigate into Local scope (should show Local variables only)
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500)
  T.TerminalSnapshot('03_navigated_into_local_scope')

  -- === PHASE 3: Navigate Down - Complex Object ===
  -- Find and navigate into complexObject
  T.cmd("/complexObject")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500)
  T.TerminalSnapshot('04_navigated_into_complex_object')

  -- === PHASE 4: Navigate Down - Level1 ===
  -- Navigate deeper into level1
  T.cmd("/level1")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500)
  T.TerminalSnapshot('05_navigated_into_level1')

  -- === PHASE 5: Navigate Down - Nested1 ===
  -- Navigate deeper into nested1
  T.cmd("/nested1")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500)
  T.TerminalSnapshot('06_navigated_into_nested1')

  -- === PHASE 6: Navigate Up ===
  -- Test going up one level (should go back to level1)
  T.cmd("normal! u")
  T.sleep(400)
  T.TerminalSnapshot('07_navigated_up_to_level1')

  -- === PHASE 7: Navigate Back ===
  -- Test going back to previous location (should go back to nested1)
  T.cmd("normal! b")
  T.sleep(400)
  T.TerminalSnapshot('08_navigated_back_to_nested1')

  -- === PHASE 8: Navigate Up Multiple Levels ===
  -- Go up again to demonstrate multiple up navigation
  T.cmd("normal! u")
  T.sleep(300)
  T.cmd("normal! u")
  T.sleep(300)
  T.TerminalSnapshot('09_navigated_up_to_complex_object')

  -- === PHASE 9: Quick Jump to Segment ===
  -- Navigate deep again first
  T.cmd("/level1")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(300)
  T.cmd("/nested1")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(300)
  
  -- Now test quick jump to 2nd breadcrumb segment (should jump to complexObject)
  T.cmd("normal! 2")
  T.sleep(400)
  T.TerminalSnapshot('10_quick_jump_to_segment_2')

  -- === PHASE 10: Navigate to Root ===
  -- Test going back to root
  T.cmd("normal! r")
  T.sleep(400)
  T.TerminalSnapshot('11_navigated_to_root')

  -- === PHASE 11: Test Different Scope Navigation ===
  -- Navigate into Global scope to test scope switching
  T.cmd("/Global")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500)
  T.TerminalSnapshot('12_navigated_into_global_scope')

  -- === PHASE 12: Array Navigation ===
  -- Go back to Local and navigate into an array
  T.cmd("normal! r")
  T.sleep(300)
  T.cmd("execute \"normal \\<CR>\"")  -- Enter Local
  T.sleep(300)
  T.cmd("/deepArray")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"")  -- Enter deepArray
  T.sleep(500)
  T.TerminalSnapshot('13_navigated_into_array')

  -- Navigate into first array element
  T.cmd("normal! j")  -- Move to [0]
  T.cmd("execute \"normal \\<CR>\"")  -- Enter [0]
  T.sleep(500)
  T.TerminalSnapshot('14_navigated_into_array_element')

  -- === PHASE 13: Deep Navigation Test ===
  -- Test very deep navigation path
  T.cmd("/nested")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"")  -- Enter nested object
  T.sleep(400)
  T.TerminalSnapshot('15_deep_navigation_path')

  -- === PHASE 14: Return to Normal Mode ===
  -- Toggle back to normal tree mode
  T.cmd("normal! B")
  T.sleep(400)
  T.TerminalSnapshot('16_back_to_normal_tree_mode')

  -- === PHASE 15: Re-enter Breadcrumb Mode (State Persistence Test) ===
  -- Test that breadcrumb mode remembers some state
  T.cmd("VariablesBreadcrumb")
  T.sleep(300)
  T.TerminalSnapshot('17_breadcrumb_mode_reenter')
end)

--[[ TERMINAL SNAPSHOT: 01_normal_tree_mode
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   󰌾 Local: testDeepNesti│// Test fixture for Variables plugin - deeply nested st
 2|   󰇧 Global              │ructures for visibility testing
 3| ~                       │
 4| ~                       │function testDeepNesting() {
 5| ~                       │    // Create a deeply nested object structure
 6| ~                       │    let complexObject = {
 7| ~                       │        level1: {
 8| ~                       │            nested1: {
 9| ~                       │                nested2: {
10| ~                       │                    nested3: {
11| ~                       │                        nested4: {
12| ~                       │                            nested5: {
13| ~                       │                                level6: {
14| ~                       │                                    finalValue: "You fo
15| ~                       │und me!",
16| ~                       │                                    metadata: {
17| ~                       │                                        depth: 7,
18| ~                       │                                        path: "complexO
19| ~                       │bject.level1.nested1.nested2.nested3.nested4.nested5.le
20| ~                       │vel6"
21| ~                       │                                    }
22| ~                       │                                },
23| <ables [RO] 1,1      All <g/fixtures/variables/deep_nested.js 1,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: 02_breadcrumb_mode_root
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| 📍  Variables            │// Test fixture for Variables plugin - deeply nested st
 2| ────────────────────────│ructures for visibility testing
 3|   󰌾 Local: testDeepNesti│
 4|   󰇧 Global              │function testDeepNesting() {
 5| ~                       │    // Create a deeply nested object structure
 6| ~                       │    let complexObject = {
 7| ~                       │        level1: {
 8| ~                       │            nested1: {
 9| ~                       │                nested2: {
10| ~                       │                    nested3: {
11| ~                       │                        nested4: {
12| ~                       │                            nested5: {
13| ~                       │                                level6: {
14| ~                       │                                    finalValue: "You fo
15| ~                       │und me!",
16| ~                       │                                    metadata: {
17| ~                       │                                        depth: 7,
18| ~                       │                                        path: "complexO
19| ~                       │bject.level1.nested1.nested2.nested3.nested4.nested5.le
20| ~                       │vel6"
21| ~                       │                                    }
22| ~                       │                                },
23| <ables [RO] 1,1      All <g/fixtures/variables/deep_nested.js 1,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: 03_navigated_into_local_scope
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| 📍  Variables            │// Test fixture for Variables plugin - deeply nested st
 2| ────────────────────────│ructures for visibility testing
 3|   󰌾 Local: testDeepNesti│
 4|   󰇧 Global              │function testDeepNesting() {
 5| ~                       │    // Create a deeply nested object structure
 6| ~                       │    let complexObject = {
 7| ~                       │        level1: {
 8| ~                       │            nested1: {
 9| ~                       │                nested2: {
10| ~                       │                    nested3: {
11| ~                       │                        nested4: {
12| ~                       │                            nested5: {
13| ~                       │                                level6: {
14| ~                       │                                    finalValue: "You fo
15| ~                       │und me!",
16| ~                       │                                    metadata: {
17| ~                       │                                        depth: 7,
18| ~                       │                                        path: "complexO
19| ~                       │bject.level1.nested1.nested2.nested3.nested4.nested5.le
20| ~                       │vel6"
21| ~                       │                                    }
22| ~                       │                                },
23| <ables [RO] 1,1      All <g/fixtures/variables/deep_nested.js 1,1            Top
24| 
]]