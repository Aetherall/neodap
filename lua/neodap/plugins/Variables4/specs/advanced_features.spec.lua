-- Advanced Variables4 features testing
-- Consolidates: recursive_reference_test, node_duplication_debug, duplication_proper_test

local T = require("testing.testing")(describe, it)
local CommonSetups = require("testing.common_setups")

T.Scenario(function(api)
  -- Test 1: Recursive reference handling
  CommonSetups.setupRecursiveVariables(T, api)
  CommonSetups.openVariablesTree(T)

  T.TerminalSnapshot('advanced_recursive_initial')
  
  -- Expand scope and find recursive object
  T.cmd("execute \"normal \\<CR>\"") -- Expand scope
  T.sleep(200)
  T.cmd("/recursive") -- Search for recursive object
  T.cmd("execute \"normal \\<CR>\"") -- Expand recursive object
  T.sleep(300) -- Allow time for recursive handling
  T.TerminalSnapshot('advanced_recursive_expanded')

  -- Test recursive navigation (should not infinite loop)
  T.cmd("normal! j") -- Navigate into recursive structure
  T.cmd("execute \"normal \\<CR>\"") -- Try to expand recursive reference
  T.sleep(200)
  T.TerminalSnapshot('advanced_recursive_navigation')

  -- Test 2: Node duplication debugging
  -- Switch to complex fixture for duplication testing
  T.cmd("normal! q") -- Close current tree
  T.sleep(200)
  
  CommonSetups.setupAndOpenVariablesTree(T, api)
  
  -- Test node duplication scenarios
  T.cmd("execute \"normal \\<CR>\"") -- Expand
  T.sleep(200)
  T.cmd("normal! j") -- Navigate
  T.cmd("execute \"normal \\<CR>\"") -- Expand child
  T.sleep(200)
  T.TerminalSnapshot('advanced_node_duplication_test')

  -- Collapse and re-expand to test for duplication bugs
  T.cmd("normal! k") -- Go back up
  T.cmd("execute \"normal \\<CR>\"") -- Collapse
  T.sleep(200)
  T.cmd("execute \"normal \\<CR>\"") -- Re-expand
  T.sleep(200)
  T.TerminalSnapshot('advanced_duplication_reexpand')

  -- Test 3: Proper duplication handling verification
  -- Navigate through multiple levels to stress-test duplication handling
  for i = 1, 3 do
    T.cmd("normal! j") -- Navigate down
    T.cmd("execute \"normal \\<CR>\"") -- Expand if possible
    T.sleep(100)
  end
  T.TerminalSnapshot('advanced_duplication_stress_test')

  -- Test collapse behavior with complex tree
  T.cmd("normal! gg") -- Go to top
  T.cmd("execute \"normal \\<CR>\"") -- Collapse all
  T.sleep(200)
  T.TerminalSnapshot('advanced_duplication_collapse_all')

  -- Test 4: Advanced edge cases
  -- Test empty/null value handling
  T.cmd("execute \"normal \\<CR>\"") -- Re-expand to look for edge cases
  T.sleep(200)
  T.cmd("/null\\|undefined\\|empty") -- Search for edge case values
  T.TerminalSnapshot('advanced_edge_cases')

  -- Test 5: Performance with large structures
  -- Rapidly expand/collapse to test performance
  for i = 1, 2 do
    T.cmd("execute \"normal \\<CR>\"") -- Toggle
    T.sleep(50)
  end
  T.TerminalSnapshot('advanced_performance_test')

  -- Test 6: Final advanced features verification
  T.TerminalSnapshot('advanced_features_complete')
end)

