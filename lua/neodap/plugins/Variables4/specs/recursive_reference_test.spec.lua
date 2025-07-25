-- Recursive Reference Test for Variables4 Plugin
-- Tests that global variables referencing themselves reuse the same node
-- while maintaining proper indentation at different tree depths

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load the Variables4 plugin
  local variables4_plugin = api:getPluginInstance(require('neodap.plugins.Variables4.alternative'))

  -- Load supporting plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))

  -- Set up debugging session with recursive reference fixture
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("NeodapLaunchClosest Variables")
  T.sleep(1500)

  -- Open the tree
  T.cmd("Variables4Tree")
  T.TerminalSnapshot('opened')

  -- Open Global scope
  T.cmd("execute \"normal j\"")      -- move down to Global
  T.cmd("execute \"normal \\<CR>\"") -- Expand Global scope
  T.TerminalSnapshot('global')

  -- Navigate manually to find the global variable (around line 27 from previous snapshots)
  T.cmd("normal! 22j") -- Move down to approximately where global variable should be
  T.TerminalSnapshot('navigated_to_global_var')

  -- Expand the global variable to see its recursive properties
  T.cmd("execute \"normal \\<CR>\"") -- Expand the global variable itself
  T.sleep(1200)                      -- Wait for expansion of large global object
  T.TerminalSnapshot('global_variable_expanded')

  -- If expansion worked, navigate down to see the recursive content
  T.cmd("normal! j") -- Move down into the expanded content
  T.TerminalSnapshot('first_item_in_global')

  -- Move down more to see if we can find AbortController
  T.cmd("normal! j") -- Move to second item
  T.TerminalSnapshot('second_item_in_global')

  T.cmd("normal! j") -- Move to third item
  T.TerminalSnapshot('third_item_in_global')
  -- -- First expand Local scope to find our recursive variables
  -- T.cmd("execute \"normal \\<CR>\"") -- Expand Local scope (should be first)
  -- T.sleep(300)
  -- T.TerminalSnapshot('recursive_local_expanded')

  -- -- Find and expand recursiveObj which contains self-references
  -- -- Navigate to recursiveObj variable
  -- T.sleep(100)
  -- T.cmd("execute \"normal j\"") -- Move to find recursiveObj
  -- T.sleep(100)
  -- T.cmd("execute \"normal j\"") -- Continue looking for recursiveObj
  -- T.sleep(100)
  -- T.TerminalSnapshot('recursive_found_recursiveobj')

  -- -- Expand recursiveObj to see its properties including self-reference
  -- T.cmd("execute \"normal \\<CR>\"") -- Expand recursiveObj
  -- T.sleep(400)
  -- T.TerminalSnapshot('recursive_obj_expanded')

  -- -- Navigate to the 'self' property which should reference the same object
  -- T.cmd("execute \"normal j\"") -- Move down to navigate through properties
  -- T.sleep(100)
  -- T.cmd("execute \"normal j\"") -- Move to 'self' property
  -- T.sleep(100)
  -- T.cmd("execute \"normal j\"") -- Find the self reference
  -- T.sleep(100)
  -- T.TerminalSnapshot('recursive_found_self_property')

  -- -- Expand the self-reference - this should reuse the same node
  -- T.cmd("execute \"normal \\<CR>\"") -- Expand self-reference
  -- T.sleep(400)
  -- T.TerminalSnapshot('recursive_self_expanded')

  -- -- Navigate into the nested self-reference to check indentation
  -- T.cmd("execute \"normal j\"") -- Move into nested self-reference
  -- T.sleep(100)
  -- T.cmd("execute \"normal j\"") -- Navigate deeper
  -- T.sleep(100)
  -- T.TerminalSnapshot('recursive_nested_indentation')

  -- -- Navigate even deeper to verify proper indentation levels
  -- T.cmd("execute \"normal j\"") -- Move down
  -- T.sleep(100)
  -- T.cmd("execute \"normal j\"") -- Move down
  -- T.sleep(100)
  -- T.TerminalSnapshot('recursive_indentation_check')

  -- -- Test collapsing and re-expanding to verify node reuse
  -- T.cmd("execute \"normal k\"")      -- Move back up
  -- T.sleep(100)
  -- T.cmd("execute \"normal k\"")      -- Move back up to expandable node
  -- T.sleep(100)
  -- T.cmd("execute \"normal \\<CR>\"") -- Collapse the node
  -- T.sleep(200)
  -- T.TerminalSnapshot('recursive_collapsed')

  -- -- Re-expand to verify same node is reused
  -- T.cmd("execute \"normal \\<CR>\"") -- Re-expand the node
  -- T.sleep(300)
  -- T.TerminalSnapshot('recursive_re_expanded')

  -- -- Test Global scope recursive reference
  -- -- First collapse the current expansions and navigate to Global scope
  -- T.cmd("execute \"normal gg\"")     -- Go to top of tree
  -- T.sleep(100)
  -- T.cmd("execute \"normal j\"")      -- Move to Global scope
  -- T.sleep(100)
  -- T.cmd("execute \"normal \\<CR>\"") -- Expand Global scope
  -- T.sleep(800)                       -- Global expansion takes longer
  -- T.TerminalSnapshot('recursive_global_scope_expanded')

  -- -- Look for our globalRecursive variable we added to globalThis
  -- -- Navigate through global variables to find globalRecursive
  -- T.cmd("execute \"normal /globalRecursive\"") -- Search for globalRecursive
  -- T.sleep(200)
  -- T.cmd("execute \"normal \\<CR>\"")           -- Go to search result
  -- T.sleep(100)
  -- T.TerminalSnapshot('recursive_found_global_recursive')

  -- -- Expand globalRecursive to see its self-reference
  -- T.cmd("execute \"normal \\<CR>\"") -- Expand globalRecursive
  -- T.sleep(400)
  -- T.TerminalSnapshot('recursive_global_obj_expanded')

  -- -- Find and expand the 'global' property which references globalThis
  -- T.cmd("execute \"normal j\"") -- Navigate to properties
  -- T.sleep(100)
  -- T.cmd("execute \"normal j\"") -- Find 'global' property
  -- T.sleep(100)
  -- T.TerminalSnapshot('recursive_found_global_property')

  -- -- Expand the global property - this creates a very deep recursive reference
  -- T.cmd("execute \"normal \\<CR>\"") -- Expand global reference
  -- T.sleep(600)                       -- Allow time for deep recursive expansion
  -- T.TerminalSnapshot('recursive_global_reference_expanded')

  -- -- Close the tree
  -- T.cmd("execute \"normal q\"") -- Close popup
  -- T.sleep(200)
  -- T.TerminalSnapshot('recursive_test_complete')
