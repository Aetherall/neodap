-- Visual verification test for Variables4 focus mode feature
-- Tests the n-2 parent tree rendering for deep navigation

local T = require("testing.testing")(describe, it)
local CommonSetups = require("testing.common_setups")

T.Scenario(function(api)
  -- Use common deep nested setup - replaces 16 lines with 1 line!
  CommonSetups.setupDeepNestedVariables(T, api)
  
  T.TerminalSnapshot('session_started')
  
  -- Open the Variables4 tree popup  
  CommonSetups.openVariablesTree(T)
  T.TerminalSnapshot('full_tree_view')

  -- First expand the Local scope (should be at cursor position already)
  T.cmd("execute \"normal \\<CR>\"") -- Expand Local scope 
  T.sleep(200)
  T.TerminalSnapshot('local_scope_expanded')
  
  -- Find and expand complexObject (should be in Local scope)
  -- Navigate to find complexObject - it may not be the first variable
  T.cmd("normal! j") -- Move to first variable
  -- Look for complexObject in the list - let's search for it
  T.cmd("/complexObject") -- Search for complexObject
  T.cmd("execute \"normal \\<CR>\"") -- Expand complexObject  
  T.sleep(200)
  T.TerminalSnapshot('complexObject_expanded')
  
  -- Navigate deeper: level1 -> nested1 -> nested2 -> nested3
  T.cmd("normal! j") -- Move to level1
  T.cmd("execute \"normal \\<CR>\"") -- Expand level1
  T.sleep(200)
  
  T.cmd("normal! j") -- Move to nested1
  T.cmd("execute \"normal \\<CR>\"") -- Expand nested1  
  T.sleep(200)
  
  T.cmd("normal! j") -- Move to nested2
  T.cmd("execute \"normal \\<CR>\"") -- Expand nested2
  T.sleep(200)
  
  T.cmd("normal! j") -- Move to nested3
  T.cmd("execute \"normal \\<CR>\"") -- Expand nested3
  T.sleep(200)
  T.TerminalSnapshot('deep_navigation_before_focus')
  
  -- Now we're deep in the hierarchy - this should show the problem
  -- The tree is very wide and hard to navigate
  
  -- Navigate to nested4 (this will be our focus target)
  T.cmd("normal! j") -- Move to nested4
  T.TerminalSnapshot('nested4_selected_full_tree')
  
  -- Enter focus mode by pressing 'f'
  T.cmd("execute \"normal f\"") -- Enter focus mode
  T.sleep(300) -- Let UI update
  T.TerminalSnapshot('focus_mode_entered')
  
  -- Now the tree should show only from the n-2 parent (nested1)
  -- with a breadcrumb showing "Focus: nested1"
  
  -- Test navigation in focus mode
  T.cmd("execute \"normal \\<CR>\"") -- Expand nested4 in focus mode
  T.sleep(200)
  
  T.cmd("normal! j") -- Navigate to nested5
  T.cmd("execute \"normal \\<CR>\"") -- Expand nested5
  T.sleep(200)
  T.TerminalSnapshot('focus_mode_navigation')
  
  -- Test resetting back to full tree
  T.cmd("execute \"normal r\"") -- Reset to full tree
  T.sleep(300)
  T.TerminalSnapshot('focus_mode_exited')
  
  -- Should now show full tree again with original title
  
  -- Test focus mode from a different depth
  -- Navigate to an even deeper node
  T.cmd("normal! j") -- Move to level6  
  T.cmd("execute \"normal \\<CR>\"") -- Expand level6
  T.sleep(200)
  
  T.cmd("normal! j") -- Move to finalValue
  T.TerminalSnapshot('very_deep_selection')
  
  -- Enter focus mode from this very deep position
  T.cmd("execute \"normal f\"") -- Enter focus mode
  T.sleep(300)
  T.TerminalSnapshot('focus_mode_very_deep')
  
  -- Test that we can re-focus when already in focus mode
  T.cmd("normal! k") -- Move to a different node
  T.cmd("execute \"normal f\"") -- Re-focus from new position
  T.sleep(200)
  T.TerminalSnapshot('re_focus_test')
  
  -- This should show focus starting from the n-2 parent of finalValue
  
  -- Test help to verify focus mode is documented
  T.cmd("execute \"normal ?\"") -- Show help
  T.sleep(500)
  T.TerminalSnapshot('help_with_focus_mode')
end)


