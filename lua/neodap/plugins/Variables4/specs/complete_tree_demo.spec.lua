-- Complete Tree Demo Test for Variables4 Plugin
-- Tests the complete plugin functionality using actual commands

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load the Variables4 plugin
  local variables4_plugin = api:getPluginInstance(require('neodap.plugins.Variables4'))

  -- Load supporting plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))

  -- Set up debugging session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j") -- Move to line with variables
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500) -- Wait for session and breakpoint hit

  T.TerminalSnapshot('complete_demo_session_ready')

  -- Test the main tree command
  T.cmd("Variables4Tree")
  T.sleep(500)
  T.TerminalSnapshot('complete_demo_tree_opened')

  -- Test hierarchical expansion - expand Local scope
  T.cmd("execute \"normal \\<CR>\"") -- Expand Local scope
  T.sleep(300)
  T.TerminalSnapshot('complete_demo_local_expanded')

  -- Navigate to a complex variable and expand it
  T.cmd("execute \"normal j\"")      -- Move to arrayVar
  T.sleep(100)
  T.cmd("execute \"normal \\<CR>\"") -- Expand arrayVar
  T.sleep(300)
  T.TerminalSnapshot('complete_demo_array_expanded')

  -- Navigate to nested object and expand
  T.cmd("execute \"normal j\"")      -- Move down
  T.sleep(100)
  T.cmd("execute \"normal j\"")      -- Move down
  T.sleep(100)
  T.cmd("execute \"normal j\"")      -- Move down
  T.sleep(100)
  T.cmd("execute \"normal j\"")      -- Move down to nested object
  T.sleep(100)
  T.cmd("execute \"normal \\<CR>\"") -- Expand nested object
  T.sleep(300)
  T.TerminalSnapshot('complete_demo_nested_expanded')

  -- Test navigation with more variables
  T.cmd("execute \"normal k\"")      -- Move up
  T.sleep(100)
  T.cmd("execute \"normal k\"")      -- Move up
  T.sleep(100)
  T.cmd("execute \"normal k\"")      -- Move up
  T.sleep(100)
  T.cmd("execute \"normal k\"")      -- Move up to objectVar
  T.sleep(100)
  T.cmd("execute \"normal \\<CR>\"") -- Expand objectVar
  T.sleep(300)
  T.TerminalSnapshot('complete_demo_object_expanded')

  -- Test frame management command
  T.cmd("execute \"normal q\"") -- Close popup first
  T.sleep(200)
  T.cmd("Variables4UpdateFrame")
  T.sleep(200)
  T.TerminalSnapshot('complete_demo_frame_updated')

  -- Reopen tree to show it works after frame update
  T.cmd("Variables4Tree")
  T.sleep(500)
  T.TerminalSnapshot('complete_demo_tree_reopened')

  -- Test Global scope expansion
  T.cmd("execute \"normal j\"")      -- Move to Global scope
  T.sleep(100)
  T.cmd("execute \"normal \\<CR>\"") -- Expand Global scope
  T.sleep(500)                       -- Global scope takes longer
  T.TerminalSnapshot('complete_demo_global_expanded')

  -- Final cleanup
  T.cmd("execute \"normal q\"") -- Close popup
  T.sleep(200)
  T.TerminalSnapshot('complete_demo_finished')
end)


--[[ TERMINAL SNAPSHOT: complete_demo_session_ready
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
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
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: complete_demo_tree_opened
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
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: complete_demo_local_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  <93><81> Local: testVariables                              │
 5|     let│  ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                      │
 6|     let│    ◐ booleanVar: true                                          │
 7|     let│    󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Central Europe│
 8|     let│an Stand...                                                     │
 9|     let│  ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                      │
10|     let│    󰉿 longStringValue: "'This is a very long string value that s│lue";
11|     let│hould b..."                                                     │e trunc
12| ated wh│  ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2 => value2}  │
13|        │    󰅩 nullVar: null                                             │
14|     // │    󰎠 numberVar: 42                                             │
15|     let│  ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nested: {…}, │
16|     let│method: ƒ}                                                      │
17|        │  ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                      │
18|        │    󰉿 stringVar: "'Hello, Debug!'"                              │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               1,1           Top
]]

--[[ TERMINAL SNAPSHOT: complete_demo_array_expanded
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
15|     let│    󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Central Europe│
16|     let│an Stand...                                                     │
17|        │  ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                      │
18|        │    󰉿 longStringValue: "'This is a very long string value tha@@@│
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               2,1           Top
]]

--[[ TERMINAL SNAPSHOT: complete_demo_nested_expanded
Size: 24x80
Cursor: [6, 0] (line 6, col 0)
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
15|     let│    󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Central Europe│
16|     let│an Stand...                                                     │
17|        │  ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                      │
18|        │    󰉿 longStringValue: "'This is a very long string value tha@@@│
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               6,1           Top
]]

--[[ TERMINAL SNAPSHOT: complete_demo_object_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  <93><81> Local: testVariables                              │
 5|     let│  ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                      │
 6|     let│    ◐ booleanVar: true                                          │
 7|     let│    󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Central Europe│
 8|     let│an Stand...                                                     │
 9|     let│  ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                      │
10|     let│    󰉿 longStringValue: "'This is a very long string value that s│lue";
11|     let│hould b..."                                                     │e trunc
12| ated wh│  ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2 => value2}  │
13|        │    󰅩 nullVar: null                                             │
14|     // │    󰎠 numberVar: 42                                             │
15|     let│  ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nested: {…}, │
16|     let│method: ƒ}                                                      │
17|        │  ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                      │
18|        │    󰉿 stringVar: "'Hello, Debug!'"                              │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               2,1           Top
]]

--[[ TERMINAL SNAPSHOT: complete_demo_frame_updated
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
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
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: complete_demo_tree_reopened
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  <93><81> Local: testVariables                              │
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
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: complete_demo_global_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  <93><81> Local: testVariables                              │
 5|     let│▼ 📁  <93><81> Global                                            │
 6|     let│  ▶ 󰊕 AbortController: ƒ () { mod ??= require(id); if (lazy...  │
 7|     let│  ▶ 󰊕 AbortSignal: ƒ () { mod ??= require(id); if (lazy...      │
 8|     let│  ▶ 󰊕 atob: ƒ () { mod ??= require(id); if (lazy...             │
 9|     let│  ▶ 󰊕 Blob: ƒ () { mod ??= require(id); if (lazy...             │
10|     let│  ▶ 󰊕 BroadcastChannel: ƒ () { mod ??= require(id); if (lazy... │lue";
11|     let│  ▶ 󰊕 btoa: ƒ () { mod ??= require(id); if (lazy...             │e trunc
12| ated wh│  ▶ 󰊕 Buffer: ƒ get() { return _Buffer; }                       │
13|        │  ▶ 󰊕 ByteLengthQueuingStrategy: ƒ () { mod ??= require(id); if │
14|     // │(lazy...                                                        │
15|     let│  ▶ 󰊕 clearImmediate: ƒ clearImmediate(immediate) { if (!immedia│
16|     let│te || immediat...                                               │
17|        │  ▶ 󰊕 clearInterval: ƒ clearInterval(timer) { // clearTimeout an│
18|        │d clearInterv...                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               2,1           Top
]]

--[[ TERMINAL SNAPSHOT: complete_demo_finished
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
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
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               2,1           Top
]]