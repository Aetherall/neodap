-- Comprehensive focus mode testing for Variables4
-- Consolidates all focus mode tests into a single comprehensive test

local T = require("testing.testing")(describe, it)
local CommonSetups = require("testing.common_setups")

T.Scenario(function(api)
  -- Setup focus mode testing with deep nested data
  CommonSetups.setupFocusModeTest(T, api)

  -- Test 1: Basic focus mode activation
  T.TerminalSnapshot('focus_mode_initial')

  -- Test 2: Auto-drill focus behavior
  T.cmd("normal! j") -- Navigate to focusable item
  T.cmd("execute \"normal \\<CR>\"") -- Trigger focus
  T.sleep(200)
  T.TerminalSnapshot('auto_drill_focus_activated')

  -- Test 3: Bidirectional focus navigation
  T.cmd("normal! j") -- Navigate within focus
  T.TerminalSnapshot('bidirectional_focus_down')
  
  T.cmd("normal! k") -- Navigate back up
  T.TerminalSnapshot('bidirectional_focus_up')

  -- Test 4: Hierarchical focus (n-2 parent rendering)
  T.cmd("/level1") -- Search for nested item
  T.cmd("execute \"normal \\<CR>\"") -- Expand level1
  T.sleep(200)
  T.cmd("normal! j") -- Navigate to nested1
  T.cmd("execute \"normal \\<CR>\"") -- Focus on nested1
  T.sleep(300)
  T.TerminalSnapshot('hierarchical_focus_deep')

  -- Test 5: Focus mode with hjkl navigation
  T.cmd("normal! h") -- Left navigation in focus
  T.TerminalSnapshot('focus_hjkl_left')
  
  T.cmd("normal! l") -- Right navigation in focus
  T.TerminalSnapshot('focus_hjkl_right')

  -- Test 6: True hierarchical focus with parent context
  T.cmd("normal! j") -- Navigate deeper
  T.cmd("execute \"normal \\<CR>\"") -- Expand
  T.sleep(200)
  T.TerminalSnapshot('true_hierarchical_focus')

  -- Test 7: Simple focus mode exit
  T.cmd("normal! q") -- Exit focus mode
  T.sleep(200)
  T.TerminalSnapshot('focus_mode_exit')

  -- Test 8: Focus mode re-entry verification
  T.cmd("Variables4Tree") -- Re-open
  T.sleep(300)
  T.TerminalSnapshot('focus_mode_reentry_verification')
end)