--[[ TERMINAL SNAPSHOT: session_started
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3| 
 4| function testDeepNesting() {
 5|     // Create a deeply nested object structure
 6|     let complexObject = {
 7|         level1: {
 8|             nested1: {
 9|                 nested2: {
10|                     nested3: {
11|                         nested4: {
12|                             nested5: {
13|                                 level6: {
14|                                     finalValue: "You found me!",
15|                                     metadata: {
16|                                         depth: 7,
17|                                         path: "complexObject.level1.nested1.nest
18| ed2.nested3.nested4.nested5.level6"
19|                                     }
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: full_tree_view
Size: 24x80
Cursor: [1, 9] (line 1, col 9)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  Local: testDeepNesting                                     │
 5|     // │╰─ ▶ 󰅩 complexObject: {level1: {…}, description: 'Root le...    │
 6|     let│╰─ ▶ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...        │
 7|        │╰─ ▶ 󰅩 mixedStructure: {users: {…}}                             │
 8|        │╰─ ▶ 󰀬 this: global                                             │
 9|        │╰─ ▶ 󰅩 wideObject: {property_0: {…}, property_1: {…}...         │
10|        │▶ 📁  Global                                                     │
11|        │                                                                │
12|        │                                                                │
13|        │                                                                │
14|        │                                                                │
15|        │                                                                │
16|        │                                                                │
17|        │                                                                │d1.nest
18| ed2.nes│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               1,10-6        All
]]

--[[ TERMINAL SNAPSHOT: local_scope_expanded
Size: 24x80
Cursor: [2, 16] (line 2, col 16)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  Local: testDeepNesting                                     │
 5|     // │╰─ ▶ 󰅩 complexObject: {level1: {…}, description: 'Root le...    │
 6|     let│╰─ ▶ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...        │
 7|        │╰─ ▶ 󰅩 mixedStructure: {users: {…}}                             │
 8|        │╰─ ▶ 󰀬 this: global                                             │
 9|        │╰─ ▶ 󰅩 wideObject: {property_0: {…}, property_1: {…}...         │
10|        │▶ 📁  Global                                                     │
11|        │                                                                │
12|        │                                                                │
13|        │                                                                │
14|        │                                                                │
15|        │                                                                │
16|        │                                                                │
17|        │                                                                │d1.nest
18| ed2.nes│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               2,17-8        All
]]

--[[ TERMINAL SNAPSHOT: complexObject_expanded
Size: 24x80
Cursor: [3, 19] (line 3, col 19)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  Local: testDeepNesting                                     │
 5|     // │╰─ ▼ 󰅩 complexObject: {level1: {…}, description: 'Root le...    │
 6|     let││  ╰─   󰉿 description: "'Root level'"                           │
 7|        ││  ╰─ ▶ 󰅩 level1: {nested1: {…}, data: 'Level 1 data'}          │
 8|        ││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
 9|        │╰─ ▶ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...        │
10|        │╰─ ▶ 󰅩 mixedStructure: {users: {…}}                             │
11|        │╰─ ▶ 󰀬 this: global                                             │
12|        │╰─ ▶ 󰅩 wideObject: {property_0: {…}, property_1: {…}...         │
13|        │▶ 📁  Global                                                     │
14|        │                                                                │
15|        │                                                                │
16|        │                                                                │
17|        │                                                                │d1.nest
18| ed2.nes│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               3,20-11       All
]]

--[[ TERMINAL SNAPSHOT: deep_navigation_before_focus
Size: 24x80
Cursor: [11, 41] (line 11, col 41)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  Local: testDeepNesting                                     │
 5|     // │╰─ ▼ 󰅩 complexObject: {level1: {…}, description: 'Root le...    │
 6|     let││  ╰─   󰉿 description: "'Root level'"                           │
 7|        ││  ╰─ ▼ 󰅩 level1: {nested1: {…}, data: 'Level 1 data'}          │
 8|        ││  │  ╰─   󰉿 data: "'Level 1 data'"                             │
 9|        ││  │  ╰─ ▼ 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}      │
10|        ││  │  │  ╰─   󰉿 info: "'Level 2 info'"                          │
11|        ││  │  │  ╰─ ▼ 󰅩 nested2: {nested3: {…}, array: Array(5)}        │
12|        ││  │  │  │  ╰─ ▶ 󰅪 array: (5) [10, 20, 30, 40, 50]              │
13|        ││  │  │  │  ╰─ ▼ 󰅩 nested3: {nested4: {…}, properties: {…}}     │
14|        ││  │  │  │  │  ╰─ ▶ 󰅩 nested4: {nested5: {…}, moreData: Array(5)│
15|        ││  │  │  │  │  ╰─ ▶ 󰅩 properties: {type: 'deep', count: 42}     │
16|        ││  │  │  │  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                     │
17|        ││  │  │  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                        │d1.nest
18| ed2.nes││  │  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                           │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               11,42-23      Top
]]

--[[ TERMINAL SNAPSHOT: nested4_selected_full_tree
Size: 24x80
Cursor: [12, 41] (line 12, col 41)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  Local: testDeepNesting                                     │
 5|     // │╰─ ▼ 󰅩 complexObject: {level1: {…}, description: 'Root le...    │
 6|     let││  ╰─   󰉿 description: "'Root level'"                           │
 7|        ││  ╰─ ▼ 󰅩 level1: {nested1: {…}, data: 'Level 1 data'}          │
 8|        ││  │  ╰─   󰉿 data: "'Level 1 data'"                             │
 9|        ││  │  ╰─ ▼ 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}      │
10|        ││  │  │  ╰─   󰉿 info: "'Level 2 info'"                          │
11|        ││  │  │  ╰─ ▼ 󰅩 nested2: {nested3: {…}, array: Array(5)}        │
12|        ││  │  │  │  ╰─ ▶ 󰅪 array: (5) [10, 20, 30, 40, 50]              │
13|        ││  │  │  │  ╰─ ▼ 󰅩 nested3: {nested4: {…}, properties: {…}}     │
14|        ││  │  │  │  │  ╰─ ▶ 󰅩 nested4: {nested5: {…}, moreData: Array(5)│
15|        ││  │  │  │  │  ╰─ ▶ 󰅩 properties: {type: 'deep', count: 42}     │
16|        ││  │  │  │  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                     │
17|        ││  │  │  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                        │d1.nest
18| ed2.nes││  │  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                           │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               12,42-23      Top
]]

--[[ TERMINAL SNAPSHOT: focus_mode_entered
Size: 24x80
Cursor: [6, 29] (line 6, col 29)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▶ 󰅪 array: (5) [10, 20, 30, 40, 50]                             │
 5|     // │▼ 󰅩 nested3: {nested4: {…}, properties: {…}}                    │
 6|     let│╰─ ▶ 󰅩 nested4: {nested5: {…}, moreData: Array(5)}              │
 7|        │╰─ ▶ 󰅩 properties: {type: 'deep', count: 42}                    │
 8|        │╰─ ▶ 󰅩 [{Prototype}]: Object                                    │
 9|        │▶ 󰅩 [{Prototype}]: Object                                       │
10|        │                                                                │
11|        │                                                                │
12|        │                                                                │
13|        │                                                                │
14|        │                                                                │
15|        │                                                                │
16|        │                                                                │
17|        │                                                                │d1.nest
18| ed2.nes│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               6,30-25       All
]]

--[[ TERMINAL SNAPSHOT: focus_mode_navigation
Size: 24x80
Cursor: [9, 21] (line 9, col 21)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▶ 󰅪 array: (5) [10, 20, 30, 40, 50]                             │
 5|     // │▼ 󰅩 nested3: {nested4: {…}, properties: {…}}                    │
 6|     let│╰─ ▶ 󰅩 nested4: {nested5: {…}, moreData: Array(5)}              │
 7|        │╰─ ▶ 󰅩 properties: {type: 'deep', count: 42}                    │
 8|        │╰─ ▶ 󰅩 [{Prototype}]: Object                                    │
 9|        │▼ 󰅩 [{Prototype}]: Object                                       │
10|        │╰─ ▶ 󰊕 __proto__: ƒ __proto__()                                 │
11|        │╰─ ▼ 󰊕 __defineGetter__: ƒ __defineGetter__()                   │
12|        ││  ╰─ ▶ 󰊕 arguments: ƒ ()                                       │
13|        ││  ╰─ ▶ 󰊕 caller: ƒ ()                                          │
14|        ││  ╰─   󰎠 length: 2                                             │
15|        ││  ╰─   󰉿 name: "'__defineGetter__'"                            │
16|        ││  ╰─ ▶ 󰊕 [{Prototype}]: ƒ ()                                   │
17|        ││  ╰─ ▶ 󰅪 [{Scopes}]: Scopes[0]                                 │d1.nest
18| ed2.nes│╰─ ▶ 󰊕 __defineSetter__: ƒ __defineSetter__()                   │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               9,22-11       Top
]]

--[[ TERMINAL SNAPSHOT: focus_mode_exited
Size: 24x80
Cursor: [9, 21] (line 9, col 21)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▶ 󰅪 array: (5) [10, 20, 30, 40, 50]                             │
 5|     // │▼ 󰅩 nested3: {nested4: {…}, properties: {…}}                    │
 6|     let│╰─ ▶ 󰅩 nested4: {nested5: {…}, moreData: Array(5)}              │
 7|        │╰─ ▶ 󰅩 properties: {type: 'deep', count: 42}                    │
 8|        │╰─ ▶ 󰅩 [{Prototype}]: Object                                    │
 9|        │▼ 󰅩 [{Prototype}]: Object                                       │
10|        │╰─ ▶ 󰊕 __proto__: ƒ __proto__()                                 │
11|        │╰─ ▼ 󰊕 __defineGetter__: ƒ __defineGetter__()                   │
12|        ││  ╰─ ▶ 󰊕 arguments: ƒ ()                                       │
13|        ││  ╰─ ▶ 󰊕 caller: ƒ ()                                          │
14|        ││  ╰─   󰎠 length: 2                                             │
15|        ││  ╰─   󰉿 name: "'__defineGetter__'"                            │
16|        ││  ╰─ ▶ 󰊕 [{Prototype}]: ƒ ()                                   │
17|        ││  ╰─ ▶ 󰅪 [{Scopes}]: Scopes[0]                                 │d1.nest
18| ed2.nes│╰─ ▶ 󰊕 __defineSetter__: ƒ __defineSetter__()                   │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               9,22-11       Top
]]

--[[ TERMINAL SNAPSHOT: very_deep_selection
Size: 24x80
Cursor: [12, 26] (line 12, col 26)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▶ 󰅪 array: (5) [10, 20, 30, 40, 50]                             │
 5|     // │▼ 󰅩 nested3: {nested4: {…}, properties: {…}}                    │
 6|     let│╰─ ▶ 󰅩 nested4: {nested5: {…}, moreData: Array(5)}              │
 7|        │╰─ ▶ 󰅩 properties: {type: 'deep', count: 42}                    │
 8|        │╰─ ▶ 󰅩 [{Prototype}]: Object                                    │
 9|        │▼ 󰅩 [{Prototype}]: Object                                       │
10|        │╰─ ▶ 󰊕 __proto__: ƒ __proto__()                                 │
11|        │╰─ ▼ 󰊕 __defineGetter__: ƒ __defineGetter__()                   │
12|        ││  ╰─ ▶ 󰊕 arguments: ƒ ()                                       │
13|        ││  ╰─ ▼ 󰊕 caller: ƒ ()                                          │
14|        ││  │  ╰─ ▶ 󰊕 arguments: ƒ ()                                    │
15|        ││  │  ╰─ ▶ 󰊕 caller: ƒ ()                                       │
16|        ││  │  ╰─   󰎠 length: 0                                          │
17|        ││  │  ╰─   󰉿 name: "''"                                         │d1.nest
18| ed2.nes││  │  ╰─ ▶ 󰊕 [{Prototype}]: ƒ ()                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               12,27-14      Top
]]

--[[ TERMINAL SNAPSHOT: focus_mode_very_deep
Size: 24x80
Cursor: [12, 26] (line 12, col 26)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▶ 󰊕 arguments: ƒ ()                                             │
 5|     // │▼ 󰊕 caller: ƒ ()                                                │
 6|     let│╰─ ▶ 󰊕 arguments: ƒ ()                                          │
 7|        │╰─ ▶ 󰊕 caller: ƒ ()                                             │
 8|        │╰─   󰎠 length: 0                                                │
 9|        │╰─   󰉿 name: "''"                                               │
10|        │╰─ ▶ 󰊕 [{Prototype}]: ƒ ()                                      │
11|        │╰─ ▶ 󰅪 [{Scopes}]: Scopes[0]                                    │
12|        │  󰎠 length: 2                                                   │
13|        │  󰉿 name: "'__defineGetter__'"                                  │
14|        │▶ 󰊕 [{Prototype}]: ƒ ()                                         │
15|        │▶ 󰅪 [{Scopes}]: Scopes[0]                                       │
16|        │                                                                │
17|        │                                                                │d1.nest
18| ed2.nes│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               12,27-22      All
]]

--[[ TERMINAL SNAPSHOT: re_focus_test
Size: 24x80
Cursor: [11, 18] (line 11, col 18)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▶ 󰊕 __proto__: ƒ __proto__()                                    │
 5|     // │▼ 󰊕 __defineGetter__: ƒ __defineGetter__()                      │
 6|     let│╰─ ▶ 󰊕 arguments: ƒ ()                                          │
 7|        │╰─ ▼ 󰊕 caller: ƒ ()                                             │
 8|        ││  ╰─ ▶ 󰊕 arguments: ƒ ()                                       │
 9|        ││  ╰─ ▶ 󰊕 caller: ƒ ()                                          │
10|        ││  ╰─   󰎠 length: 0                                             │
11|        ││  ╰─   󰉿 name: "''"                                            │
12|        ││  ╰─ ▶ 󰊕 [{Prototype}]: ƒ ()                                   │
13|        ││  ╰─ ▶ 󰅪 [{Scopes}]: Scopes[0]                                 │
14|        │╰─   󰎠 length: 2                                                │
15|        │╰─   󰉿 name: "'__defineGetter__'"                               │
16|        │╰─ ▶ 󰊕 [{Prototype}]: ƒ ()                                      │
17|        │╰─ ▶ 󰅪 [{Scopes}]: Scopes[0]                                    │d1.nest
18| ed2.nes│▶ 󰊕 __defineSetter__: ƒ __defineSetter__()                      │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               11,19-12      Top
]]

--[[ TERMINAL SNAPSHOT: help_with_focus_mode
Size: 24x80
Cursor: [11, 18] (line 11, col 18)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▶ 󰊕 __proto__: ƒ __proto__()                                    │
 5|     // │▼ 󰊕 __defineGetter__: ƒ __defineGetter__()                      │
 6|     let│╰─ ▶ 󰊕 arguments: ƒ ()                                          │
 7|        │╰─ ▼ 󰊕 caller: ƒ ()                                             │
 8|        ││  ╰─ ▶ 󰊕 arguments: ƒ ()                                       │
 9|        ││  ╰─ ▶ 󰊕 caller: ƒ ()                                          │
10|        ││  ╰─   󰎠 length: 0                                             │
11|        ││  ╰─   󰉿 name: "''"                                            │
12|        ││  ╰─ ▶ 󰊕 [{Prototype}]: ƒ ()                                   │
13|        ││  ╰─ ▶ 󰅪 [{Scopes}]: Scopes[0]                                 │
14|        │╰─   󰎠 length: 2                                                │
15|        │╰─   󰉿 name: "'__defineGetter__'"                               │
16|        │╰─ ▶ 󰊕 [{Prototype}]: ƒ ()                                      │
17|        │╰─ ▶ 󰅪 [{Scopes}]: Scopes[0]                                    │d1.nest
18| ed2.nes│▶ 󰊕 __defineSetter__: ƒ __defineSetter__()                      │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               11,19-12      Top
]]