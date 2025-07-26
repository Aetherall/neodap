-- Visual verification test for Variables4 focus mode feature
-- Tests the n-2 parent tree rendering for deep navigation

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables4'))

  -- Set up initial state and launch session with deep_nested fixture
  T.cmd("edit lua/testing/fixtures/variables/deep_nested.js")
  T.cmd("NeodapLaunchClosest Deep Nested [variables]")
  
  -- Wait for session to start and hit breakpoint
  T.sleep(1500)
  T.TerminalSnapshot('session_started')

  -- Open the Variables4 tree popup
  T.cmd("Variables4Tree")
  T.sleep(300) -- Let UI render
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
Cursor: [1, 0] (line 1, col 0)
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
23| lua/testing/fixtures/variables/deep_nested.js                 1,1            Top
24| 
]]




--[[ TERMINAL SNAPSHOT: full_tree_view
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▶ 📁  <93><81> Local: testDeepNesting                            │
 5|     // │▶ 📁  <93><81> Global                                            │
 6|     let│                                                                │
 7|        │                                                                │
 8|        │                                                                │
 9|        │                                                                │
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
23| lua/testing/fixtures/variables/deep_nested.js                 1,1            Top
24|                                                               1,1           All
]]







--[[ TERMINAL SNAPSHOT: complexObject_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  <93><81> Local: testDeepNesting                            │
 5|     // │  ▼ 󰅩 complexObject: {level1: {…}, description: 'Root le...     │
 6|     let│      󰉿 description: "'Root level'"                             │
 7|        │    ▶ 󰅩 level1: {nested1: {…}, data: 'Level 1 data'}            │
 8|        │    ▶ 󰅩 [{Prototype}]: Object                                   │
 9|        │  ▶ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...         │
10|        │  ▶ 󰅩 mixedStructure: {users: {…}}                              │
11|        │  ▶ 󰀬 this: global                                              │
12|        │  ▶ 󰅩 wideObject: {property_0: {…}, property_1: {…}...          │
13|        │▶ 📁  <93><81> Global                                            │
14|        │                                                                │
15|        │                                                                │
16|        │                                                                │
17|        │                                                                │d1.nest
18| ed2.nes│                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 1,1            Top
24|                                                               2,1           All
]]







--[[ TERMINAL SNAPSHOT: deep_navigation_before_focus
Size: 24x80
Cursor: [6, 0] (line 6, col 0)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  <93><81> Local: testDeepNesting                            │
 5|     // │  ▼ 󰅩 complexObject: {level1: {…}, description: 'Root le...     │
 6|     let│      󰉿 description: "'Root level'"                             │
 7|        │    ▼ 󰅩 level1: {nested1: {…}, data: 'Level 1 data'}            │
 8|        │        󰉿 data: "'Level 1 data'"                                │
 9|        │      ▼ 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}         │
10|        │          󰉿 info: "'Level 2 info'"                              │
11|        │        ▶ 󰅩 nested2: {nested3: {…}, array: Array(5)}            │
12|        │        ▶ 󰅩 [{Prototype}]: Object                               │
13|        │      ▶ 󰅩 [{Prototype}]: Object                                 │
14|        │    ▶ 󰅩 [{Prototype}]: Object                                   │
15|        │  ▶ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...         │
16|        │  ▶ 󰅩 mixedStructure: {users: {…}}                              │
17|        │  ▶ 󰀬 this: global                                              │d1.nest
18| ed2.nes│  ▶ 󰅩 wideObject: {property_0: {…}, property_1: {…}...          │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 1,1            Top
24|                                                               6,1           Top
]]







--[[ TERMINAL SNAPSHOT: nested4_selected_full_tree
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  <93><81> Local: testDeepNesting                            │
 5|     // │  ▼ 󰅩 complexObject: {level1: {…}, description: 'Root le...     │
 6|     let│      󰉿 description: "'Root level'"                             │
 7|        │    ▼ 󰅩 level1: {nested1: {…}, data: 'Level 1 data'}            │
 8|        │        󰉿 data: "'Level 1 data'"                                │
 9|        │      ▼ 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}         │
10|        │          󰉿 info: "'Level 2 info'"                              │
11|        │        ▶ 󰅩 nested2: {nested3: {…}, array: Array(5)}            │
12|        │        ▶ 󰅩 [{Prototype}]: Object                               │
13|        │      ▶ 󰅩 [{Prototype}]: Object                                 │
14|        │    ▶ 󰅩 [{Prototype}]: Object                                   │
15|        │  ▶ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...         │
16|        │  ▶ 󰅩 mixedStructure: {users: {…}}                              │
17|        │  ▶ 󰀬 this: global                                              │d1.nest
18| ed2.nes│  ▶ 󰅩 wideObject: {property_0: {…}, property_1: {…}...          │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 1,1            Top
24|                                                               7,1           Top
]]






--[[ TERMINAL SNAPSHOT: focus_mode_entered
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 󰅩 level1: {nested1: {…}, data: 'Level 1 data'}                │
 5|     // │    󰉿 data: "'Level 1 data'"                                    │
 6|     let│  ▼ 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}             │
 7|        │      󰉿 info: "'Level 2 info'"                                  │
 8|        │    ▶ 󰅩 nested2: {nested3: {…}, array: Array(5)}                │
 9|        │    ▶ 󰅩 [{Prototype}]: Object                                   │
10|        │  ▶ 󰅩 [{Prototype}]: Object                                     │
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
23| lua/testing/fixtures/variables/deep_nested.js                 1,1            Top
24| Focused on: 󰅩 level1: {nested1: {…}, data: 'Level 1 data'}    7,1           All
]]






