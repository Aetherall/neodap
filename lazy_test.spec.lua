-- Test for lazy variable resolution
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load the Variables4 plugin
  local variables4_plugin = api:getPluginInstance(require('neodap.plugins.Variables4.alternative'))

  -- Load supporting plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))

  -- Set up debugging session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("NeodapLaunchClosest Variables")
  T.sleep(1500)

  -- Open the tree
  T.cmd("Variables4Tree")
  T.sleep(300)
  T.TerminalSnapshot('opened_tree')

  -- Expand Global scope to see lazy variables
  T.cmd("execute \"normal j\"")      -- move down to Global
  T.cmd("execute \"normal \\<CR>\"") -- Expand Global scope
  T.sleep(800)
  T.TerminalSnapshot('global_expanded')

  -- Navigate to the first lazy variable (AbortController)
  T.cmd("normal! j") -- Move to first variable
  T.TerminalSnapshot('on_abort_controller')

  -- Try to expand the lazy variable - this should resolve it
  T.cmd("execute \"normal \\<CR>\"") -- Expand lazy variable
  T.sleep(1000) -- Wait for lazy resolution
  T.TerminalSnapshot('abort_controller_resolved')

  -- Navigate to another lazy variable
  T.cmd("normal! j") -- Move to next variable
  T.TerminalSnapshot('on_abort_signal')

  -- Try to expand this one too
  T.cmd("execute \"normal \\<CR>\"") -- Expand lazy variable
  T.sleep(1000) -- Wait for lazy resolution
  T.TerminalSnapshot('abort_signal_resolved')
end)

--[[ TERMINAL SNAPSHOT: opened_tree
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

--[[ TERMINAL SNAPSHOT: global_expanded
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

--[[ TERMINAL SNAPSHOT: on_abort_controller
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
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
24|                                                               3,1           Top
]]

--[[ TERMINAL SNAPSHOT: abort_controller_resolved
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
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
24|                                                               3,1           Top
]]

--[[ TERMINAL SNAPSHOT: on_abort_signal
Size: 24x80
Cursor: [4, 0] (line 4, col 0)
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
24|                                                               4,1           Top
]]

--[[ TERMINAL SNAPSHOT: abort_signal_resolved
Size: 24x80
Cursor: [4, 0] (line 4, col 0)
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
24|                                                               4,1           Top
]]