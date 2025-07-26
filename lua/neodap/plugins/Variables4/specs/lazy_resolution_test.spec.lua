-- Test lazy variable resolution with actual lazy global variables

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load the Variables4 plugin
  local _variables4_plugin = api:getPluginInstance(require('neodap.plugins.Variables4'))
  
  -- Load supporting plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  
  -- Use any JavaScript file
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500)
  
  -- Open the variables tree
  T.cmd("Variables4Tree")
  T.sleep(500)
  T.TerminalSnapshot('lazy_resolution_tree_opened')
  
  -- Navigate directly to Global scope where lazy variables are
  T.cmd("normal! j")  -- Move to Global scope
  T.cmd("execute \"normal \\<CR>\"")  -- Expand Global scope
  T.sleep(800)  -- Global scope takes longer to load
  T.TerminalSnapshot('lazy_resolution_global_expanded')
  
  -- Navigate to find a lazy variable like Buffer or Request
  -- These were confirmed to have presentationHint.lazy = true
  T.cmd("normal! 5j")  -- Move down to find Buffer
  T.TerminalSnapshot('lazy_resolution_at_buffer')
  
  -- Toggle Buffer - this should trigger lazy resolution!
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(400)
  T.TerminalSnapshot('lazy_resolution_buffer_toggled')
  
  -- Check if the lazy variable was resolved
  -- The value should change from the getter function to the actual resolved value
  
  -- Try another lazy variable - navigate to Request
  T.cmd("normal! 20j")  -- Move down to find Request
  T.TerminalSnapshot('lazy_resolution_at_request')
  
  -- Toggle Request
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(400)
  T.TerminalSnapshot('lazy_resolution_request_toggled')
  
  -- Close the tree
  T.cmd("execute \"normal q\"")
  T.sleep(200)
  T.TerminalSnapshot('lazy_resolution_complete')
end)

