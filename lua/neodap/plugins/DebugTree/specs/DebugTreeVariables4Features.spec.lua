-- Test Variables4-style features in DebugTree
-- Tests rich type icons, navigation, and lazy variable handling
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Set up debugging session with complex variables
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j") -- Go to line with booleanVar = true
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(2000) -- Wait for session to start and hit breakpoint
  
  -- Open DebugTree focused on frame
  T.cmd("DebugTreeFrame")
  T.sleep(500)
  T.TerminalSnapshot('01_frame_tree_initial')
  
  -- First expand the frame
  T.cmd("execute \"normal \\<CR>\"") -- Expand frame
  T.sleep(800)
  
  -- Navigate to Local scope and expand it
  T.cmd("normal! j") -- Move to Local scope
  T.cmd("execute \"normal \\<CR>\"") -- Expand Local scope
  T.sleep(1200) -- Give time for variables to load
  T.TerminalSnapshot('02_local_scope_expanded_rich_types')
  
  -- Navigate down with j to boolean variable
  T.cmd("normal! j") -- arrayVar
  T.cmd("normal! j") -- booleanVar
  T.TerminalSnapshot('03_navigated_to_boolean')
  
  -- Navigate down to object variable and expand it
  T.cmd("normal! 6j") -- Skip to objectVar
  T.cmd("normal! l") -- Use l key to expand
  T.sleep(500)
  T.TerminalSnapshot('04_object_expanded_with_l')
  
  -- Navigate into nested object with l
  T.cmd("normal! j") -- Move to first property
  T.cmd("normal! j") -- Move to nested property
  T.cmd("normal! l") -- Expand nested
  T.sleep(500)
  T.TerminalSnapshot('05_nested_object_expanded')
  
  -- Navigate back to parent with h
  T.cmd("normal! h") -- Back to parent object
  T.TerminalSnapshot('06_navigated_back_with_h')
  
  -- Test focus mode - focus on objectVar
  T.cmd("normal! k") -- Move back to objectVar
  T.cmd("normal! f") -- Focus on objectVar
  T.sleep(300)
  T.TerminalSnapshot('07_focused_on_object')
  
  -- Unfocus with F
  T.cmd("normal! F") -- Unfocus
  T.sleep(300)
  T.TerminalSnapshot('08_unfocused_view')
  
  -- Navigate to Global scope to see lazy variables
  T.cmd("normal! k") -- Move up
  T.cmd("normal! k") -- Move to Global scope
  T.cmd("execute \"normal \\<CR>\"") -- Expand Global
  T.sleep(1000)
  T.TerminalSnapshot('09_global_scope_lazy_variables')
  
  -- Test help
  T.cmd("normal! ?")
  T.sleep(100)
  T.TerminalSnapshot('10_help_displayed')
  
  -- Clean up
  T.cmd("normal! q")
  T.sleep(200)
  T.TerminalSnapshot('11_cleanup')
end)



--[[ TERMINAL SNAPSHOT: 01_frame_tree_initial
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
 4|     // │▶ 🖼   global.testVariables                                      │
 5|     let│                                                                │
 6|     let│                                                                │
 7|     let│                                                                │
 8|     let│                                                                │
 9|     let│                                                                │
10|     let│                                                                │lue";
11|     let│                                                                │e trunc
12| ated wh│                                                                │
13|        │                                                                │
14|     // │                                                                │
15|     let│                                                                │
16|     let│                                                                │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               1,1           All
]]




--[[ TERMINAL SNAPSHOT: 02_local_scope_expanded_rich_types
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
 4|     // │▼ 🖼   global.testVariables                                      │
 5|     let│╰─ ▼ 📁  Local: testVariables                                    │
 6|     let││  ╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                  │
 7|     let││  ╰─   ◐ booleanVar: true                                      │
 8|     let││  ╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...     │
 9|     let││  ╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                  │
10|     let││  ╰─   󰉿 longStringValue: "'This is a very long string valu..."│lue";
11|     let││  ╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...      │e trunc
12| ated wh││  ╰─   󰅩 nullVar: null                                         │
13|        ││  ╰─   󰎠 numberVar: 42                                         │
14|     // ││  ╰─ ▶ 󰅩 objectVar: {...}                                      │
15|     let││  ╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                  │
16|     let││  ╰─   󰉿 stringVar: "'Hello, Debug!'"                          │
17|        ││  ╰─ ▶ 󰀬 this: global                                          │
18|        ││  ╰─   󰟢 undefinedVar: undefined                               │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               2,1           Top
]]




