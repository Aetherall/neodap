-- Comprehensive navigation testing for Variables4
-- Consolidates all navigation tests into a single comprehensive test

local T = require("testing.testing")(describe, it)
local CommonSetups = require("testing.common_setups")

T.Scenario(function(api)
  -- Setup navigation testing
  CommonSetups.setupNavigationTest(T, api)

  -- Test 1: Basic hjkl navigation
  T.TerminalSnapshot('navigation_initial')
  
  T.cmd("normal! j") -- Down
  T.TerminalSnapshot('navigation_j_down')
  
  T.cmd("normal! k") -- Up
  T.TerminalSnapshot('navigation_k_up')
  
  T.cmd("normal! h") -- Left (collapse)
  T.TerminalSnapshot('navigation_h_left')
  
  T.cmd("normal! l") -- Right (expand)
  T.sleep(200)
  T.TerminalSnapshot('navigation_l_right')

  -- Test 2: Enhanced navigation with search
  T.cmd("/objectVar") -- Search navigation
  T.TerminalSnapshot('navigation_search')

  -- Test 3: Viewport navigation (scrolling)
  for i = 1, 5 do
    T.cmd("normal! j") -- Navigate down multiple times
  end
  T.TerminalSnapshot('navigation_viewport_scroll')

  -- Test 4: Bidirectional focus navigation (combine with navigation)
  T.cmd("execute \"normal \\<CR>\"") -- Enter focus
  T.sleep(200)
  T.cmd("normal! j") -- Navigate in focus
  T.TerminalSnapshot('navigation_bidirectional_focus')

  -- Test 5: Separated navigation behavior (different contexts)
  T.cmd("normal! q") -- Exit to main view
  T.sleep(200)
  T.cmd("normal! j") -- Navigate in main context
  T.TerminalSnapshot('navigation_separated_context')

  -- Test 6: Navigation fixes verification (edge cases)
  T.cmd("normal! gg") -- Go to top
  T.cmd("normal! k") -- Try to go above top
  T.TerminalSnapshot('navigation_edge_case_top')
  
  T.cmd("normal! G") -- Go to bottom
  T.cmd("normal! j") -- Try to go below bottom
  T.TerminalSnapshot('navigation_edge_case_bottom')

  -- Test 7: Simplified hjkl navigation (verify all combinations)
  T.cmd("normal! gg") -- Reset to top
  T.cmd("normal! jjj") -- Multiple down
  T.cmd("normal! hhh") -- Multiple left
  T.cmd("normal! lll") -- Multiple right
  T.sleep(500)
  T.TerminalSnapshot('navigation_simplified_hjkl_complete')

  -- Test 8: Final navigation state verification
  T.TerminalSnapshot('navigation_final_verification')
end)





