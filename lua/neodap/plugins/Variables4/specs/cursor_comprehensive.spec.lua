-- Comprehensive cursor behavior testing for Variables4
-- Consolidates all cursor-related tests into a single comprehensive test

local T = require("testing.testing")(describe, it)
local CommonSetups = require("testing.common_setups")

T.Scenario(function(api)
  -- Setup debugging session once for all cursor tests
  CommonSetups.setupAndOpenVariablesTree(T, api)

  -- Test 1: Basic cursor positioning
  T.TerminalSnapshot('initial_cursor_position')

  -- Test 2: Cursor navigation through tree
  T.cmd("normal! j") -- Move down
  T.TerminalSnapshot('cursor_moved_down')
  
  T.cmd("normal! k") -- Move up
  T.TerminalSnapshot('cursor_moved_up')

  -- Test 3: Cursor behavior with expansion
  T.cmd("execute \"normal \\<CR>\"") -- Expand node
  T.sleep(200)
  T.TerminalSnapshot('cursor_after_expansion')

  -- Test 4: Cursor predictability in deep navigation
  T.cmd("normal! j") -- Navigate to expanded content
  T.cmd("execute \"normal \\<CR>\"") -- Expand child
  T.sleep(200)
  T.TerminalSnapshot('cursor_deep_navigation')

  -- Test 5: Cursor positioning with collapse
  T.cmd("execute \"normal \\<CR>\"") -- Collapse
  T.sleep(200)
  T.TerminalSnapshot('cursor_after_collapse')

  -- Test 6: Cursor name positioning (verify cursor on variable names)
  T.cmd("normal! j") -- Move to a variable
  T.TerminalSnapshot('cursor_on_variable_name')

  -- Test 7: Cursor drill-down behavior
  T.cmd("/objectVar") -- Search for object variable
  T.cmd("execute \"normal \\<CR>\"") -- Expand
  T.sleep(200)
  T.cmd("normal! j") -- Drill down
  T.TerminalSnapshot('cursor_drill_down_complete')

  -- Test 8: Final cursor verification - comprehensive state
  T.TerminalSnapshot('cursor_final_state_verification')
end)







--[[ TERMINAL SNAPSHOT: initial_cursor_position
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







--[[ TERMINAL SNAPSHOT: cursor_moved_down
Size: 24x80
Cursor: [2, 11] (line 2, col 11)
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
24|                                                               2,12-6        Top
]]






--[[ TERMINAL SNAPSHOT: cursor_moved_up
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






--[[ TERMINAL SNAPSHOT: cursor_after_expansion
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






--[[ TERMINAL SNAPSHOT: cursor_deep_navigation
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






--[[ TERMINAL SNAPSHOT: cursor_after_collapse
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






--[[ TERMINAL SNAPSHOT: cursor_on_variable_name
Size: 24x80
Cursor: [4, 14] (line 4, col 14)
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
24|                                                               4,15-8        Top
]]



--[[ TERMINAL SNAPSHOT: cursor_drill_down_complete
Size: 24x80
Cursor: [12, 21] (line 12, col 21)
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
13|        │╰─ ▼ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...      │
14|     // ││  ╰─   󰎠 count: 100                                            │
15|     let││  ╰─ ▶ 󰊕 method: ƒ () { return "method"; }                     │
16|     let││  ╰─   󰉿 name: "'Test Object'"                                 │
17|        ││  ╰─ ▶ 󰅩 nested: {level: 2, data: Array(3)}                    │
18|        ││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               12,22-11      Top
]]



--[[ TERMINAL SNAPSHOT: cursor_final_state_verification
Size: 24x80
Cursor: [12, 21] (line 12, col 21)
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
13|        │╰─ ▼ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...      │
14|     // ││  ╰─   󰎠 count: 100                                            │
15|     let││  ╰─ ▶ 󰊕 method: ƒ () { return "method"; }                     │
16|     let││  ╰─   󰉿 name: "'Test Object'"                                 │
17|        ││  ╰─ ▶ 󰅩 nested: {level: 2, data: Array(3)}                    │
18|        ││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               12,22-11      Top
]]