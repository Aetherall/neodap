-- Test for Variables plugin visibility adjustments with deep nesting
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.Variables'))

  -- Set up initial state and launch session
  T.cmd("edit lua/testing/fixtures/variables/deep_nested.js")
  T.cmd("NeodapLaunchClosest Deep Nested")

  -- Wait for session to start and hit breakpoint
  T.sleep(1500)

  -- Open Variables window
  T.cmd("VariablesShow")
  T.sleep(300)

  -- Navigate to Variables window
  T.cmd("wincmd h")
  T.TerminalSnapshot('initial_variables_window')

  -- Expand the first scope (Local)
  -- T.cmd("normal! jj")                -- Move to Local scope
  T.cmd("execute \"normal \\<CR>\"") -- Expand complexObject
  T.sleep(500)
  T.TerminalSnapshot('local_scope_expanded')

  -- Find and expand a deeply nested object
  -- Navigate to complexObject
  T.cmd("/complexObject")
  T.cmd("normal! n")
  T.sleep(100)
  T.cmd("execute \"normal \\<CR>\"") -- Expand complexObject
  T.sleep(300)
  T.TerminalSnapshot('complex_object_expanded')

  -- Navigate deeper into nested1
  T.cmd("/nested1")
  T.cmd("normal! n")
  T.sleep(100)
  T.cmd("execute \"normal \\<CR>\"") -- Expand nested1
  T.sleep(300)
  T.TerminalSnapshot('nested1_expanded_with_scroll')

  -- Go even deeper into nested2
  T.cmd("/nested2")
  T.cmd("normal! n")
  T.sleep(100)
  T.cmd("execute \"normal \\<CR>\"") -- Expand nested2
  T.sleep(300)
  T.TerminalSnapshot('nested2_expanded_deep_scroll')

  -- Expand a large array to test vertical scrolling
  T.cmd("gg") -- Go to top
  T.cmd("/deepArray")
  T.cmd("normal! n")
  T.sleep(100)
  T.cmd("execute \"normal \\<CR>\"") -- Expand array
  T.sleep(500)
  T.TerminalSnapshot('large_array_expanded_with_scroll')

  -- Test horizontal scrolling with very deep nesting
  T.cmd("/level6")
  T.cmd("normal! n")
  T.sleep(100)
  T.TerminalSnapshot('deep_nesting_horizontal_offset')
end)


