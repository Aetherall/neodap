-- DebugTree Lazy Variable Test
-- Tests lazy variable resolution by trying to expand various variable types

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load all required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables4'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Set up debugging session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j")
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables")
  T.sleep(1500)
  
  -- Test 1: Open DebugTreeFrame and expand the Local scope
  T.cmd("DebugTreeFrame")
  T.sleep(500)
  T.TerminalSnapshot('lazy_test_initial')
  
  -- Move to Local scope and expand it
  T.cmd("normal! j") -- Move to Local scope
  T.cmd("execute \"normal \\<CR>\"") -- Expand Local scope
  T.sleep(800)
  T.TerminalSnapshot('lazy_test_local_expanded')
  
  -- Test 2: Try to expand a complex object (objectVar)
  -- Look for objectVar in the list and try to expand it
  T.cmd("normal! /objectVar") -- Search for objectVar
  T.cmd("execute \"normal \\<CR>\"") -- Press Enter on objectVar
  T.sleep(800) -- Wait for async expansion
  T.TerminalSnapshot('lazy_test_object_expanded')
  
  -- Test 3: Navigate into the expanded object to see its properties
  T.cmd("normal! j") -- Move down to first property
  T.sleep(200)
  T.TerminalSnapshot('lazy_test_object_properties')
  
  -- Test 4: Try to expand an array (arrayVar)
  T.cmd("normal! gg") -- Go to top
  T.cmd("normal! /arrayVar") -- Search for arrayVar  
  T.cmd("execute \"normal \\<CR>\"") -- Press Enter on arrayVar
  T.sleep(800) -- Wait for async expansion
  T.TerminalSnapshot('lazy_test_array_expanded')
  
  -- Test 5: Navigate into the expanded array to see its elements
  T.cmd("normal! j") -- Move down to first element
  T.sleep(200)
  T.TerminalSnapshot('lazy_test_array_elements')
  
  -- Test 4: Compare with Variables4 to see if lazy behavior differs
  T.cmd("normal! q") -- Close DebugTree
  T.sleep(200)
  
  T.cmd("Variables4Tree") -- Open Variables4 for comparison
  T.sleep(500)
  T.TerminalSnapshot('lazy_test_variables4_comparison')
  
  -- Clean up
  T.cmd("normal! q")
  T.sleep(200)
  T.TerminalSnapshot('lazy_test_cleanup')
end)