--[[ TERMINAL SNAPSHOT: focus_mode_navigation
Size: 24x80
Cursor: [8, 0] (line 8, col 0)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 󰅩 level1: {nested1: {…}, data: 'Level 1 data'}                │
 5|     // │    󰉿 data: "'Level 1 data'"                                    │
 6|     let│  ▼ 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}             │
 7|        │      󰉿 info: "'Level 2 info'"                                  │
 8|        │    ▶ 󰅩 nested2: {nested3: {…}, array: Array(5)}                │
 9|        │    ▶ 󰅩 [{Prototype}]: Object                                   │
10|        │  ▼ 󰅩 [{Prototype}]: Object                                     │
11|        │      󰅩 __proto__: null                                         │
12|        │    ▶ 󰊕 __defineGetter__: ƒ __defineGetter__()                  │
13|        │    ▶ 󰊕 __defineSetter__: ƒ __defineSetter__()                  │
14|        │    ▶ 󰊕 __lookupGetter__: ƒ __lookupGetter__()                  │
15|        │    ▶ 󰊕 __lookupSetter__: ƒ __lookupSetter__()                  │
16|        │    ▶ 󰊕 constructor: ƒ Object()                                 │
17|        │    ▶ 󰊕 hasOwnProperty: ƒ hasOwnProperty()                      │d1.nest
18| ed2.nes│    ▶ 󰊕 isPrototypeOf: ƒ isPrototypeOf()                        │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 1,1            Top
24| Focused on: 󰅩 level1: {nested1: {…}, data: 'Level 1 data'}    8,1           Top
]]






--[[ TERMINAL SNAPSHOT: focus_mode_exited
Size: 24x80
Cursor: [8, 0] (line 8, col 0)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  <93><81> Local: testDeepNesting                            │
 5|     // │  ▼ 󰅩 complexObject: {level1: {…}, description: 'Root le...     │
 6|     let│      󰉿 description: "'Root level'"                             │
 7|        │    ▼ 󰅩 level1: {nested1: {…}, data: 'Level 1 data'}            │
 8|        │        󰉿 data: "'Level 1 data'"                                │
 9|        │      ▼ 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}         │
10|        │          󰉿 info: "'Level 2 info'"                              │
11|        │        ▶ 󰅩 nested2: {nested3: {…}, array: Array(5)}            │
12|        │        ▶ 󰅩 [{Prototype}]: Object                               │
13|        │      ▼ 󰅩 [{Prototype}]: Object                                 │
14|        │          󰅩 __proto__: null                                     │
15|        │        ▶ 󰊕 __defineGetter__: ƒ __defineGetter__()              │
16|        │        ▶ 󰊕 __defineSetter__: ƒ __defineSetter__()              │
17|        │        ▶ 󰊕 __lookupGetter__: ƒ __lookupGetter__()              │d1.nest
18| ed2.nes│        ▶ 󰊕 __lookupSetter__: ƒ __lookupSetter__()              │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 1,1            Top
24| Reset to full tree view                                       8,1           Top
]]





