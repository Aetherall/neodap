-- Core test for Variables plugin breadcrumb navigation
-- Demonstrates key navigation features with clear snapshots

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

  -- === TEST: Enter Breadcrumb Mode ===
  T.cmd("VariablesBreadcrumb")
  T.sleep(300)
  T.TerminalSnapshot('02_breadcrumb_mode_shows_scopes')

  -- === TEST: Navigate Down Into Scope ===
  -- Move cursor to Local scope and enter it - should show only Local variables
  T.cmd("normal! 3G") -- Move to line 3 (Local scope)
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500)
  T.TerminalSnapshot('03_breadcrumb_inside_local_scope')

  -- === TEST: Navigate Down Into Variable ===
  -- Find and enter complexObject - should show only its properties
  T.cmd("/complexObject")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500)
  T.TerminalSnapshot('04_breadcrumb_inside_complex_object')

  -- === TEST: Navigate Further Down ===
  -- Navigate into level1 property
  T.cmd("/level1")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500)
  T.TerminalSnapshot('05_breadcrumb_deep_navigation')

  -- === TEST: Navigate Up ===
  -- Go up one level - should return to complexObject
  T.cmd("normal! u")
  T.sleep(400)
  T.TerminalSnapshot('06_breadcrumb_navigate_up')

  -- === TEST: Navigate Back ===
  -- Go back to previous location - should return to level1
  T.cmd("normal! b")
  T.sleep(400)
  T.TerminalSnapshot('07_breadcrumb_navigate_back')

  -- === TEST: Navigate to Root ===
  -- Return to root - should show all scopes
  T.cmd("normal! r")
  T.sleep(400)
  T.TerminalSnapshot('08_breadcrumb_back_to_root')

  -- === TEST: Return to Normal Mode ===
  -- Toggle back to normal tree mode
  T.cmd("normal! B")
  T.sleep(300)
  T.TerminalSnapshot('09_back_to_normal_tree_mode')
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

--[[ TERMINAL SNAPSHOT: 02_breadcrumb_mode_shows_scopes
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

--[[ TERMINAL SNAPSHOT: 03_breadcrumb_inside_local_scope
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables > Local    │// Test fixture for Variables plugin - deeply nested st
 2| ────────────────────────│ructures for visibility testing
 3|   󰀫 ▾ Local: testDeepNes│
 4|   󰅩   complexObject     │function testDeepNesting() {
 5|   󰅩   deepArray         │    // Create a deeply nested object structure
 6|   󰅩   mixedStructure    │    let complexObject = {
 7|   󰅩   this              │        level1: {
 8|   󰅩   wideObject        │            nested1: {
 9|   󰀫 ▸ Global            │                nested2: {
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
23| <ables [RO] 2,1      All <g/fixtures/variables/deep_nested.js 1,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: 04_breadcrumb_inside_complex_object
Size: 24x80
Cursor: [2, 9] (line 2, col 9)
Mode: n

 1| 📍  Variables > Local > c│// Test fixture for Variables plugin - deeply nested st
 2| ────────────────────────│ructures for visibility testing
 3|   󰀫 ↑ Local: testDeepNes│
 4|   󰀫   └▾ complexObject ←│function testDeepNesting() {
 5|   󰀫     description     │    // Create a deeply nested object structure
 6|   󰅩     level1          │    let complexObject = {
 7|   󰅩     [{Prototype}]   │        level1: {
 8|   󰀫   ├─ deepArray      │            nested1: {
 9|   󰀫   ├─ mixedStructure │                nested2: {
10|   󰀫   ├─ this           │                    nested3: {
11|   󰀫   ├─ wideObject     │                        nested4: {
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
23| <ables [RO] 2,10-4   All <g/fixtures/variables/deep_nested.js 1,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: 05_breadcrumb_deep_navigation
Size: 24x80
Cursor: [2, 11] (line 2, col 11)
Mode: n

 1| 📍  Variables > Local > c│// Test fixture for Variables plugin - deeply nested st
 2| ────────────────────────│ructures for visibility testing
 3|   󰀫 ↑ complexObject (par│
 4|   󰀫   ├─ description    │function testDeepNesting() {
 5|   󰀫   └▾ level1 ← YOU AR│    // Create a deeply nested object structure
 6|   󰀫     data            │    let complexObject = {
 7|   󰅩     nested1         │        level1: {
 8|   󰅩     [{Prototype}]   │            nested1: {
 9|   󰀫   ├─ [{Prototype}]  │                nested2: {
10|   󰀫   └▾ complexObject ←│                    nested3: {
11|   󰀫     description     │                        nested4: {
12|   󰅩     level1          │                            nested5: {
13|   󰅩     [{Prototype}]   │                                level6: {
14|   󰀫   ├─ deepArray      │                                    finalValue: "You fo
15|   󰀫   ├─ mixedStructure │und me!",
16|   󰀫   ├─ this           │                                    metadata: {
17|   󰀫   ├─ wideObject     │                                        depth: 7,
18| ~                       │                                        path: "complexO
19| ~                       │bject.level1.nested1.nested2.nested3.nested4.nested5.le
20| ~                       │vel6"
21| ~                       │                                    }
22| ~                       │                                },
23| <ables [RO] 2,12-4   All <g/fixtures/variables/deep_nested.js 1,1            Top
24| 
]]