--[[ TERMINAL SNAPSHOT: 03_navigated_to_boolean
Size: 24x80
Cursor: [4, 0] (line 4, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
 4|     // │▼ 🖼   global.testVariables                                      │
 5|     let│╰─ ▼ 📁  Local: testVariables                                    │
 6|     let││  ╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                  │
 7|     let││  ╰─   ◐ booleanVar: true                                      │
 8|     let││  ╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...     │
 9|     let││  ╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                  │
10|     let││  ╰─   󰉿 longStringValue: "'This is a very long string valu..."│lue";
11|     let││  ╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...      │e trunc
12| ated wh││  ╰─   󰅩 nullVar: null                                         │
13|        ││  ╰─   󰎠 numberVar: 42                                         │
14|     // ││  ╰─ ▶ 󰅩 objectVar: {...}                                      │
15|     let││  ╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                  │
16|     let││  ╰─   󰉿 stringVar: "'Hello, Debug!'"                          │
17|        ││  ╰─ ▶ 󰀬 this: global                                          │
18|        ││  ╰─   󰟢 undefinedVar: undefined                               │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               4,1           Top
]]




--[[ TERMINAL SNAPSHOT: 04_object_expanded_with_l
Size: 24x80
Cursor: [10, 3] (line 10, col 3)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
 4|     // │▼ 🖼   global.testVariables                                      │
 5|     let│╰─ ▼ 📁  Local: testVariables                                    │
 6|     let││  ╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                  │
 7|     let││  ╰─   ◐ booleanVar: true                                      │
 8|     let││  ╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...     │
 9|     let││  ╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                  │
10|     let││  ╰─   󰉿 longStringValue: "'This is a very long string valu..."│lue";
11|     let││  ╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...      │e trunc
12| ated wh││  ╰─   󰅩 nullVar: null                                         │
13|        ││  ╰─   󰎠 numberVar: 42                                         │
14|     // ││  ╰─ ▶ 󰅩 objectVar: {...}                                      │
15|     let││  ╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                  │
16|     let││  ╰─   󰉿 stringVar: "'Hello, Debug!'"                          │
17|        ││  ╰─ ▶ 󰀬 this: global                                          │
18|        ││  ╰─   󰟢 undefinedVar: undefined                               │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               10,4-2        Top
]]




--[[ TERMINAL SNAPSHOT: 05_nested_object_expanded
Size: 24x80
Cursor: [12, 4] (line 12, col 4)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
 4|     // │▼ 🖼   global.testVariables                                      │
 5|     let│╰─ ▼ 📁  Local: testVariables                                    │
 6|     let││  ╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                  │
 7|     let││  ╰─   ◐ booleanVar: true                                      │
 8|     let││  ╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...     │
 9|     let││  ╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                  │
10|     let││  ╰─   󰉿 longStringValue: "'This is a very long string valu..."│lue";
11|     let││  ╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...      │e trunc
12| ated wh││  ╰─   󰅩 nullVar: null                                         │
13|        ││  ╰─   󰎠 numberVar: 42                                         │
14|     // ││  ╰─ ▶ 󰅩 objectVar: {...}                                      │
15|     let││  ╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                  │
16|     let││  ╰─   󰉿 stringVar: "'Hello, Debug!'"                          │
17|        ││  ╰─ ▶ 󰀬 this: global                                          │
18|        ││  ╰─   󰟢 undefinedVar: undefined                               │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               12,5-3        Top
]]




--[[ TERMINAL SNAPSHOT: 06_navigated_back_with_h
Size: 24x80
Cursor: [12, 3] (line 12, col 3)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
 4|     // │▼ 🖼   global.testVariables                                      │
 5|     let│╰─ ▼ 📁  Local: testVariables                                    │
 6|     let││  ╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                  │
 7|     let││  ╰─   ◐ booleanVar: true                                      │
 8|     let││  ╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...     │
 9|     let││  ╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                  │
10|     let││  ╰─   󰉿 longStringValue: "'This is a very long string valu..."│lue";
11|     let││  ╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...      │e trunc
12| ated wh││  ╰─   󰅩 nullVar: null                                         │
13|        ││  ╰─   󰎠 numberVar: 42                                         │
14|     // ││  ╰─ ▶ 󰅩 objectVar: {...}                                      │
15|     let││  ╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                  │
16|     let││  ╰─   󰉿 stringVar: "'Hello, Debug!'"                          │
17|        ││  ╰─ ▶ 󰀬 this: global                                          │
18|        ││  ╰─   󰟢 undefinedVar: undefined                               │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               12,4-2        Top
]]




--[[ TERMINAL SNAPSHOT: 07_focused_on_object
Size: 24x80
Cursor: [11, 3] (line 11, col 3)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
 4|     // │▼ 🖼   global.testVariables                                      │
 5|     let│╰─ ▼ 📁  Local: testVariables                                    │
 6|     let││  ╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                  │
 7|     let││  ╰─   ◐ booleanVar: true                                      │
 8|     let││  ╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...     │
 9|     let││  ╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                  │
10|     let││  ╰─   󰉿 longStringValue: "'This is a very long string valu..."│lue";
11|     let││  ╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...      │e trunc
12| ated wh││  ╰─   󰅩 nullVar: null                                         │
13|        ││  ╰─   󰎠 numberVar: 42                                         │
14|     // ││  ╰─ ▶ 󰅩 objectVar: {...}                                      │
15|     let││  ╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                  │
16|     let││  ╰─   󰉿 stringVar: "'Hello, Debug!'"                          │
17|        ││  ╰─ ▶ 󰀬 this: global                                          │
18|        ││  ╰─   󰟢 undefinedVar: undefined                               │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               11,4-2        Top
]]




--[[ TERMINAL SNAPSHOT: 08_unfocused_view
Size: 24x80
Cursor: [11, 3] (line 11, col 3)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
 4|     // │▼ 🖼   global.testVariables                                      │
 5|     let│╰─ ▼ 📁  Local: testVariables                                    │
 6|     let││  ╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                  │
 7|     let││  ╰─   ◐ booleanVar: true                                      │
 8|     let││  ╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...     │
 9|     let││  ╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                  │
10|     let││  ╰─   󰉿 longStringValue: "'This is a very long string valu..."│lue";
11|     let││  ╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...      │e trunc
12| ated wh││  ╰─   󰅩 nullVar: null                                         │
13|        ││  ╰─   󰎠 numberVar: 42                                         │
14|     // ││  ╰─ ▶ 󰅩 objectVar: {...}                                      │
15|     let││  ╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                  │
16|     let││  ╰─   󰉿 stringVar: "'Hello, Debug!'"                          │
17|        ││  ╰─ ▶ 󰀬 this: global                                          │
18|        ││  ╰─   󰟢 undefinedVar: undefined                               │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               11,4-2        Top
]]




--[[ TERMINAL SNAPSHOT: 09_global_scope_lazy_variables
Size: 24x80
Cursor: [9, 3] (line 9, col 3)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
 4|     // │▼ 🖼   global.testVariables                                      │
 5|     let│╰─ ▼ 📁  Local: testVariables                                    │
 6|     let││  ╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                  │
 7|     let││  ╰─   ◐ booleanVar: true                                      │
 8|     let││  ╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...     │
 9|     let││  ╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                  │
10|     let││  ╰─   󰉿 longStringValue: "'This is a very long string valu..."│lue";
11|     let││  ╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...      │e trunc
12| ated wh││  ╰─   󰅩 nullVar: null                                         │
13|        ││  ╰─   󰎠 numberVar: 42                                         │
14|     // ││  ╰─ ▶ 󰅩 objectVar: {...}                                      │
15|     let││  ╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                  │
16|     let││  ╰─   󰉿 stringVar: "'Hello, Debug!'"                          │
17|        ││  ╰─ ▶ 󰀬 this: global                                          │
18|        ││  ╰─   󰟢 undefinedVar: undefined                               │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               9,4-2         Top
]]




--[[ TERMINAL SNAPSHOT: 10_help_displayed
Size: 24x80
Cursor: [9, 3] (line 9, col 3)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
 4|     // │▼ 🖼   global.testVariables                                      │
 5|     let│╰─ ▼ 📁  Local: testVariables                                    │
 6|     let││  ╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                  │
 7|     let││  ╰─   ◐ booleanVar: true                                      │
 8|     let││  ╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...     │
 9|     let││  ╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                  │
10|     let││  ╰─   󰉿 longStringValue: "'This is a very long string valu..."│lue";
11|     let││  ╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...      │e trunc
12| ated wh││  ╰─   󰅩 nullVar: null                                         │
13|        ││  ╰─   󰎠 numberVar: 42                                         │
14|     // ││  ╰─ ▶ 󰅩 objectVar: {...}                                      │
15|     let││  ╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                  │
16|     let││  ╰─   󰉿 stringVar: "'Hello, Debug!'"                          │
17|        ││  ╰─ ▶ 󰀬 this: global                                          │
18|        ││  ╰─   󰟢 undefinedVar: undefined                               │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               9,4-2         Top
]]




--[[ TERMINAL SNAPSHOT: 11_cleanup
Size: 24x80
Cursor: [9, 3] (line 9, col 3)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────── Debug Tree - Frame Variables ─────────────────╮
 4|     // │▼ 🖼   global.testVariables                                      │
 5|     let│╰─ ▼ 📁  Local: testVariables                                    │
 6|     let││  ╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                  │
 7|     let││  ╰─   ◐ booleanVar: true                                      │
 8|     let││  ╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...     │
 9|     let││  ╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                  │
10|     let││  ╰─   󰉿 longStringValue: "'This is a very long string valu..."│lue";
11|     let││  ╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...      │e trunc
12| ated wh││  ╰─   󰅩 nullVar: null                                         │
13|        ││  ╰─   󰎠 numberVar: 42                                         │
14|     // ││  ╰─ ▶ 󰅩 objectVar: {...}                                      │
15|     let││  ╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                  │
16|     let││  ╰─   󰉿 stringVar: "'Hello, Debug!'"                          │
17|        ││  ╰─ ▶ 󰀬 this: global                                          │
18|        ││  ╰─   󰟢 undefinedVar: undefined                               │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               9,4-2         Top
]]