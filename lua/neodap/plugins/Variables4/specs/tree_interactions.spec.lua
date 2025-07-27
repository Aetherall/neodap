-- Tree interaction testing for Variables4
-- Consolidates: collapse_behavior, jump_up_collapse, interactive_expansion

local T = require("testing.testing")(describe, it)
local CommonSetups = require("testing.common_setups")

T.Scenario(function(api)
  -- Setup for tree interaction testing
  CommonSetups.setupAndOpenVariablesTree(T, api)

  -- Test 1: Basic expand/collapse behavior
  T.TerminalSnapshot('interactions_initial_state')
  
  T.cmd("execute \"normal \\<CR>\"") -- Expand
  T.sleep(200)
  T.TerminalSnapshot('interactions_expand_basic')
  
  T.cmd("execute \"normal \\<CR>\"") -- Collapse
  T.sleep(200)
  T.TerminalSnapshot('interactions_collapse_basic')

  -- Test 2: Interactive expansion (step-by-step)
  T.cmd("execute \"normal \\<CR>\"") -- Re-expand
  T.sleep(200)
  T.cmd("normal! j") -- Navigate to child
  T.cmd("execute \"normal \\<CR>\"") -- Expand child
  T.sleep(200)
  T.TerminalSnapshot('interactions_interactive_expansion')

  -- Test 3: Jump up collapse behavior  
  T.cmd("normal! j") -- Navigate deeper
  T.cmd("execute \"normal \\<CR>\"") -- Expand deeper item
  T.sleep(200)
  T.TerminalSnapshot('interactions_deep_expanded')

  -- Now test jump up collapse (going up levels)
  T.cmd("normal! k") -- Move up
  T.cmd("execute \"normal \\<CR>\"") -- Collapse parent
  T.sleep(200)
  T.TerminalSnapshot('interactions_jump_up_collapse')

  -- Test 4: Complex collapse behavior patterns
  -- Re-expand everything for complex test
  T.cmd("execute \"normal \\<CR>\"") -- Expand parent
  T.sleep(200)
  T.cmd("normal! j") -- Navigate down
  T.cmd("execute \"normal \\<CR>\"") -- Expand child
  T.sleep(200)
  T.cmd("normal! j") -- Navigate to grandchild
  T.cmd("execute \"normal \\<CR>\"") -- Expand grandchild
  T.sleep(200)
  T.TerminalSnapshot('interactions_complex_expanded')

  -- Test various collapse scenarios
  T.cmd("normal! kk") -- Navigate up two levels
  T.cmd("execute \"normal \\<CR>\"") -- Collapse from middle
  T.sleep(200)
  T.TerminalSnapshot('interactions_complex_collapse')

  -- Test 5: Interactive expansion edge cases
  T.cmd("normal! G") -- Go to bottom
  T.cmd("execute \"normal \\<CR>\"") -- Try to expand at bottom
  T.sleep(100)
  T.TerminalSnapshot('interactions_edge_case_bottom')

  T.cmd("normal! gg") -- Go to top
  T.cmd("execute \"normal \\<CR>\"") -- Expand at top
  T.sleep(200)
  T.TerminalSnapshot('interactions_edge_case_top')

  -- Test 6: Final tree interaction verification
  T.TerminalSnapshot('interactions_final_verification')
end)


--[[ TERMINAL SNAPSHOT: interactions_initial_state
Size: 24x80
Cursor: [1, 9] (line 1, col 9)
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
24|                                                               1,10-6        Top
]]


--[[ TERMINAL SNAPSHOT: interactions_expand_basic
Size: 24x80
Cursor: [2, 16] (line 2, col 16)
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
24|                                                               2,17-8        Top
]]


--[[ TERMINAL SNAPSHOT: interactions_collapse_basic
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


--[[ TERMINAL SNAPSHOT: interactions_interactive_expansion
Size: 24x80
Cursor: [4, 19] (line 4, col 19)
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
24|                                                               4,20-11       Top
]]


--[[ TERMINAL SNAPSHOT: interactions_deep_expanded
Size: 24x80
Cursor: [5, 19] (line 5, col 19)
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
24|                                                               5,20-11       Top
]]


--[[ TERMINAL SNAPSHOT: interactions_jump_up_collapse
Size: 24x80
Cursor: [4, 19] (line 4, col 19)
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
24|                                                               4,20-11       Top
]]


--[[ TERMINAL SNAPSHOT: interactions_complex_expanded
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


--[[ TERMINAL SNAPSHOT: interactions_complex_collapse
Size: 24x80
Cursor: [4, 19] (line 4, col 19)
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
24|                                                               4,20-11       Top
]]


--[[ TERMINAL SNAPSHOT: interactions_edge_case_bottom
Size: 24x80
Cursor: [25, 16] (line 25, col 16)
Mode: n

11| // Test fixture for Variables plugin - various variable types
12| 
13| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
14|     // │╰─   ◐ booleanVar: true                                         │
15|     let│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
16|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
17|     let│╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
18|     let│╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
19|     let│╰─   󰅩 nullVar: null                                            │
20|     let│╰─   󰎠 numberVar: 42                                            │lue";
21|     let│╰─ ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...      │e trunc
22| ated wh│╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                     │
23|        │╰─   󰉿 stringVar: "'Hello, Debug!'"                             │
24|     // │╰─ ▶ 󰀬 this: global                                             │
25|     let│╰─   󰟢 undefinedVar: undefined                                  │
26|     let│╰─   󰉿 veryLongVariableNameThatExceedsNormalLimitsForDisplay: "'│
27|        │▼ 📁  Global                                                     │
28|        │╰─ ▶ 󰊕 AbortController: ƒ () { mod ??= requir...                │
29|        ╰────────────────────────────────────────────────────────────────╯
30|             level: 2,
31|             data: ["a", "b", "c"]
32|         },
33| lua/testing/fixtures/variables/complex.js                     7,1            Top
34|                                                               25,17-8        7%
]]


--[[ TERMINAL SNAPSHOT: interactions_edge_case_top
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


--[[ TERMINAL SNAPSHOT: interactions_final_verification
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