--[[ TERMINAL SNAPSHOT: focus_mode_initial
Size: 24x80
Cursor: [4, 21] (line 4, col 21)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  Local: testDeepNesting                                     │
 5|     // │╰─ ▶ 󰅩 complexObject: {level1: {…}, description: 'Root le...    │
 6|     let│╰─ ▼ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...        │
 7|        ││  ╰─ ▶ 󰅩 0: {index: 0, value: 'Item 0', nested: {...           │
 8|        ││  ╰─ ▶ 󰅩 1: {index: 1, value: 'Item 1', nested: {...           │
 9|        ││  ╰─ ▶ 󰅩 2: {index: 2, value: 'Item 2', nested: {...           │
10|        ││  ╰─ ▶ 󰅩 3: {index: 3, value: 'Item 3', nested: {...           │
11|        ││  ╰─ ▶ 󰅩 4: {index: 4, value: 'Item 4', nested: {...           │
12|        ││  ╰─ ▶ 󰅩 5: {index: 5, value: 'Item 5', nested: {...           │
13|        ││  ╰─ ▶ 󰅩 6: {index: 6, value: 'Item 6', nested: {...           │
14|        ││  ╰─ ▶ 󰅩 7: {index: 7, value: 'Item 7', nested: {...           │
15|        ││  ╰─ ▶ 󰅩 8: {index: 8, value: 'Item 8', nested: {...           │
16|        ││  ╰─ ▶ 󰅩 9: {index: 9, value: 'Item 9', nested: {...           │
17|        ││  ╰─ ▶ 󰅩 10: {index: 10, value: 'Item 10', nested:...          │d1.nest
18| ed2.nes││  ╰─ ▶ 󰅩 11: {index: 11, value: 'Item 11', nested:...          │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               4,22-11       Top
]]


--[[ TERMINAL SNAPSHOT: auto_drill_focus_activated
Size: 24x80
Cursor: [6, 24] (line 6, col 24)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  Local: testDeepNesting                                     │
 5|     // │╰─ ▶ 󰅩 complexObject: {level1: {…}, description: 'Root le...    │
 6|     let│╰─ ▼ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...        │
 7|        ││  ╰─ ▶ 󰅩 0: {index: 0, value: 'Item 0', nested: {...           │
 8|        ││  ╰─ ▼ 󰅩 1: {index: 1, value: 'Item 1', nested: {...           │
 9|        ││  │  ╰─   󰎠 index: 1                                           │
10|        ││  │  ╰─ ▶ 󰅩 nested: {data: 10, more: {…}}                      │
11|        ││  │  ╰─   󰉿 value: "'Item 1'"                                  │
12|        ││  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                              │
13|        ││  ╰─ ▶ 󰅩 2: {index: 2, value: 'Item 2', nested: {...           │
14|        ││  ╰─ ▶ 󰅩 3: {index: 3, value: 'Item 3', nested: {...           │
15|        ││  ╰─ ▶ 󰅩 4: {index: 4, value: 'Item 4', nested: {...           │
16|        ││  ╰─ ▶ 󰅩 5: {index: 5, value: 'Item 5', nested: {...           │
17|        ││  ╰─ ▶ 󰅩 6: {index: 6, value: 'Item 6', nested: {...           │d1.nest
18| ed2.nes││  ╰─ ▶ 󰅩 7: {index: 7, value: 'Item 7', nested: {...           │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               6,25-14       Top
]]


--[[ TERMINAL SNAPSHOT: bidirectional_focus_down
Size: 24x80
Cursor: [7, 26] (line 7, col 26)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  Local: testDeepNesting                                     │
 5|     // │╰─ ▶ 󰅩 complexObject: {level1: {…}, description: 'Root le...    │
 6|     let│╰─ ▼ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...        │
 7|        ││  ╰─ ▶ 󰅩 0: {index: 0, value: 'Item 0', nested: {...           │
 8|        ││  ╰─ ▼ 󰅩 1: {index: 1, value: 'Item 1', nested: {...           │
 9|        ││  │  ╰─   󰎠 index: 1                                           │
10|        ││  │  ╰─ ▶ 󰅩 nested: {data: 10, more: {…}}                      │
11|        ││  │  ╰─   󰉿 value: "'Item 1'"                                  │
12|        ││  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                              │
13|        ││  ╰─ ▶ 󰅩 2: {index: 2, value: 'Item 2', nested: {...           │
14|        ││  ╰─ ▶ 󰅩 3: {index: 3, value: 'Item 3', nested: {...           │
15|        ││  ╰─ ▶ 󰅩 4: {index: 4, value: 'Item 4', nested: {...           │
16|        ││  ╰─ ▶ 󰅩 5: {index: 5, value: 'Item 5', nested: {...           │
17|        ││  ╰─ ▶ 󰅩 6: {index: 6, value: 'Item 6', nested: {...           │d1.nest
18| ed2.nes││  ╰─ ▶ 󰅩 7: {index: 7, value: 'Item 7', nested: {...           │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               7,27-14       Top
]]


--[[ TERMINAL SNAPSHOT: bidirectional_focus_up
Size: 24x80
Cursor: [6, 24] (line 6, col 24)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  Local: testDeepNesting                                     │
 5|     // │╰─ ▶ 󰅩 complexObject: {level1: {…}, description: 'Root le...    │
 6|     let│╰─ ▼ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...        │
 7|        ││  ╰─ ▶ 󰅩 0: {index: 0, value: 'Item 0', nested: {...           │
 8|        ││  ╰─ ▼ 󰅩 1: {index: 1, value: 'Item 1', nested: {...           │
 9|        ││  │  ╰─   󰎠 index: 1                                           │
10|        ││  │  ╰─ ▶ 󰅩 nested: {data: 10, more: {…}}                      │
11|        ││  │  ╰─   󰉿 value: "'Item 1'"                                  │
12|        ││  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                              │
13|        ││  ╰─ ▶ 󰅩 2: {index: 2, value: 'Item 2', nested: {...           │
14|        ││  ╰─ ▶ 󰅩 3: {index: 3, value: 'Item 3', nested: {...           │
15|        ││  ╰─ ▶ 󰅩 4: {index: 4, value: 'Item 4', nested: {...           │
16|        ││  ╰─ ▶ 󰅩 5: {index: 5, value: 'Item 5', nested: {...           │
17|        ││  ╰─ ▶ 󰅩 6: {index: 6, value: 'Item 6', nested: {...           │d1.nest
18| ed2.nes││  ╰─ ▶ 󰅩 7: {index: 7, value: 'Item 7', nested: {...           │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               6,25-14       Top
]]

--[[ TERMINAL SNAPSHOT: hierarchical_focus_deep
Size: 24x80
Cursor: [5, 24] (line 5, col 24)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  Local: testDeepNesting                                     │
 5|     // │╰─ ▼ 󰅩 complexObject: {level1: {…}, description: 'Root le...    │
 6|     let││  ╰─   󰉿 description: "'Root level'"                           │
 7|        ││  ╰─ ▼ 󰅩 level1: {nested1: {…}, data: 'Level 1 data'}          │
 8|        ││  │  ╰─   󰉿 data: "'Level 1 data'"                             │
 9|        ││  │  ╰─ ▶ 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}      │
10|        ││  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                              │
11|        ││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
12|        │╰─ ▼ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...        │
13|        ││  ╰─ ▶ 󰅩 0: {index: 0, value: 'Item 0', nested: {...           │
14|        ││  ╰─ ▼ 󰅩 1: {index: 1, value: 'Item 1', nested: {...           │
15|        ││  │  ╰─   󰎠 index: 1                                           │
16|        ││  │  ╰─ ▶ 󰅩 nested: {data: 10, more: {…}}                      │
17|        ││  │  ╰─   󰉿 value: "'Item 1'"                                  │d1.nest
18| ed2.nes││  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                              │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               5,25-14       Top
]]

--[[ TERMINAL SNAPSHOT: focus_hjkl_left
Size: 24x80
Cursor: [5, 23] (line 5, col 23)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  Local: testDeepNesting                                     │
 5|     // │╰─ ▼ 󰅩 complexObject: {level1: {…}, description: 'Root le...    │
 6|     let││  ╰─   󰉿 description: "'Root level'"                           │
 7|        ││  ╰─ ▼ 󰅩 level1: {nested1: {…}, data: 'Level 1 data'}          │
 8|        ││  │  ╰─   󰉿 data: "'Level 1 data'"                             │
 9|        ││  │  ╰─ ▶ 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}      │
10|        ││  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                              │
11|        ││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
12|        │╰─ ▼ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...        │
13|        ││  ╰─ ▶ 󰅩 0: {index: 0, value: 'Item 0', nested: {...           │
14|        ││  ╰─ ▼ 󰅩 1: {index: 1, value: 'Item 1', nested: {...           │
15|        ││  │  ╰─   󰎠 index: 1                                           │
16|        ││  │  ╰─ ▶ 󰅩 nested: {data: 10, more: {…}}                      │
17|        ││  │  ╰─   󰉿 value: "'Item 1'"                                  │d1.nest
18| ed2.nes││  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                              │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               5,24-13       Top
]]

--[[ TERMINAL SNAPSHOT: focus_hjkl_right
Size: 24x80
Cursor: [5, 24] (line 5, col 24)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  Local: testDeepNesting                                     │
 5|     // │╰─ ▼ 󰅩 complexObject: {level1: {…}, description: 'Root le...    │
 6|     let││  ╰─   󰉿 description: "'Root level'"                           │
 7|        ││  ╰─ ▼ 󰅩 level1: {nested1: {…}, data: 'Level 1 data'}          │
 8|        ││  │  ╰─   󰉿 data: "'Level 1 data'"                             │
 9|        ││  │  ╰─ ▶ 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}      │
10|        ││  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                              │
11|        ││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
12|        │╰─ ▼ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...        │
13|        ││  ╰─ ▶ 󰅩 0: {index: 0, value: 'Item 0', nested: {...           │
14|        ││  ╰─ ▼ 󰅩 1: {index: 1, value: 'Item 1', nested: {...           │
15|        ││  │  ╰─   󰎠 index: 1                                           │
16|        ││  │  ╰─ ▶ 󰅩 nested: {data: 10, more: {…}}                      │
17|        ││  │  ╰─   󰉿 value: "'Item 1'"                                  │d1.nest
18| ed2.nes││  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                              │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               5,25-14       Top
]]

--[[ TERMINAL SNAPSHOT: true_hierarchical_focus
Size: 24x80
Cursor: [7, 29] (line 7, col 29)
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
11|        ││  │  │  ╰─ ▶ 󰅩 nested2: {nested3: {…}, array: Array(5)}        │
12|        ││  │  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                           │
13|        ││  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                              │
14|        ││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
15|        │╰─ ▼ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...        │
16|        ││  ╰─ ▶ 󰅩 0: {index: 0, value: 'Item 0', nested: {...           │
17|        ││  ╰─ ▼ 󰅩 1: {index: 1, value: 'Item 1', nested: {...           │d1.nest
18| ed2.nes││  │  ╰─   󰎠 index: 1                                           │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               7,30-17       Top
]]

--[[ TERMINAL SNAPSHOT: focus_mode_exit
Size: 24x80
Cursor: [7, 29] (line 7, col 29)
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
11|        ││  │  │  ╰─ ▶ 󰅩 nested2: {nested3: {…}, array: Array(5)}        │
12|        ││  │  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                           │
13|        ││  │  ╰─ ▶ 󰅩 [{Prototype}]: Object                              │
14|        ││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
15|        │╰─ ▼ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...        │
16|        ││  ╰─ ▶ 󰅩 0: {index: 0, value: 'Item 0', nested: {...           │
17|        ││  ╰─ ▼ 󰅩 1: {index: 1, value: 'Item 1', nested: {...           │d1.nest
18| ed2.nes││  │  ╰─   󰎠 index: 1                                           │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 7,1            Top
24|                                                               7,30-17       Top
]]

--[[ TERMINAL SNAPSHOT: focus_mode_reentry_verification
Size: 24x80
Cursor: [1, 9] (line 1, col 9)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  Local: testDeepNesting                                     │
 5|     // │╰─ ▼ 󰅩 complexObject: {level1: {…}, description: 'Root le...    │
 6|     let│╰─ ▼ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...        │
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