--[[ TERMINAL SNAPSHOT: lazy_test_initial
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
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








--[[ TERMINAL SNAPSHOT: lazy_test_local_expanded
Size: 24x80
Cursor: [24, 0] (line 24, col 0)
Mode: n

18| // Test fixture for Variables plugin - various variable types
19| 
20| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
21|     // │╰─ ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...      │
22|     let│╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                     │
23|     let│╰─   󰉿 stringVar: "'Hello, Debug!'"                             │
24|     let│╰─ ▶ 󰀬 this: global                                             │
25|     let│╰─   󰟢 undefinedVar: undefined                                  │
26|     let│╰─   󰉿 veryLongVariableNameThatExceedsNormalLimitsForDisplay: "'│
27|     let│▶ 📁  Global                                                     │lue";
28|     let│                                                                │e trunc
29| ated wh│                                                                │
30|        │                                                                │
31|     // │                                                                │
32|     let│                                                                │
33|     let│                                                                │
34|        │                                                                │
35|        │                                                                │
36|        ╰────────────────────────────────────────────────────────────────╯
37|             level: 2,
38|             data: ["a", "b", "c"]
39|         },
40| lua/testing/fixtures/variables/complex.js                     7,1            Top
41| W10: Warning: Changing a readonly file                        24,1          Bot
]]








--[[ TERMINAL SNAPSHOT: lazy_test_object_expanded
Size: 24x80
Cursor: [24, 0] (line 24, col 0)
Mode: n

18| // Test fixture for Variables plugin - various variable types
19| 
20| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
21|     // │╰─ ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...      │
22|     let│╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                     │
23|     let│╰─   󰉿 stringVar: "'Hello, Debug!'"                             │
24|     let│╰─ ▶ 󰀬 this: global                                             │
25|     let│╰─   󰟢 undefinedVar: undefined                                  │
26|     let│╰─   󰉿 veryLongVariableNameThatExceedsNormalLimitsForDisplay: "'│
27|     let│▼ 📁  Global                                                     │lue";
28|     let│╰─ ▶ 󰊕 AbortController: ƒ () { mod ??= requir...                │e trunc
29| ated wh│╰─ ▶ 󰊕 AbortSignal: ƒ () { mod ??= requir...                    │
30|        │╰─ ▶ 󰊕 atob: ƒ () { mod ??= requir...                           │
31|     // │╰─ ▶ 󰊕 Blob: ƒ () { mod ??= requir...                           │
32|     let│╰─ ▶ 󰊕 BroadcastChannel: ƒ () { mod ??= requir...               │
33|     let│╰─ ▶ 󰊕 btoa: ƒ () { mod ??= requir...                           │
34|        │╰─ ▶ 󰊕 Buffer: ƒ get() { return _Buf...                         │
35|        │╰─ ▶ 󰊕 ByteLengthQueuingStrategy: ƒ () { mod ??= requir...      │
36|        ╰────────────────────────────────────────────────────────────────╯
37|             level: 2,
38|             data: ["a", "b", "c"]
39|         },
40| lua/testing/fixtures/variables/complex.js                     7,1            Top
41|                                                               24,1          12%
]]









--[[ TERMINAL SNAPSHOT: lazy_test_array_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
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
24|                                                               1,1           Top
]]









--[[ TERMINAL SNAPSHOT: lazy_test_variables4_comparison
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
 4|     // │▼ 📁  Local: testVariables                                       │
 5|     let│╰─ ▼ ╭────────────── Variables4 Debug Tree ──────────────╮      │
 6|     let││  ╰─│▼ 📁  Local: testVariables                          │      │
 7|     let││  ╰─│╰─ ▼ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]        │      │
 8|     let││  ╰─│╰─   ◐ booleanVar: true                            │      │
 9|     let││  ╰─│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (│      │
10|     let││  ╰─│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }        │      │lue";
11|     let││  ╰─│╰─   󰉿 longStringValue: "'This is a very long strin│      │e trunc
12| ated wh││  ╰─│╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key│      │
13|        ││  ╰─│╰─   󰅩 nullVar: null                               │      │
14|     // │╰─   │╰─   󰎠 numberVar: 42                               │      │
15|     let│╰─   │╰─ ▶ 󰅩 objectVar: {name: 'Test Object', count: 100,│      │
16|     let│╰─ ▶ ╰───────────────────────────────────────────────────╯      │
17|        │╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
18|        │╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24| W10: Warning: Changing a readonly file                        1,1           Top
]]









--[[ TERMINAL SNAPSHOT: lazy_test_cleanup
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
 4|     // │▼ 📁  Local: testVariables                                       │
 5|     let│╰─ ▼ ╭────────────── Variables4 Debug Tree ──────────────╮      │
 6|     let││  ╰─│▼ 📁  Local: testVariables                          │      │
 7|     let││  ╰─│╰─ ▼ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]        │      │
 8|     let││  ╰─│╰─   ◐ booleanVar: true                            │      │
 9|     let││  ╰─│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (│      │
10|     let││  ╰─│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }        │      │lue";
11|     let││  ╰─│╰─   󰉿 longStringValue: "'This is a very long strin│      │e trunc
12| ated wh││  ╰─│╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key│      │
13|        ││  ╰─│╰─   󰅩 nullVar: null                               │      │
14|     // │╰─   │╰─   󰎠 numberVar: 42                               │      │
15|     let│╰─   │╰─ ▶ 󰅩 objectVar: {name: 'Test Object', count: 100,│      │
16|     let│╰─ ▶ ╰───────────────────────────────────────────────────╯      │
17|        │╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
18|        │╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24| W10: Warning: Changing a readonly file                        1,1           Top
]]




--[[ TERMINAL SNAPSHOT: lazy_test_object_properties
Size: 24x80
Cursor: [25, 0] (line 25, col 0)
Mode: n

18| // Test fixture for Variables plugin - various variable types
19| 
20| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
21|     // │╰─ ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...      │
22|     let│╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                     │
23|     let│╰─   󰉿 stringVar: "'Hello, Debug!'"                             │
24|     let│╰─ ▶ 󰀬 this: global                                             │
25|     let│╰─   󰟢 undefinedVar: undefined                                  │
26|     let│╰─   󰉿 veryLongVariableNameThatExceedsNormalLimitsForDisplay: "'│
27|     let│▼ 📁  Global                                                     │lue";
28|     let│╰─ ▶ 󰊕 AbortController: ƒ () { mod ??= requir...                │e trunc
29| ated wh│╰─ ▶ 󰊕 AbortSignal: ƒ () { mod ??= requir...                    │
30|        │╰─ ▶ 󰊕 atob: ƒ () { mod ??= requir...                           │
31|     // │╰─ ▶ 󰊕 Blob: ƒ () { mod ??= requir...                           │
32|     let│╰─ ▶ 󰊕 BroadcastChannel: ƒ () { mod ??= requir...               │
33|     let│╰─ ▶ 󰊕 btoa: ƒ () { mod ??= requir...                           │
34|        │╰─ ▶ 󰊕 Buffer: ƒ get() { return _Buf...                         │
35|        │╰─ ▶ 󰊕 ByteLengthQueuingStrategy: ƒ () { mod ??= requir...      │
36|        ╰────────────────────────────────────────────────────────────────╯
37|             level: 2,
38|             data: ["a", "b", "c"]
39|         },
40| lua/testing/fixtures/variables/complex.js                     7,1            Top
41|                                                               25,1          12%
]]





--[[ TERMINAL SNAPSHOT: lazy_test_array_elements
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
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
24|                                                               2,1           Top
]]