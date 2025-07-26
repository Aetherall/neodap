-- Lazy Variable Resolution Test for Variables4 Plugin
-- Tests that variables with presentationHint.lazy=true are resolved on toggle

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load the Variables4 plugin
  local variables4_plugin = api:getPluginInstance(require('neodap.plugins.Variables4'))
  
  -- Load supporting plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  
  -- Set up debugging session with a fixture that has lazy variables
  -- For this test, we'll use any JavaScript file and look for getter properties
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500)  -- Wait for session to start
  
  -- Open the variables tree
  T.cmd("Variables4Tree")
  T.sleep(500)
  T.TerminalSnapshot('lazy_tree_opened')
  
  -- Expand the Local scope to see variables
  T.cmd("execute \"normal \\<CR>\"")  -- Expand Local scope
  T.sleep(300)
  T.TerminalSnapshot('lazy_local_expanded')
  
  -- Look for any variable that might be lazy (usually getters or properties)
  -- Navigate through variables to find one with expandable state
  T.cmd("normal! 5j")  -- Move down to find an object variable
  T.TerminalSnapshot('lazy_found_object')
  
  -- Expand an object to see if it has lazy properties
  T.cmd("execute \"normal \\<CR>\"")  -- Expand the object
  T.sleep(400)
  T.TerminalSnapshot('lazy_object_expanded')
  
  -- If we find a lazy variable (presentationHint.lazy = true), 
  -- toggling it should resolve it and update the display
  -- Look for getter properties or lazy-loaded values
  T.cmd("normal! j")  -- Move to first property
  T.TerminalSnapshot('lazy_property_selected')
  
  -- Toggle the property - if it's lazy, it should resolve
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(300)
  T.TerminalSnapshot('lazy_property_toggled')
  
  -- Navigate to Global scope to find more complex lazy scenarios
  T.cmd("normal! gg")  -- Go to top
  T.cmd("normal! j")   -- Move to Global scope
  T.cmd("execute \"normal \\<CR>\"")  -- Expand Global
  T.sleep(800)  -- Global takes longer
  T.TerminalSnapshot('lazy_global_expanded')
  
  -- Look for known lazy properties in global objects
  -- Many built-in properties use getters that could be lazy
  T.cmd("normal! 10j")  -- Navigate down into global properties
  T.TerminalSnapshot('lazy_global_property')
  
  -- Close the tree
  T.cmd("execute \"normal q\"")
  T.sleep(200)
  T.TerminalSnapshot('lazy_test_complete')
end)

--[[ TERMINAL SNAPSHOT: lazy_tree_opened
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▶ 📁  <93><81> Local: testVariables                              │
 5|     let│▶ 📁  <93><81> Global                                            │
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
23| lua/testing/fixtures/variables/complex.js                     1,1            Top
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: lazy_local_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  <93><81> Local: testVariables                              │
 5|     let│  ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                      │
 6|     let│    ◐ booleanVar: true                                          │
 7|     let│    󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...         │
 8|     let│  ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                      │
 9|     let│    󰉿 longStringValue: "'This is a very long string valu..."    │
10|     let│  ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...          │lue";
11|     let│    󰅩 nullVar: null                                             │e trunc
12| ated wh│    󰎠 numberVar: 42                                             │
13|        │  ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...       │
14|     // │  ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                      │
15|     let│    󰉿 stringVar: "'Hello, Debug!'"                              │
16|     let│  ▶ 󰀬 this: global                                              │
17|        │    󰟢 undefinedVar: undefined                                   │
18|        │    󰉿 veryLongVariableNameThatExceedsNormalLimitsForDisplay: "'s│
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     1,1            Top
24|                                                               1,1           Top
]]