end)


--[[ TERMINAL SNAPSHOT: opened
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

--[[ TERMINAL SNAPSHOT: global
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

--[[ TERMINAL SNAPSHOT: navigated_to_global_var
Size: 24x80
Cursor: [24, 0] (line 24, col 0)
Mode: n

17| // Test fixture for Variables plugin - various variable types
18| 
19| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
20|     // │  ▶ 󰊕 Crypto: ƒ () { mod ??= requir...                          │
21|     let│  ▶ 󰊕 CryptoKey: ƒ () { mod ??= requir...                       │
22|     let│  ▶ 󰊕 DecompressionStream: ƒ () { mod ??= requir...             │
23|     let│  ▶ 󰊕 DOMException: () => { const DOMExcep...                   │
24|     let│  ▶ 󰊕 fetch: ƒ fetch(input, init = undefined) { /...            │
25|     let│  ▶ 󰊕 File: ƒ () { mod ??= requir...                            │
26|     let│  ▶ 󰊕 FormData: ƒ () { mod ??= requir...                        │lue";
27|     let│  ▶ 󰀬 global: global {global: global, clearImmediat...          │e trunc
28| ated wh│  ▶ 󰊕 Headers: ƒ () { mod ??= requir...                         │
29|        │  ▶ 󰊕 MessageChannel: ƒ () { mod ??= requir...                  │
30|     // │  ▶ 󰊕 MessageEvent: ƒ () { mod ??= requir...                    │
31|     let│  ▶ 󰊕 MessagePort: ƒ () { mod ??= requir...                     │
32|     let│  ▶ 󰊕 performance: ƒ () { if (check !== ...                     │
33|        │  ▶ 󰊕 Performance: ƒ () { mod ??= requir...                     │
34|        │  ▶ 󰊕 PerformanceEntry: ƒ () { mod ??= requir...                │
35|        ╰────────────────────────────────────────────────────────────────╯
36|             level: 2,
37|             data: ["a", "b", "c"]
38|         },
39| lua/testing/fixtures/variables/complex.js                     1,1            Top
40|                                                               24,1          13%
]]

--[[ TERMINAL SNAPSHOT: global_variable_expanded
Size: 24x80
Cursor: [24, 0] (line 24, col 0)
Mode: n

17| // Test fixture for Variables plugin - various variable types
18| 
19| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
20|     // │  ▶ 󰊕 Crypto: ƒ () { mod ??= requir...                          │
21|     let│  ▶ 󰊕 CryptoKey: ƒ () { mod ??= requir...                       │
22|     let│  ▶ 󰊕 DecompressionStream: ƒ () { mod ??= requir...             │
23|     let│  ▶ 󰊕 DOMException: () => { const DOMExcep...                   │
24|     let│  ▶ 󰊕 fetch: ƒ fetch(input, init = undefined) { /...            │
25|     let│  ▶ 󰊕 File: ƒ () { mod ??= requir...                            │
26|     let│  ▶ 󰊕 FormData: ƒ () { mod ??= requir...                        │lue";
27|     let│  ▼ 󰀬 global: global {global: global, clearImmediat...          │e trunc
28| ated wh│    ▶ 󰊕 AbortController: ƒ () { mod ??= requir...               │
29|        │    ▶ 󰊕 AbortSignal: ƒ () { mod ??= requir...                   │
30|     // │    ▶ 󰊕 atob: ƒ () { mod ??= requir...                          │
31|     let│    ▶ 󰊕 Blob: ƒ () { mod ??= requir...                          │
32|     let│    ▶ 󰊕 BroadcastChannel: ƒ () { mod ??= requir...              │
33|        │    ▶ 󰊕 btoa: ƒ () { mod ??= requir...                          │
34|        │    ▶ 󰊕 Buffer: ƒ get() { return _Buf...                        │
35|        ╰────────────────────────────────────────────────────────────────╯
36|             level: 2,
37|             data: ["a", "b", "c"]
38|         },
39| lua/testing/fixtures/variables/complex.js                     1,1            Top
40|                                                               24,1           6%
]]

--[[ TERMINAL SNAPSHOT: first_item_in_global
Size: 24x80
Cursor: [25, 0] (line 25, col 0)
Mode: n

17| // Test fixture for Variables plugin - various variable types
18| 
19| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
20|     // │  ▶ 󰊕 Crypto: ƒ () { mod ??= requir...                          │
21|     let│  ▶ 󰊕 CryptoKey: ƒ () { mod ??= requir...                       │
22|     let│  ▶ 󰊕 DecompressionStream: ƒ () { mod ??= requir...             │
23|     let│  ▶ 󰊕 DOMException: () => { const DOMExcep...                   │
24|     let│  ▶ 󰊕 fetch: ƒ fetch(input, init = undefined) { /...            │
25|     let│  ▶ 󰊕 File: ƒ () { mod ??= requir...                            │
26|     let│  ▶ 󰊕 FormData: ƒ () { mod ??= requir...                        │lue";
27|     let│  ▼ 󰀬 global: global {global: global, clearImmediat...          │e trunc
28| ated wh│    ▶ 󰊕 AbortController: ƒ () { mod ??= requir...               │
29|        │    ▶ 󰊕 AbortSignal: ƒ () { mod ??= requir...                   │
30|     // │    ▶ 󰊕 atob: ƒ () { mod ??= requir...                          │
31|     let│    ▶ 󰊕 Blob: ƒ () { mod ??= requir...                          │
32|     let│    ▶ 󰊕 BroadcastChannel: ƒ () { mod ??= requir...              │
33|        │    ▶ 󰊕 btoa: ƒ () { mod ??= requir...                          │
34|        │    ▶ 󰊕 Buffer: ƒ get() { return _Buf...                        │
35|        ╰────────────────────────────────────────────────────────────────╯
36|             level: 2,
37|             data: ["a", "b", "c"]
38|         },
39| lua/testing/fixtures/variables/complex.js                     1,1            Top
40|                                                               25,1           6%
]]

--[[ TERMINAL SNAPSHOT: second_item_in_global
Size: 24x80
Cursor: [26, 0] (line 26, col 0)
Mode: n

17| // Test fixture for Variables plugin - various variable types
18| 
19| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
20|     // │  ▶ 󰊕 Crypto: ƒ () { mod ??= requir...                          │
21|     let│  ▶ 󰊕 CryptoKey: ƒ () { mod ??= requir...                       │
22|     let│  ▶ 󰊕 DecompressionStream: ƒ () { mod ??= requir...             │
23|     let│  ▶ 󰊕 DOMException: () => { const DOMExcep...                   │
24|     let│  ▶ 󰊕 fetch: ƒ fetch(input, init = undefined) { /...            │
25|     let│  ▶ 󰊕 File: ƒ () { mod ??= requir...                            │
26|     let│  ▶ 󰊕 FormData: ƒ () { mod ??= requir...                        │lue";
27|     let│  ▼ 󰀬 global: global {global: global, clearImmediat...          │e trunc
28| ated wh│    ▶ 󰊕 AbortController: ƒ () { mod ??= requir...               │
29|        │    ▶ 󰊕 AbortSignal: ƒ () { mod ??= requir...                   │
30|     // │    ▶ 󰊕 atob: ƒ () { mod ??= requir...                          │
31|     let│    ▶ 󰊕 Blob: ƒ () { mod ??= requir...                          │
32|     let│    ▶ 󰊕 BroadcastChannel: ƒ () { mod ??= requir...              │
33|        │    ▶ 󰊕 btoa: ƒ () { mod ??= requir...                          │
34|        │    ▶ 󰊕 Buffer: ƒ get() { return _Buf...                        │
35|        ╰────────────────────────────────────────────────────────────────╯
36|             level: 2,
37|             data: ["a", "b", "c"]
38|         },
39| lua/testing/fixtures/variables/complex.js                     1,1            Top
40|                                                               26,1           6%
]]

--[[ TERMINAL SNAPSHOT: third_item_in_global
Size: 24x80
Cursor: [27, 0] (line 27, col 0)
Mode: n

17| // Test fixture for Variables plugin - various variable types
18| 
19| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
20|     // │  ▶ 󰊕 Crypto: ƒ () { mod ??= requir...                          │
21|     let│  ▶ 󰊕 CryptoKey: ƒ () { mod ??= requir...                       │
22|     let│  ▶ 󰊕 DecompressionStream: ƒ () { mod ??= requir...             │
23|     let│  ▶ 󰊕 DOMException: () => { const DOMExcep...                   │
24|     let│  ▶ 󰊕 fetch: ƒ fetch(input, init = undefined) { /...            │
25|     let│  ▶ 󰊕 File: ƒ () { mod ??= requir...                            │
26|     let│  ▶ 󰊕 FormData: ƒ () { mod ??= requir...                        │lue";
27|     let│  ▼ 󰀬 global: global {global: global, clearImmediat...          │e trunc
28| ated wh│    ▶ 󰊕 AbortController: ƒ () { mod ??= requir...               │
29|        │    ▶ 󰊕 AbortSignal: ƒ () { mod ??= requir...                   │
30|     // │    ▶ 󰊕 atob: ƒ () { mod ??= requir...                          │
31|     let│    ▶ 󰊕 Blob: ƒ () { mod ??= requir...                          │
32|     let│    ▶ 󰊕 BroadcastChannel: ƒ () { mod ??= requir...              │
33|        │    ▶ 󰊕 btoa: ƒ () { mod ??= requir...                          │
34|        │    ▶ 󰊕 Buffer: ƒ get() { return _Buf...                        │
35|        ╰────────────────────────────────────────────────────────────────╯
36|             level: 2,
37|             data: ["a", "b", "c"]
38|         },
39| lua/testing/fixtures/variables/complex.js                     1,1            Top
40|                                                               27,1           6%
]]