--[[ TERMINAL SNAPSHOT: lazy_resolution_tree_opened
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

--[[ TERMINAL SNAPSHOT: lazy_resolution_global_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▶ 📁  <93><81> Local: testVariables                              │
 5|     let│▼ 📁  <93><81> Global                                            │
 6|     let│  ▶ 󰊕 AbortController: ƒ () { mod ??= requir...                 │
 7|     let│  ▶ 󰊕 AbortSignal: ƒ () { mod ??= requir...                     │
 8|     let│  ▶ 󰊕 atob: ƒ () { mod ??= requir...                            │
 9|     let│  ▶ 󰊕 Blob: ƒ () { mod ??= requir...                            │
10|     let│  ▶ 󰊕 BroadcastChannel: ƒ () { mod ??= requir...                │lue";
11|     let│  ▶ 󰊕 btoa: ƒ () { mod ??= requir...                            │e trunc
12| ated wh│  ▶ 󰊕 Buffer: ƒ get() { return _Buf...                          │
13|        │  ▶ 󰊕 ByteLengthQueuingStrategy: ƒ () { mod ??= requir...       │
14|     // │  ▶ 󰊕 clearImmediate: ƒ clearImmediate(immediate) { if (!i...   │
15|     let│  ▶ 󰊕 clearInterval: ƒ clearInterval(timer) { // clearTim...    │
16|     let│  ▶ 󰊕 clearTimeout: ƒ clearTimeout(timer) { if (timer &&...     │
17|        │  ▶ 󰊕 CompressionStream: ƒ () { mod ??= requir...               │
18|        │  ▶ 󰊕 CountQueuingStrategy: ƒ () { mod ??= requir...            │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     1,1            Top
24|                                                               2,1           Top
]]

--[[ TERMINAL SNAPSHOT: lazy_resolution_at_buffer
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▶ 📁  <93><81> Local: testVariables                              │
 5|     let│▼ 📁  <93><81> Global                                            │
 6|     let│  ▶ 󰊕 AbortController: ƒ () { mod ??= requir...                 │
 7|     let│  ▶ 󰊕 AbortSignal: ƒ () { mod ??= requir...                     │
 8|     let│  ▶ 󰊕 atob: ƒ () { mod ??= requir...                            │
 9|     let│  ▶ 󰊕 Blob: ƒ () { mod ??= requir...                            │
10|     let│  ▶ 󰊕 BroadcastChannel: ƒ () { mod ??= requir...                │lue";
11|     let│  ▶ 󰊕 btoa: ƒ () { mod ??= requir...                            │e trunc
12| ated wh│  ▶ 󰊕 Buffer: ƒ get() { return _Buf...                          │
13|        │  ▶ 󰊕 ByteLengthQueuingStrategy: ƒ () { mod ??= requir...       │
14|     // │  ▶ 󰊕 clearImmediate: ƒ clearImmediate(immediate) { if (!i...   │
15|     let│  ▶ 󰊕 clearInterval: ƒ clearInterval(timer) { // clearTim...    │
16|     let│  ▶ 󰊕 clearTimeout: ƒ clearTimeout(timer) { if (timer &&...     │
17|        │  ▶ 󰊕 CompressionStream: ƒ () { mod ??= requir...               │
18|        │  ▶ 󰊕 CountQueuingStrategy: ƒ () { mod ??= requir...            │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     1,1            Top
24|                                                               7,1           Top
]]

--[[ TERMINAL SNAPSHOT: lazy_resolution_buffer_toggled
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▶ 📁  <93><81> Local: testVariables                              │
 5|     let│▼ 📁  <93><81> Global                                            │
 6|     let│  ▶ 󰊕 AbortController: ƒ () { mod ??= requir...                 │
 7|     let│  ▶ 󰊕 AbortSignal: ƒ () { mod ??= requir...                     │
 8|     let│  ▶ 󰊕 atob: ƒ () { mod ??= requir...                            │
 9|     let│  ▶ 󰊕 Blob: ƒ () { mod ??= requir...                            │
10|     let│  ▶ 󰊕 BroadcastChannel: class BroadcastChannel                  │lue";
11|     let│  ▶ 󰊕 btoa: ƒ () { mod ??= requir...                            │e trunc
12| ated wh│  ▶ 󰊕 Buffer: ƒ get() { return _Buf...                          │
13|        │  ▶ 󰊕 ByteLengthQueuingStrategy: ƒ () { mod ??= requir...       │
14|     // │  ▶ 󰊕 clearImmediate: ƒ clearImmediate(immediate) { if (!i...   │
15|     let│  ▶ 󰊕 clearInterval: ƒ clearInterval(timer) { // clearTim...    │
16|     let│  ▶ 󰊕 clearTimeout: ƒ clearTimeout(timer) { if (timer &&...     │
17|        │  ▶ 󰊕 CompressionStream: ƒ () { mod ??= requir...               │
18|        │  ▶ 󰊕 CountQueuingStrategy: ƒ () { mod ??= requir...            │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     1,1            Top
24|                                                               7,1           Top
]]

--[[ TERMINAL SNAPSHOT: lazy_resolution_at_request
Size: 24x80
Cursor: [27, 0] (line 27, col 0)
Mode: n

20| // Test fixture for Variables plugin - various variable types
21| 
22| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
23|     // │  ▶ 󰊕 DOMException: () => { const DOMExcep...                   │
24|     let│  ▶ 󰊕 fetch: ƒ fetch(input, init = undefined) { /...            │
25|     let│  ▶ 󰊕 File: ƒ () { mod ??= requir...                            │
26|     let│  ▶ 󰊕 FormData: ƒ () { mod ??= requir...                        │
27|     let│  ▶ 󰀬 global: global {global: global, clearImmediat...          │
28|     let│  ▶ 󰊕 Headers: ƒ () { mod ??= requir...                         │
29|     let│  ▶ 󰊕 MessageChannel: ƒ () { mod ??= requir...                  │lue";
30|     let│  ▶ 󰊕 MessageEvent: ƒ () { mod ??= requir...                    │e trunc
31| ated wh│  ▶ 󰊕 MessagePort: ƒ () { mod ??= requir...                     │
32|        │  ▶ 󰊕 performance: ƒ () { if (check !== ...                     │
33|     // │  ▶ 󰊕 Performance: ƒ () { mod ??= requir...                     │
34|     let│  ▶ 󰊕 PerformanceEntry: ƒ () { mod ??= requir...                │
35|     let│  ▶ 󰊕 PerformanceMark: ƒ () { mod ??= requir...                 │
36|        │  ▶ 󰊕 PerformanceMeasure: ƒ () { mod ??= requir...              │
37|        │  ▶ 󰊕 PerformanceObserver: ƒ () { mod ??= requir...             │
38|        ╰────────────────────────────────────────────────────────────────╯
39|             level: 2,
40|             data: ["a", "b", "c"]
41|         },
42| lua/testing/fixtures/variables/complex.js                     1,1            Top
43|                                                               27,1          16%
]]

--[[ TERMINAL SNAPSHOT: lazy_resolution_request_toggled
Size: 24x80
Cursor: [27, 0] (line 27, col 0)
Mode: n

20| // Test fixture for Variables plugin - various variable types
21| 
22| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
23|     // │  ▶ 󰊕 DOMException: () => { const DOMExcep...                   │
24|     let│  ▶ 󰊕 fetch: ƒ fetch(input, init = undefined) { /...            │
25|     let│  ▶ 󰊕 File: ƒ () { mod ??= requir...                            │
26|     let│  ▶ 󰊕 FormData: ƒ () { mod ??= requir...                        │
27|     let│  ▶ 󰀬 global: global {global: global, clearImmediat...          │
28|     let│  ▶ 󰊕 Headers: ƒ () { mod ??= requir...                         │
29|     let│  ▶ 󰊕 MessageChannel: ƒ () { mod ??= requir...                  │lue";
30|     let│  ▶ 󰊕 MessageEvent: class MessageEvent extends Event { co...    │e trunc
31| ated wh│  ▶ 󰊕 MessagePort: ƒ () { mod ??= requir...                     │
32|        │  ▶ 󰊕 performance: ƒ () { if (check !== ...                     │
33|     // │  ▶ 󰊕 Performance: ƒ () { mod ??= requir...                     │
34|     let│  ▶ 󰊕 PerformanceEntry: ƒ () { mod ??= requir...                │
35|     let│  ▶ 󰊕 PerformanceMark: ƒ () { mod ??= requir...                 │
36|        │  ▶ 󰊕 PerformanceMeasure: ƒ () { mod ??= requir...              │
37|        │  ▶ 󰊕 PerformanceObserver: ƒ () { mod ??= requir...             │
38|        ╰────────────────────────────────────────────────────────────────╯
39|             level: 2,
40|             data: ["a", "b", "c"]
41|         },
42| lua/testing/fixtures/variables/complex.js                     1,1            Top
43|                                                               27,1          16%
]]

--[[ TERMINAL SNAPSHOT: lazy_resolution_complete
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
24|                                                               27,1          16%
]]