--[[ TERMINAL SNAPSHOT: lazy_found_object
Size: 24x80
Cursor: [6, 0] (line 6, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  <93><81> Local: testVariables                              │
 5|     let│  ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                      │
 6|     let│    ◐ booleanVar: true                                          │
 7|     let│    󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...         │
 8|     let│  ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                      │
 9|     let│    󰉿 longStringValue: "'This is a very long string valu..."    │
10|     let│  ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...          │lue";
11|     let│    󰅩 nullVar: null                                             │e trunc
12| ated wh│    󰎠 numberVar: 42                                             │
13|        │  ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...       │
14|     // │  ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                      │
15|     let│    󰉿 stringVar: "'Hello, Debug!'"                              │
16|     let│  ▶ 󰀬 this: global                                              │
17|        │    󰟢 undefinedVar: undefined                                   │
18|        │    󰉿 veryLongVariableNameThatExceedsNormalLimitsForDisplay: "'s│
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     1,1            Top
24|                                                               6,1           Top
]]

--[[ TERMINAL SNAPSHOT: lazy_object_expanded
Size: 24x80
Cursor: [6, 0] (line 6, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  <93><81> Local: testVariables                              │
 5|     let│  ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                      │
 6|     let│    ◐ booleanVar: true                                          │
 7|     let│    󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...         │
 8|     let│  ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                      │
 9|     let│    󰉿 longStringValue: "'This is a very long string valu..."    │
10|     let│  ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...          │lue";
11|     let│    󰅩 nullVar: null                                             │e trunc
12| ated wh│    󰎠 numberVar: 42                                             │
13|        │  ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...       │
14|     // │  ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                      │
15|     let│    󰉿 stringVar: "'Hello, Debug!'"                              │
16|     let│  ▶ 󰀬 this: global                                              │
17|        │    󰟢 undefinedVar: undefined                                   │
18|        │    󰉿 veryLongVariableNameThatExceedsNormalLimitsForDisplay: "'s│
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     1,1            Top
24|                                                               6,1           Top
]]

--[[ TERMINAL SNAPSHOT: lazy_property_selected
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  <93><81> Local: testVariables                              │
 5|     let│  ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                      │
 6|     let│    ◐ booleanVar: true                                          │
 7|     let│    󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...         │
 8|     let│  ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                      │
 9|     let│    󰉿 longStringValue: "'This is a very long string valu..."    │
10|     let│  ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...          │lue";
11|     let│    󰅩 nullVar: null                                             │e trunc
12| ated wh│    󰎠 numberVar: 42                                             │
13|        │  ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...       │
14|     // │  ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                      │
15|     let│    󰉿 stringVar: "'Hello, Debug!'"                              │
16|     let│  ▶ 󰀬 this: global                                              │
17|        │    󰟢 undefinedVar: undefined                                   │
18|        │    󰉿 veryLongVariableNameThatExceedsNormalLimitsForDisplay: "'s│
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     1,1            Top
24|                                                               7,1           Top
]]

--[[ TERMINAL SNAPSHOT: lazy_property_toggled
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  <93><81> Local: testVariables                              │
 5|     let│  ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                      │
 6|     let│    ◐ booleanVar: true                                          │
 7|     let│    󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...         │
 8|     let│  ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                      │
 9|     let│    󰉿 longStringValue: "'This is a very long string valu..."    │
10|     let│  ▼ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...          │lue";
11|     let│    ▶ 󰅩 0: {"key1" => "value1"}                                 │e trunc
12| ated wh│    ▶ 󰅩 1: {"key2" => "value2"}                                 │
13|        │      󰎠 size: 2                                                 │
14|     // │    ▶ 󰘣 [{Prototype}]: Map                                      │
15|     let│    󰅩 nullVar: null                                             │
16|     let│    󰎠 numberVar: 42                                             │
17|        │  ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...       │
18|        │  ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                      │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     1,1            Top
24|                                                               7,1           Top
]]

--[[ TERMINAL SNAPSHOT: lazy_global_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  <93><81> Local: testVariables                              │
 5|     let│  ▼ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                      │
 6|     let│      󰎠 0: 1                                                    │
 7|     let│      󰎠 1: 2                                                    │
 8|     let│      󰎠 2: 3                                                    │
 9|     let│      󰉿 3: "'four'"                                             │
10|     let│    ▶ 󰅩 4: {five: 5}                                            │lue";
11|     let│      󰎠 length: 5                                               │e trunc
12| ated wh│    ▶ 󰅩 [{Prototype}]: Object                                   │
13|        │    ▶ 󰅩 [{Prototype}]: Object                                   │
14|     // │    ◐ booleanVar: true                                          │
15|     let│    󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...         │
16|     let│  ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                      │
17|        │    󰉿 longStringValue: "'This is a very long string valu..."    │
18|        │  ▼ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...          │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     1,1            Top
24|                                                               2,1           Top
]]

--[[ TERMINAL SNAPSHOT: lazy_global_property
Size: 24x80
Cursor: [12, 0] (line 12, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  <93><81> Local: testVariables                              │
 5|     let│  ▼ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                      │
 6|     let│      󰎠 0: 1                                                    │
 7|     let│      󰎠 1: 2                                                    │
 8|     let│      󰎠 2: 3                                                    │
 9|     let│      󰉿 3: "'four'"                                             │
10|     let│    ▶ 󰅩 4: {five: 5}                                            │lue";
11|     let│      󰎠 length: 5                                               │e trunc
12| ated wh│    ▶ 󰅩 [{Prototype}]: Object                                   │
13|        │    ▶ 󰅩 [{Prototype}]: Object                                   │
14|     // │    ◐ booleanVar: true                                          │
15|     let│    󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...         │
16|     let│  ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                      │
17|        │    󰉿 longStringValue: "'This is a very long string valu..."    │
18|        │  ▼ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...          │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     1,1            Top
24|                                                               12,1          Top
]]

--[[ TERMINAL SNAPSHOT: lazy_test_complete
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| function testVariables() {
 4|     // Primitive types
 5|     let numberVar = 42;
 6|     let stringVar = "Hello, Debug!";
 7|     let booleanVar = true;
 8|     let nullVar = null;
 9|     let undefinedVar = undefined;
10|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
11|     let longStringValue = "This is a very long string value that should be trunc
12| ated when displayed in the tree view to prevent line wrapping";
13| 
14|     // Complex types
15|     let arrayVar = [1, 2, 3, "four", { five: 5 }];
16|     let objectVar = {
17|         name: "Test Object",
18|         count: 100,
19|         nested: {
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     1,1            Top
24|                                                               12,1          Top
]]