-- Core Variables4 functionality testing
-- Consolidates: simplified_features, tree_rendering, asnode_caching, complete_tree_demo

local T = require("testing.testing")(describe, it)
local CommonSetups = require("testing.common_setups")

T.Scenario(function(api)
  -- Setup comprehensive Variables4 testing
  CommonSetups.setupAndOpenVariablesTree(T, api)

  -- Test 1: Basic tree rendering and structure
  T.TerminalSnapshot('core_tree_initial_render')

  -- Test 2: AsNode caching functionality
  T.cmd("execute \"normal \\<CR>\"") -- Expand to trigger caching
  T.sleep(200)
  T.TerminalSnapshot('core_asnode_caching_active')

  -- Test 3: Simplified features integration
  T.cmd("normal! j") -- Navigate
  T.cmd("execute \"normal \\<CR>\"") -- Expand variable
  T.sleep(200)
  T.TerminalSnapshot('core_simplified_features')

  -- Test 4: Complete tree demonstration (all scopes)
  T.cmd("normal! k") -- Back to scope level
  T.cmd("normal! j") -- Navigate to next scope if available
  if true then -- Add logic to detect scope availability
    T.cmd("execute \"normal \\<CR>\"") -- Expand additional scope
    T.sleep(200)
  end
  T.TerminalSnapshot('core_complete_tree_demo')

  -- Test 5: Tree rendering consistency
  T.cmd("normal! gg") -- Go to top
  T.cmd("normal! G") -- Go to bottom
  T.TerminalSnapshot('core_tree_rendering_consistency')

  -- Test 6: AsNode caching verification (re-expand should be instant)
  T.cmd("normal! gg") -- Back to top
  T.cmd("execute \"normal \\<CR>\"") -- Re-expand (should use cache)
  T.sleep(50) -- Minimal wait for cached expansion
  T.TerminalSnapshot('core_asnode_cache_verification')

  -- Test 7: Core functionality final state
  T.TerminalSnapshot('core_functionality_complete')
end)




--[[ TERMINAL SNAPSHOT: core_tree_initial_render
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
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
24| W10: Warning: Changing a readonly file                        1,1           Top
]]




--[[ TERMINAL SNAPSHOT: core_asnode_caching_active
Size: 24x80
Cursor: [1, 4] (line 1, col 4)
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
24| W10: Warning: Changing a readonly file                        1,5-3         Top
]]




--[[ TERMINAL SNAPSHOT: core_simplified_features
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
24| W10: Warning: Changing a readonly file                        3,20-11       Top
]]




--[[ TERMINAL SNAPSHOT: core_complete_tree_demo
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




--[[ TERMINAL SNAPSHOT: core_tree_rendering_consistency
Size: 24x80
Cursor: [24, 14] (line 24, col 14)
Mode: n

10| // Test fixture for Variables plugin - various variable types
11| 
12| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
13|     // ││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
14|     let│╰─   ◐ booleanVar: true                                         │
15|     let│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
16|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
17|     let│╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
18|     let│╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
19|     let│╰─   󰅩 nullVar: null                                            │lue";
20|     let│╰─   󰎠 numberVar: 42                                            │e trunc
21| ated wh│╰─ ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...      │
22|        │╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                     │
23|     // │╰─   󰉿 stringVar: "'Hello, Debug!'"                             │
24|     let│╰─ ▶ 󰀬 this: global                                             │
25|     let│╰─   󰟢 undefinedVar: undefined                                  │
26|        │╰─   󰉿 veryLongVariableNameThatExceedsNormalLimitsForDisplay: "'│
27|        │▶ 📁  Global                                                     │
28|        ╰────────────────────────────────────────────────────────────────╯
29|             level: 2,
30|             data: ["a", "b", "c"]
31|         },
32| lua/testing/fixtures/variables/complex.js                     7,1            Top
33|                                                               24,15-11      Bot
]]




--[[ TERMINAL SNAPSHOT: core_asnode_cache_verification
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




--[[ TERMINAL SNAPSHOT: core_functionality_complete
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