--[[ TERMINAL SNAPSHOT: initial_variables_window
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   󰌾 Local: testDeepNesti│// Test fixture for Variables plugin - deeply nested st
 2|   󰇧 Global              │ructures for visibility testing
 3| ~                       │
 4| ~                       │function testDeepNesting() {
 5| ~                       │    // Create a deeply nested object structure
 6| ~                       │    let complexObject = {
 7| ~                       │        level1: {
 8| ~                       │            nested1: {
 9| ~                       │                nested2: {
10| ~                       │                    nested3: {
11| ~                       │                        nested4: {
12| ~                       │                            nested5: {
13| ~                       │                                level6: {
14| ~                       │                                    finalValue: "You fo
15| ~                       │und me!",
16| ~                       │                                    metadata: {
17| ~                       │                                        depth: 7,
18| ~                       │                                        path: "complexO
19| ~                       │bject.level1.nested1.nested2.nested3.nested4.nested5.le
20| ~                       │vel6"
21| ~                       │                                    }
22| ~                       │                                },
23| <ables [RO] 1,1      All <g/fixtures/variables/deep_nested.js 1,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: local_scope_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| ▾ 󰌾 Local: testDeepNesti│// Test fixture for Variables plugin - deeply nested st
 2| ├─  󰆩 complexObject {des│ructures for visibility testing
 3| ├─  󰅪 deepArray [{index:│
 4| ├─  󰆩 mixedStructure {us│function testDeepNesting() {
 5| ├─  󰅩 this global       │    // Create a deeply nested object structure
 6| ├─  󰆩 wideObject {proper│    let complexObject = {
 7|   󰇧 Global              │        level1: {
 8| ~                       │            nested1: {
 9| ~                       │                nested2: {
10| ~                       │                    nested3: {
11| ~                       │                        nested4: {
12| ~                       │                            nested5: {
13| ~                       │                                level6: {
14| ~                       │                                    finalValue: "You fo
15| ~                       │und me!",
16| ~                       │                                    metadata: {
17| ~                       │                                        depth: 7,
18| ~                       │                                        path: "complexO
19| ~                       │bject.level1.nested1.nested2.nested3.nested4.nested5.le
20| ~                       │vel6"
21| ~                       │                                    }
22| ~                       │                                },
23| <ables [RO] 1,1      All <g/fixtures/variables/deep_nested.js 1,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: complex_object_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| ▾ 󰌾 Local: testDeepNesti│// Test fixture for Variables plugin - deeply nested st
 2| ├─▾ 󰆩 complexObject {des│ructures for visibility testing
 3| │ ├─  󰀫 description: 'Ro│
 4| │ ├─  󰆩 level1 {data: 'L│function testDeepNesting() {
 5| │ ├─  󰆩 [{Prototype}] {_│    // Create a deeply nested object structure
 6| ├─  󰅪 deepArray [{index:│    let complexObject = {
 7| ├─  󰆩 mixedStructure {us│        level1: {
 8| ├─  󰅩 this global       │            nested1: {
 9| ├─  󰆩 wideObject {proper│                nested2: {
10|   󰇧 Global              │                    nested3: {
11| ~                       │                        nested4: {
12| ~                       │                            nested5: {
13| ~                       │                                level6: {
14| ~                       │                                    finalValue: "You fo
15| ~                       │und me!",
16| ~                       │                                    metadata: {
17| ~                       │                                        depth: 7,
18| ~                       │                                        path: "complexO
19| ~                       │bject.level1.nested1.nested2.nested3.nested4.nested5.le
20| ~                       │vel6"
21| ~                       │                                    }
22| ~                       │                                },
23| <ables [RO] 2,1      All <g/fixtures/variables/deep_nested.js 1,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: nested1_expanded_with_scroll
Size: 24x80
Cursor: [4, 47] (line 4, col 47)
Mode: n

 1|                         │// Test fixture for Variables plugin - deeply nested st
 2| iption: 'Root level', le│ructures for visibility testing
 3|  level'                 │
 4| el 1 data', nested1: {ne│function testDeepNesting() {
 5| ata'                    │    // Create a deeply nested object structure
 6| Level 2 info', nested2: │    let complexObject = {
 7| _proto__: ƒ(), __defineG│        level1: {
 8| roto__: ƒ(), __defineGet│            nested1: {
 9| ,..., {index: 1,..., {in│                nested2: {
10| s: {admins:..., [{Protot│                    nested3: {
11|                         │                        nested4: {
12| _0: {value: 0,..., prope│                            nested5: {
13|                         │                                level6: {
14| ~                       │                                    finalValue: "You fo
15| ~                       │und me!",
16| ~                       │                                    metadata: {
17| ~                       │                                        depth: 7,
18| ~                       │                                        path: "complexO
19| ~                       │bject.level1.nested1.nested2.nested3.nested4.nested5.le
20| ~                       │vel6"
21| ~                       │                                    }
22| ~                       │                                },
23| <ables [RO] 4,48-37  All <g/fixtures/variables/deep_nested.js 1,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: nested2_expanded_deep_scroll
Size: 24x80
Cursor: [6, 52] (line 6, col 52)
Mode: n

 1|                         │// Test fixture for Variables plugin - deeply nested st
 2| iption: 'Root level', le│ructures for visibility testing
 3|  level'                 │
 4| el 1 data', nested1: {ne│function testDeepNesting() {
 5| ata'                    │    // Create a deeply nested object structure
 6| Level 2 info', nested2: │    let complexObject = {
 7|  info'                  │        level1: {
 8| : (5) [10,..., nested3: │            nested1: {
 9| {__proto__: ƒ(), __defin│                nested2: {
10| _proto__: ƒ(), __defineG│                    nested3: {
11| roto__: ƒ(), __defineGet│                        nested4: {
12| ,..., {index: 1,..., {in│                            nested5: {
13| s: {admins:..., [{Protot│                                level6: {
14|                         │                                    finalValue: "You fo
15| _0: {value: 0,..., prope│und me!",
16|                         │                                    metadata: {
17| ~                       │                                        depth: 7,
18| ~                       │                                        path: "complexO
19| ~                       │bject.level1.nested1.nested2.nested3.nested4.nested5.le
20| ~                       │vel6"
21| ~                       │                                    }
22| ~                       │                                },
23| <ables [RO] 6,53-40  All <g/fixtures/variables/deep_nested.js 1,1            Top
24| 
]]