--[[ TERMINAL SNAPSHOT: navigation_initial
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





--[[ TERMINAL SNAPSHOT: navigation_j_down
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





--[[ TERMINAL SNAPSHOT: navigation_k_up
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





--[[ TERMINAL SNAPSHOT: navigation_h_left
Size: 24x80
Cursor: [3, 12] (line 3, col 12)
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
24|                                                               3,13-7        Top
]]





--[[ TERMINAL SNAPSHOT: navigation_l_right
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


--[[ TERMINAL SNAPSHOT: navigation_search
Size: 24x80
Cursor: [10, 16] (line 10, col 16)
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
24|                                                               10,17-8       Top
]]


--[[ TERMINAL SNAPSHOT: navigation_viewport_scroll
Size: 24x80
Cursor: [15, 14] (line 15, col 14)
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
24|                                                               15,15-8       Top
]]


--[[ TERMINAL SNAPSHOT: navigation_bidirectional_focus
Size: 24x80
Cursor: [16, 11] (line 16, col 11)
Mode: n

 2| // Test fixture for Variables plugin - various variable types
 3| 
 4| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 5|     // │╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                     │
 6|     let│╰─   ◐ booleanVar: true                                         │
 7|     let│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
 8|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
 9|     let│╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
10|     let│╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
11|     let│╰─   󰅩 nullVar: null                                            │lue";
12|     let│╰─   󰎠 numberVar: 42                                            │e trunc
13| ated wh│╰─ ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...      │
14|        │╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                     │
15|     // │╰─   󰉿 stringVar: "'Hello, Debug!'"                             │
16|     let│╰─ ▶ 󰀬 this: global                                             │
17|     let│╰─   󰟢 undefinedVar: undefined                                  │
18|        │╰─   󰉿 veryLongVariableNameThatExceedsNormalLimitsForDisplay: "'│
19|        │▶ 📁  Global                                                     │
20|        ╰────────────────────────────────────────────────────────────────╯
21|             level: 2,
22|             data: ["a", "b", "c"]
23|         },
24| lua/testing/fixtures/variables/complex.js                     7,1            Top
25|                                                               16,12-8       Bot
]]


--[[ TERMINAL SNAPSHOT: navigation_separated_context
Size: 24x80
Cursor: [16, 11] (line 16, col 11)
Mode: n

 2| // Test fixture for Variables plugin - various variable types
 3| 
 4| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 5|     // │╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                     │
 6|     let│╰─   ◐ booleanVar: true                                         │
 7|     let│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
 8|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
 9|     let│╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
10|     let│╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
11|     let│╰─   󰅩 nullVar: null                                            │lue";
12|     let│╰─   󰎠 numberVar: 42                                            │e trunc
13| ated wh│╰─ ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...      │
14|        │╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                     │
15|     // │╰─   󰉿 stringVar: "'Hello, Debug!'"                             │
16|     let│╰─ ▶ 󰀬 this: global                                             │
17|     let│╰─   󰟢 undefinedVar: undefined                                  │
18|        │╰─   󰉿 veryLongVariableNameThatExceedsNormalLimitsForDisplay: "'│
19|        │▶ 📁  Global                                                     │
20|        ╰────────────────────────────────────────────────────────────────╯
21|             level: 2,
22|             data: ["a", "b", "c"]
23|         },
24| lua/testing/fixtures/variables/complex.js                     7,1            Top
25|                                                               16,12-8       Bot
]]


--[[ TERMINAL SNAPSHOT: navigation_edge_case_top
Size: 24x80
Cursor: [1, 11] (line 1, col 11)
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
24|                                                               1,12-8        Top
]]


--[[ TERMINAL SNAPSHOT: navigation_edge_case_bottom
Size: 24x80
Cursor: [16, 11] (line 16, col 11)
Mode: n

 2| // Test fixture for Variables plugin - various variable types
 3| 
 4| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 5|     // │╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                     │
 6|     let│╰─   ◐ booleanVar: true                                         │
 7|     let│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
 8|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
 9|     let│╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
10|     let│╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
11|     let│╰─   󰅩 nullVar: null                                            │lue";
12|     let│╰─   󰎠 numberVar: 42                                            │e trunc
13| ated wh│╰─ ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...      │
14|        │╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                     │
15|     // │╰─   󰉿 stringVar: "'Hello, Debug!'"                             │
16|     let│╰─ ▶ 󰀬 this: global                                             │
17|     let│╰─   󰟢 undefinedVar: undefined                                  │
18|        │╰─   󰉿 veryLongVariableNameThatExceedsNormalLimitsForDisplay: "'│
19|        │▶ 📁  Global                                                     │
20|        ╰────────────────────────────────────────────────────────────────╯
21|             level: 2,
22|             data: ["a", "b", "c"]
23|         },
24| lua/testing/fixtures/variables/complex.js                     7,1            Top
25|                                                               16,12-8       Bot
]]


--[[ TERMINAL SNAPSHOT: navigation_simplified_hjkl_complete
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


--[[ TERMINAL SNAPSHOT: navigation_final_verification
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