--[[ TERMINAL SNAPSHOT: advanced_recursive_initial
Size: 24x80
Cursor: [6, 0] (line 6, col 0)
Mode: n

 1| // Test fixture for Variables plugin - recursive reference testing
 2| 
 3| function testRecursiveReferences() {
 4|     // Create an object that references itself
 5|     let recursiveObj = {
 6|         name: "I reference myself",
 7|         value: 42,
 8|         nested: {
 9|             data: "nested data",
10|             parent: null  // Will be set to recursiveObj
11|         }
12|     };
13| 
14|     // Create the recursive reference
15|     recursiveObj.nested.parent = recursiveObj;
16|     recursiveObj.self = recursiveObj;
17| 
18|     // Create a circular array reference
19|     let circularArray = [1, 2, 3];
20|     circularArray.push(circularArray); // circularArray[3] points to circularArr
21| ay itself
22|     circularArray.self = circularArray;
23| lua/testing/fixtures/variables/recursive.js                   6,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: advanced_recursive_expanded
Size: 24x80
Cursor: [11, 8] (line 11, col 8)
Mode: n

 1| // Test fixture for Variables plugin - recursive reference testing
 2| 
 3| function testRecursiveReferences() {
 4|     // Create an object that references itself
 5|     let recursiveObj = {
 6|         name: "I reference myself",
 7|         value: 42,
 8|         nested: {
 9|             data: "nested data",
10|             parent: null  // Will be set to recursiveObj
11|         }
12|     };
13| 
14|     // Create the recursive reference
15|     recursiveObj.nested.parent = recursiveObj;
16|     recursiveObj.self = recursiveObj;
17| 
18|     // Create a circular array reference
19|     let circularArray = [1, 2, 3];
20|     circularArray.push(circularArray); // circularArray[3] points to circularArr
21| ay itself
22|     circularArray.self = circularArray;
23| lua/testing/fixtures/variables/recursive.js                   11,9           Top
24| 
]]

--[[ TERMINAL SNAPSHOT: advanced_recursive_navigation
Size: 24x80
Cursor: [13, 3] (line 13, col 3)
Mode: n

 1| // Test fixture for Variables plugin - recursive reference testing
 2| 
 3| function testRecursiveReferences() {
 4|     // Create an object that references itself
 5|     let recursiveObj = {
 6|         name: "I reference myself",
 7|         value: 42,
 8|         nested: {
 9|             data: "nested data",
10|             parent: null  // Will be set to recursiveObj
11|         }
12|     };
13| 
14|     // Create the recursive reference
15|     recursiveObj.nested.parent = recursiveObj;
16|     recursiveObj.self = recursiveObj;
17| 
18|     // Create a circular array reference
19|     let circularArray = [1, 2, 3];
20|     circularArray.push(circularArray); // circularArray[3] points to circularArr
21| ay itself
22|     circularArray.self = circularArray;
23| lua/testing/fixtures/variables/recursive.js                   13,4           Top
24| 
]]

--[[ TERMINAL SNAPSHOT: advanced_node_duplication_test
Size: 24x80
Cursor: [3, 13] (line 3, col 13)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  Local: testVariables                                       │
 5|     let│╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                     │
 6|     let│╰─   ◐ booleanVar: true                                         │
 7|     let│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
 8|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
 9|     let│╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
10|     let│╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │lue";
11|     let│╰─   󰅩 nullVar: null                                            │e trunc
12| ated wh│╰─   󰎠 numberVar: 42                                            │
13|        │╰─ ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...      │
14|     // │╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                     │
15|     let│╰─   󰉿 stringVar: "'Hello, Debug!'"                             │
16|     let│╰─ ▶ 󰀬 this: global                                             │
17|        │╰─   󰟢 undefinedVar: undefined                                  │
18|        │╰─   󰉿 veryLongVariableNameThatExceedsNormalLimitsForDisplay: "'│
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               3,14-8        Top
]]

--[[ TERMINAL SNAPSHOT: advanced_duplication_reexpand
Size: 24x80
Cursor: [3, 19] (line 3, col 19)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  Local: testVariables                                       │
 5|     let│╰─ ▼ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                     │
 6|     let││  ╰─   󰎠 0: 1                                                  │
 7|     let││  ╰─   󰎠 1: 2                                                  │
 8|     let││  ╰─   󰎠 2: 3                                                  │
 9|     let││  ╰─   󰉿 3: "'four'"                                           │
10|     let││  ╰─ ▶ 󰅩 4: {five: 5}                                          │lue";
11|     let││  ╰─   󰎠 length: 5                                             │e trunc
12| ated wh││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
13|        ││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
14|     // │╰─   ◐ booleanVar: true                                         │
15|     let│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
16|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
17|        │╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
18|        │╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               3,20-11       Top
]]

--[[ TERMINAL SNAPSHOT: advanced_duplication_stress_test
Size: 24x80
Cursor: [6, 19] (line 6, col 19)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  Local: testVariables                                       │
 5|     let│╰─ ▼ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                     │
 6|     let││  ╰─   󰎠 0: 1                                                  │
 7|     let││  ╰─   󰎠 1: 2                                                  │
 8|     let││  ╰─   󰎠 2: 3                                                  │
 9|     let││  ╰─   󰉿 3: "'four'"                                           │
10|     let││  ╰─ ▶ 󰅩 4: {five: 5}                                          │lue";
11|     let││  ╰─   󰎠 length: 5                                             │e trunc
12| ated wh││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
13|        ││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
14|     // │╰─   ◐ booleanVar: true                                         │
15|     let│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
16|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
17|        │╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
18|        │╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               6,20-11       Top
]]

--[[ TERMINAL SNAPSHOT: advanced_duplication_collapse_all
Size: 24x80
Cursor: [2, 16] (line 2, col 16)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  Local: testVariables                                       │
 5|     let│╰─ ▼ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                     │
 6|     let││  ╰─   󰎠 0: 1                                                  │
 7|     let││  ╰─   󰎠 1: 2                                                  │
 8|     let││  ╰─   󰎠 2: 3                                                  │
 9|     let││  ╰─   󰉿 3: "'four'"                                           │
10|     let││  ╰─ ▶ 󰅩 4: {five: 5}                                          │lue";
11|     let││  ╰─   󰎠 length: 5                                             │e trunc
12| ated wh││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
13|        ││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
14|     // │╰─   ◐ booleanVar: true                                         │
15|     let│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
16|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
17|        │╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
18|        │╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               2,17-8        Top
]]

--[[ TERMINAL SNAPSHOT: advanced_edge_cases
Size: 24x80
Cursor: [16, 17] (line 16, col 17)
Mode: n

 2| // Test fixture for Variables plugin - various variable types
 3| 
 4| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 5|     // │╰─ ▼ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                     │
 6|     let││  ╰─   󰎠 0: 1                                                  │
 7|     let││  ╰─   󰎠 1: 2                                                  │
 8|     let││  ╰─   󰎠 2: 3                                                  │
 9|     let││  ╰─   󰉿 3: "'four'"                                           │
10|     let││  ╰─ ▶ 󰅩 4: {five: 5}                                          │
11|     let││  ╰─   󰎠 length: 5                                             │lue";
12|     let││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │e trunc
13| ated wh││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
14|        │╰─   ◐ booleanVar: true                                         │
15|     // │╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
16|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
17|     let│╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
18|        │╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
19|        │╰─   󰅩 nullVar: null                                            │
20|        ╰────────────────────────────────────────────────────────────────╯
21|             level: 2,
22|             data: ["a", "b", "c"]
23|         },
24| lua/testing/fixtures/variables/complex.js                     7,1            Top
25|                                                               16,18-11      11%
]]

--[[ TERMINAL SNAPSHOT: advanced_performance_test
Size: 24x80
Cursor: [16, 17] (line 16, col 17)
Mode: n

 2| // Test fixture for Variables plugin - various variable types
 3| 
 4| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 5|     // │╰─ ▼ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                     │
 6|     let││  ╰─   󰎠 0: 1                                                  │
 7|     let││  ╰─   󰎠 1: 2                                                  │
 8|     let││  ╰─   󰎠 2: 3                                                  │
 9|     let││  ╰─   󰉿 3: "'four'"                                           │
10|     let││  ╰─ ▶ 󰅩 4: {five: 5}                                          │
11|     let││  ╰─   󰎠 length: 5                                             │lue";
12|     let││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │e trunc
13| ated wh││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
14|        │╰─   ◐ booleanVar: true                                         │
15|     // │╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
16|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
17|     let│╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
18|        │╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
19|        │╰─   󰅩 nullVar: null                                            │
20|        ╰────────────────────────────────────────────────────────────────╯
21|             level: 2,
22|             data: ["a", "b", "c"]
23|         },
24| lua/testing/fixtures/variables/complex.js                     7,1            Top
25|                                                               16,18-11      11%
]]

--[[ TERMINAL SNAPSHOT: advanced_features_complete
Size: 24x80
Cursor: [16, 17] (line 16, col 17)
Mode: n

 2| // Test fixture for Variables plugin - various variable types
 3| 
 4| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 5|     // │╰─ ▼ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                     │
 6|     let││  ╰─   󰎠 0: 1                                                  │
 7|     let││  ╰─   󰎠 1: 2                                                  │
 8|     let││  ╰─   󰎠 2: 3                                                  │
 9|     let││  ╰─   󰉿 3: "'four'"                                           │
10|     let││  ╰─ ▶ 󰅩 4: {five: 5}                                          │
11|     let││  ╰─   󰎠 length: 5                                             │lue";
12|     let││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │e trunc
13| ated wh││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
14|        │╰─   ◐ booleanVar: true                                         │
15|     // │╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
16|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
17|     let│╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
18|        │╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
19|        │╰─   󰅩 nullVar: null                                            │
20|        ╰────────────────────────────────────────────────────────────────╯
21|             level: 2,
22|             data: ["a", "b", "c"]
23|         },
24| lua/testing/fixtures/variables/complex.js                     7,1            Top
25|                                                               16,18-11      11%
]]