--[[ TERMINAL SNAPSHOT: very_deep_selection
Size: 24x80
Cursor: [10, 0] (line 10, col 0)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  <93><81> Local: testDeepNesting                            │
 5|     // │  ▼ 󰅩 complexObject: {level1: {…}, description: 'Root le...     │
 6|     let│      󰉿 description: "'Root level'"                             │
 7|        │    ▼ 󰅩 level1: {nested1: {…}, data: 'Level 1 data'}            │
 8|        │        󰉿 data: "'Level 1 data'"                                │
 9|        │      ▼ 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}         │
10|        │          󰉿 info: "'Level 2 info'"                              │
11|        │        ▶ 󰅩 nested2: {nested3: {…}, array: Array(5)}            │
12|        │        ▼ 󰅩 [{Prototype}]: Object                               │
13|        │          ▶ 󰊕 __proto__: ƒ __proto__()                          │
14|        │          ▶ 󰊕 __defineGetter__: ƒ __defineGetter__()            │
15|        │          ▶ 󰊕 __defineSetter__: ƒ __defineSetter__()            │
16|        │          ▶ 󰊕 __lookupGetter__: ƒ __lookupGetter__()            │
17|        │          ▶ 󰊕 __lookupSetter__: ƒ __lookupSetter__()            │d1.nest
18| ed2.nes│          ▶ 󰊕 constructor: ƒ Object()                           │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 1,1            Top
24| Reset to full tree view                                       10,1          Top
]]






--[[ TERMINAL SNAPSHOT: focus_mode_very_deep
Size: 24x80
Cursor: [10, 0] (line 10, col 0)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}               │
 5|     // │    󰉿 info: "'Level 2 info'"                                    │
 6|     let│  ▶ 󰅩 nested2: {nested3: {…}, array: Array(5)}                  │
 7|        │  ▼ 󰅩 [{Prototype}]: Object                                     │
 8|        │    ▶ 󰊕 __proto__: ƒ __proto__()                                │
 9|        │    ▶ 󰊕 __defineGetter__: ƒ __defineGetter__()                  │
10|        │    ▶ 󰊕 __defineSetter__: ƒ __defineSetter__()                  │
11|        │    ▶ 󰊕 __lookupGetter__: ƒ __lookupGetter__()                  │
12|        │    ▶ 󰊕 __lookupSetter__: ƒ __lookupSetter__()                  │
13|        │    ▶ 󰊕 constructor: ƒ Object()                                 │
14|        │    ▶ 󰊕 hasOwnProperty: ƒ hasOwnProperty()                      │
15|        │    ▶ 󰊕 isPrototypeOf: ƒ isPrototypeOf()                        │
16|        │    ▶ 󰊕 propertyIsEnumerable: ƒ propertyIsEnumerable()          │
17|        │    ▶ 󰊕 toLocaleString: ƒ toLocaleString()                      │d1.nest
18| ed2.nes│    ▶ 󰊕 toString: ƒ toString()                                  │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 1,1            Top
24| Focused on: 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}   10,1          Top
]]





--[[ TERMINAL SNAPSHOT: help_with_focus_mode
Size: 24x80
Cursor: [9, 0] (line 9, col 0)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}               │
 5|     // │    󰉿 info: "'Level 2 info'"                                    │
 6|     let│  ▶ 󰅩 nested2: {nested3: {…}, array: Array(5)}                  │
 7|        │  ▼ 󰅩 [{Prototype}]: Object                                     │
 8|        │    ▶ 󰊕 __proto__: ƒ __proto__()                                │
 9|        │    ▶ 󰊕 __defineGetter__: ƒ __defineGetter__()                  │
10|        │    ▶ 󰊕 __defineSetter__: ƒ __defineSetter__()                  │
11|        │    ▶ 󰊕 __lookupGetter__: ƒ __lookupGetter__()                  │
12|        │    ▶ 󰊕 __lookupSetter__: ƒ __lookupSetter__()                  │
13|        │    ▶ 󰊕 constructor: ƒ Object()                                 │
14|        │    ▶ 󰊕 hasOwnProperty: ƒ hasOwnProperty()                      │
15|        │    ▶ 󰊕 isPrototypeOf: ƒ isPrototypeOf()                        │
16|        │    ▶ 󰊕 propertyIsEnumerable: ƒ propertyIsEnumerable()          │
17|        │    ▶ 󰊕 toLocaleString: ƒ toLocaleString()                      │d1.nest
18| ed2.nes│    ▶ 󰊕 toString: ƒ toString()                                  │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 1,1            Top
24|                                                               9,1           Top
]]







