-- Lazy Variable Resolution Test for Variables4 Plugin
-- Tests lazy variables in the global scope where many built-in properties use getters

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load the Variables4 plugin
  local _variables4_plugin = api:getPluginInstance(require('neodap.plugins.Variables4'))
  
  -- Load supporting plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  
  -- Use any JavaScript file - we're interested in the global scope
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500)  -- Wait for session to start
  
  -- Open the variables tree
  T.cmd("Variables4Tree")
  T.sleep(500)
  T.TerminalSnapshot('lazy_global_tree_opened')
  
  -- Navigate directly to Global scope
  T.cmd("normal! j")  -- Move to Global scope
  T.cmd("execute \"normal \\<CR>\"")  -- Expand Global scope
  T.sleep(800)  -- Global scope takes longer to load
  T.TerminalSnapshot('lazy_global_scope_expanded')
  
  -- Many global properties are lazy-loaded getters
  -- Look for properties like 'process', 'global', 'Buffer', etc.
  -- These often have presentationHint.lazy = true
  
  -- Navigate through global properties to find lazy ones
  -- The 'global' property itself is often lazy and recursive
  T.cmd("normal! 10j")  -- Move down to find interesting properties
  T.TerminalSnapshot('lazy_global_navigated')
  
  -- Try to expand a property that might be lazy
  -- If it's lazy, our resolution code should trigger
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(400)
  T.TerminalSnapshot('lazy_global_property_toggled')
  
  -- Continue exploring - look for 'process' which often has lazy properties
  T.cmd("normal! 10j")  -- Move further down
  T.TerminalSnapshot('lazy_global_process_area')
  
  -- Try expanding another potentially lazy property
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(400)
  T.TerminalSnapshot('lazy_global_second_toggle')
  
  -- Look for Buffer or other constructor functions that might be lazy
  T.cmd("normal! gg")  -- Go to top of tree
  T.cmd("normal! /Buffer")  -- Search for Buffer
  T.cmd("normal! n")  -- Go to search result
  T.sleep(200)
  T.TerminalSnapshot('lazy_global_buffer_found')
  
  -- Toggle Buffer if found - constructors often have lazy prototype properties
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(400)
  T.TerminalSnapshot('lazy_global_buffer_toggled')
  
  -- Check if any lazy properties were resolved
  -- The UI should update seamlessly without showing intermediate nodes
  
  -- Close the tree
  T.cmd("execute \"normal q\"")
  T.sleep(200)
  T.TerminalSnapshot('lazy_global_test_complete')
end)

--[[ TERMINAL SNAPSHOT: lazy_global_tree_opened
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

--[[ TERMINAL SNAPSHOT: lazy_global_scope_expanded
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

--[[ TERMINAL SNAPSHOT: lazy_global_navigated
Size: 24x80
Cursor: [12, 0] (line 12, col 0)
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
24|                                                               12,1          Top
]]

--[[ TERMINAL SNAPSHOT: lazy_global_property_toggled
Size: 24x80
Cursor: [12, 0] (line 12, col 0)
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
15|     let│  ▼ 󰊕 clearInterval: ƒ clearInterval(timer) { // clearTim...    │
16|     let│    ▶ 󰊕 arguments: ƒ ()                                         │
17|        │    ▶ 󰊕 caller: ƒ ()                                            │
18|        │      󰎠 length: 1                                               │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     1,1            Top
24|                                                               12,1          Top
]]

--[[ TERMINAL SNAPSHOT: lazy_global_process_area
Size: 24x80
Cursor: [22, 0] (line 22, col 0)
Mode: n

 8| // Test fixture for Variables plugin - various variable types
 9| 
10| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
11|     // │  ▶ 󰊕 btoa: ƒ () { mod ??= requir...                            │
12|     let│  ▶ 󰊕 Buffer: ƒ get() { return _Buf...                          │
13|     let│  ▶ 󰊕 ByteLengthQueuingStrategy: ƒ () { mod ??= requir...       │
14|     let│  ▶ 󰊕 clearImmediate: ƒ clearImmediate(immediate) { if (!i...   │
15|     let│  ▼ 󰊕 clearInterval: ƒ clearInterval(timer) { // clearTim...    │
16|     let│    ▶ 󰊕 arguments: ƒ ()                                         │
17|     let│    ▶ 󰊕 caller: ƒ ()                                            │lue";
18|     let│      󰎠 length: 1                                               │e trunc
19| ated wh│      󰉿 name: "'clearInterval'"                                 │
20|        │    ▶ 󰅩 prototype: {constructor: ƒ}                             │
21|     // │      󰀬 [{FunctionLocation}]: @ <node_internals>/timers:244     │
22|     let│    ▶ 󰊕 [{Prototype}]: ƒ ()                                     │
23|     let│    ▶ 󰅪 [{Scopes}]: Scopes[2]                                   │
24|        │  ▶ 󰊕 clearTimeout: ƒ clearTimeout(timer) { if (timer &&...     │
25|        │  ▶ 󰊕 CompressionStream: ƒ () { mod ??= requir...               │
26|        ╰────────────────────────────────────────────────────────────────╯
27|             level: 2,
28|             data: ["a", "b", "c"]
29|         },
30| lua/testing/fixtures/variables/complex.js                     1,1            Top
31|                                                               22,1           5%
]]

--[[ TERMINAL SNAPSHOT: lazy_global_second_toggle
Size: 24x80
Cursor: [22, 0] (line 22, col 0)
Mode: n

 8| // Test fixture for Variables plugin - various variable types
 9| 
10| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
11|     // │  ▶ 󰊕 btoa: ƒ () { mod ??= requir...                            │
12|     let│  ▶ 󰊕 Buffer: ƒ get() { return _Buf...                          │
13|     let│  ▶ 󰊕 ByteLengthQueuingStrategy: ƒ () { mod ??= requir...       │
14|     let│  ▶ 󰊕 clearImmediate: ƒ clearImmediate(immediate) { if (!i...   │
15|     let│  ▼ 󰊕 clearInterval: ƒ clearInterval(timer) { // clearTim...    │
16|     let│    ▶ 󰊕 arguments: ƒ ()                                         │
17|     let│    ▶ 󰊕 caller: ƒ ()                                            │lue";
18|     let│      󰎠 length: 1                                               │e trunc
19| ated wh│      󰉿 name: "'clearInterval'"                                 │
20|        │    ▶ 󰅩 prototype: {constructor: ƒ}                             │
21|     // │      󰀬 [{FunctionLocation}]: @ <node_internals>/timers:244     │
22|     let│    ▶ 󰊕 [{Prototype}]: ƒ ()                                     │
23|     let│    ▶ 󰅪 [{Scopes}]: Scopes[2]                                   │
24|        │  ▶ 󰊕 clearTimeout: ƒ clearTimeout(timer) { if (timer &&...     │
25|        │  ▶ 󰊕 CompressionStream: class CompressionStream                │
26|        ╰────────────────────────────────────────────────────────────────╯
27|             level: 2,
28|             data: ["a", "b", "c"]
29|         },
30| lua/testing/fixtures/variables/complex.js                     1,1            Top
31|                                                               22,1           5%
]]