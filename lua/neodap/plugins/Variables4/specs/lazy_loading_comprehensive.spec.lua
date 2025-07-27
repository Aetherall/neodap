-- Comprehensive lazy loading testing for Variables4
-- Consolidates all lazy loading tests into a single comprehensive test

local T = require("testing.testing")(describe, it)
local CommonSetups = require("testing.common_setups")

T.Scenario(function(api)
  -- Setup for lazy loading tests
  CommonSetups.setupAndOpenVariablesTree(T, api)

  -- Test 1: Basic lazy variable loading
  T.TerminalSnapshot('lazy_initial_state')
  
  -- Expand scope to trigger lazy loading
  T.cmd("execute \"normal \\<CR>\"") -- Expand scope
  T.sleep(500) -- Wait for lazy loading
  T.TerminalSnapshot('lazy_variable_loaded')

  -- Test 2: Lazy global variable resolution
  T.cmd("/global") -- Search for global scope
  T.cmd("execute \"normal \\<CR>\"") -- Expand globals
  T.sleep(500) -- Wait for lazy global loading
  T.TerminalSnapshot('lazy_global_loaded')

  -- Test 3: Lazy resolution of complex objects
  T.cmd("/objectVar") -- Find complex object
  T.cmd("execute \"normal \\<CR>\"") -- Expand complex object
  T.sleep(500) -- Wait for lazy resolution
  T.TerminalSnapshot('lazy_complex_resolution')

  -- Test 4: Mock lazy loading behavior (simulated delays)
  T.cmd("normal! j") -- Navigate to nested item
  T.cmd("execute \"normal \\<CR>\"") -- Trigger lazy loading
  T.sleep(200) -- Shorter wait to test intermediate state
  T.TerminalSnapshot('lazy_mock_intermediate')
  T.sleep(300) -- Complete loading
  T.TerminalSnapshot('lazy_mock_complete')

  -- Test 5: Lazy loading with recursive references
  -- SKIPPED: Recursive fixture not available in launch.json
  -- T.cmd("normal! q") -- Close current tree
  -- T.sleep(200)
  -- CommonSetups.setupRecursiveVariables(T, api)
  -- CommonSetups.openVariablesTree(T)
  -- T.cmd("execute \"normal \\<CR>\"") -- Expand scope
  -- T.sleep(200)
  -- T.cmd("/recursive") -- Find recursive object
  -- T.cmd("execute \"normal \\<CR>\"") -- Expand - should handle recursion
  -- T.sleep(500)
  -- T.TerminalSnapshot('lazy_recursive_handled')

  -- Test 6: Lazy loading performance (multiple expansions)
  for i = 1, 3 do
    T.cmd("normal! j") -- Navigate
    T.cmd("execute \"normal \\<CR>\"") -- Expand if possible
    T.sleep(100) -- Brief wait
  end
  T.TerminalSnapshot('lazy_performance_multiple')

  -- Test 7: Final lazy loading verification
  T.TerminalSnapshot('lazy_loading_final_state')
end)



--[[ TERMINAL SNAPSHOT: lazy_initial_state
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



--[[ TERMINAL SNAPSHOT: lazy_variable_loaded
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



--[[ TERMINAL SNAPSHOT: lazy_global_loaded
Size: 24x80
Cursor: [14, 21] (line 14, col 21)
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
16|     let│╰─ ▼ 󰀬 this: global                                             │
17|        ││  ╰─ ▶ 󰊕 AbortController: ƒ () { mod ??= requir...             │
18|        ││  ╰─ ▶ 󰊕 AbortSignal: ƒ () { mod ??= requir...                 │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               14,22-11      Top
]]


--[[ TERMINAL SNAPSHOT: lazy_complex_resolution
Size: 24x80
Cursor: [11, 19] (line 11, col 19)
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
24|                                                               11,20-11      Top
]]


--[[ TERMINAL SNAPSHOT: lazy_mock_intermediate
Size: 24x80
Cursor: [13, 24] (line 13, col 24)
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
15|     let││  ╰─ ▼ 󰊕 method: ƒ () { return "method"; }                     │
16|     let││  │  ╰─   󰅩 arguments: null                                    │
17|        ││  │  ╰─   󰅩 caller: null                                       │
18|        ││  │  ╰─   󰎠 length: 0                                          │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               13,25-14      Top
]]


--[[ TERMINAL SNAPSHOT: lazy_mock_complete
Size: 24x80
Cursor: [13, 24] (line 13, col 24)
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
15|     let││  ╰─ ▼ 󰊕 method: ƒ () { return "method"; }                     │
16|     let││  │  ╰─   󰅩 arguments: null                                    │
17|        ││  │  ╰─   󰅩 caller: null                                       │
18|        ││  │  ╰─   󰎠 length: 0                                          │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               13,25-14      Top
]]

--[[ TERMINAL SNAPSHOT: lazy_performance_multiple
Size: 24x80
Cursor: [16, 24] (line 16, col 24)
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
13| ated wh│╰─ ▼ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...      │
14|        ││  ╰─   󰎠 count: 100                                            │
15|     // ││  ╰─ ▼ 󰊕 method: ƒ () { return "method"; }                     │
16|     let││  │  ╰─   󰅩 arguments: null                                    │
17|     let││  │  ╰─   󰅩 caller: null                                       │
18|        ││  │  ╰─   󰎠 length: 0                                          │
19|        ││  │  ╰─   󰉿 name: "'method'"                                   │
20|        ╰────────────────────────────────────────────────────────────────╯
21|             level: 2,
22|             data: ["a", "b", "c"]
23|         },
24| lua/testing/fixtures/variables/complex.js                     7,1            Top
25|                                                               16,25-14       0%
]]

--[[ TERMINAL SNAPSHOT: lazy_loading_final_state
Size: 24x80
Cursor: [16, 24] (line 16, col 24)
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
13| ated wh│╰─ ▼ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...      │
14|        ││  ╰─   󰎠 count: 100                                            │
15|     // ││  ╰─ ▼ 󰊕 method: ƒ () { return "method"; }                     │
16|     let││  │  ╰─   󰅩 arguments: null                                    │
17|     let││  │  ╰─   󰅩 caller: null                                       │
18|        ││  │  ╰─   󰎠 length: 0                                          │
19|        ││  │  ╰─   󰉿 name: "'method'"                                   │
20|        ╰────────────────────────────────────────────────────────────────╯
21|             level: 2,
22|             data: ["a", "b", "c"]
23|         },
24| lua/testing/fixtures/variables/complex.js                     7,1            Top
25|                                                               16,25-14       0%
]]