--[[ TERMINAL SNAPSHOT: local_scope_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  <93><81> Local: testDeepNesting                            │
 5|     // │  ▶ 󰅩 complexObject: {level1: {…}, description: 'Root le...     │
 6|     let│  ▶ 󰅪 deepArray: (50) [{…}, {…}, {…}, {…}, {<e2><80>...         │
 7|        │  ▶ 󰅩 mixedStructure: {users: {…}}                              │
 8|        │  ▶ 󰀬 this: global                                              │
 9|        │  ▶ 󰅩 wideObject: {property_0: {…}, property_1: {…}...          │
10|        │▶ 📁  <93><81> Global                                            │
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
23| lua/testing/fixtures/variables/deep_nested.js                 1,1            Top
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: focus_already_active
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 📁  <93><81> Global                                            │
 5|     // │  ▶ 󰊕 AbortController: ƒ () { mod ??= requir...                 │
 6|     let│  ▶ 󰊕 AbortSignal: ƒ () { mod ??= requir...                     │
 7|        │  ▶ 󰊕 atob: ƒ () { mod ??= requir...                            │
 8|        │  ▶ 󰊕 Blob: ƒ () { mod ??= requir...                            │
 9|        │  ▶ 󰊕 BroadcastChannel: ƒ () { mod ??= requir...                │
10|        │  ▶ 󰊕 btoa: ƒ () { mod ??= requir...                            │
11|        │  ▶ 󰊕 Buffer: ƒ get() { return _Buf...                          │
12|        │  ▶ 󰊕 ByteLengthQueuingStrategy: ƒ () { mod ??= requir...       │
13|        │  ▶ 󰊕 clearImmediate: ƒ clearImmediate(immediate) { if (!i...   │
14|        │  ▶ 󰊕 clearInterval: ƒ clearInterval(timer) { // clearTim...    │
15|        │  ▶ 󰊕 clearTimeout: ƒ clearTimeout(timer) { if (timer &&...     │
16|        │  ▶ 󰊕 CompressionStream: ƒ () { mod ??= requir...               │
17|        │  ▶ 󰊕 CountQueuingStrategy: ƒ () { mod ??= requir...            │d1.nest
18| ed2.nes│  ▶ 󰊕 crypto: ƒ () { if (check !== ...                          │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 1,1            Top
24| Already in focus mode - use 'r' to reset first                3,1           Top
]]


--[[ TERMINAL SNAPSHOT: re_focus_test
Size: 24x80
Cursor: [9, 0] (line 9, col 0)
Mode: n

 1| // Test fixture for Variables plugin - deeply nested structures for visibility t
 2| esting
 3|        ╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4| functio│▼ 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}               │
 5|     // │    󰉿 info: "'Level 2 info'"                                    │
 6|     let│  ▶ 󰅩 nested2: {nested3: {…}, array: Array(5)}                  │
 7|        │  ▼ 󰅩 [{Prototype}]: Object                                     │
 8|        │    ▶ 󰊕 __proto__: ƒ __proto__()                                │
 9|        │    ▶ 󰊕 __defineGetter__: ƒ __defineGetter__()                  │
10|        │    ▶ 󰊕 __defineSetter__: ƒ __defineSetter__()                  │
11|        │    ▶ 󰊕 __lookupGetter__: ƒ __lookupGetter__()                  │
12|        │    ▶ 󰊕 __lookupSetter__: ƒ __lookupSetter__()                  │
13|        │    ▶ 󰊕 constructor: ƒ Object()                                 │
14|        │    ▶ 󰊕 hasOwnProperty: ƒ hasOwnProperty()                      │
15|        │    ▶ 󰊕 isPrototypeOf: ƒ isPrototypeOf()                        │
16|        │    ▶ 󰊕 propertyIsEnumerable: ƒ propertyIsEnumerable()          │
17|        │    ▶ 󰊕 toLocaleString: ƒ toLocaleString()                      │d1.nest
18| ed2.nes│    ▶ 󰊕 toString: ƒ toString()                                  │
19|        ╰────────────────────────────────────────────────────────────────╯
20|                                 },
21|                                 siblings: ["a", "b", "c"]
22|                             },
23| lua/testing/fixtures/variables/deep_nested.js                 1,1            Top
24| Re-focused on: 󰅩 nested1: {nested2: {…}, info: 'Level 2 info'}9,1           Top
]]