local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.BreakpointVirtualText'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables'))

  -- Set up neo-tree with the Variables source
  local neotree = require('neo-tree')
  neotree.setup({
    sources = {
      "neodap.plugins.Variables",
    }
  })

  -- Use the loop fixture that works reliably
  T.cmd("edit lua/testing/fixtures/loop/loop.js")

  -- Move to line 3 where we'll set a breakpoint
  T.cmd("normal! 2j") -- Move to line 3

  -- Launch with the Loop config
  T.cmd("NeodapLaunchClosest Loop [loop]")

  -- Set a breakpoint and wait for it to hit
  T.cmd("NeodapToggleBreakpoint")
  T.sleep(2000) -- Give time for breakpoint to be hit

  -- Add a small delay to ensure the frame is properly set
  T.sleep(300)

  -- Open Variables window
  T.cmd("NeodapVariablesShow")
  T.sleep(1000) -- Give time for Neo-tree to render and load scopes

  -- Navigate to Variables window
  T.cmd("wincmd h")
  T.sleep(300)

  -- Navigate to Global scope and expand it
  print("\n[TEST] About to expand Global scope")
  T.cmd("normal! jj")                -- Move to Global
  print("[TEST] Cursor moved to Global")
  T.cmd("execute \"normal \\<CR>\"") -- Expand Global
  print("[TEST] Sent expand command")
  T.sleep(1500)                      -- Wait for global variables to load
  print("[TEST] After sleep")
  T.TerminalSnapshot('global_expanded')

  -- Navigate down and find an object to expand
  T.cmd("normal! 10j") -- Move down to find Buffer or another object

  -- Expand whatever we're on
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(1000)
  T.TerminalSnapshot('nested_object_expanded')

  -- Navigate into the object's properties and expand one more level
  T.cmd("normal! j") -- Move to first property
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(800)
  T.TerminalSnapshot('deep_nested_property')
end)











--[[ TERMINAL SNAPSHOT: global_expanded
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1|  - Local                                │let i = 0;
 2| loading: Loading...                     │setInterval(() => {
 3|  - Closure                              │●  ◆console.log("A Loop iteration:", i+
 4|   + 󰀫 i: value                          │+);
 5|  + Global                               │  console.log("B Loop iteration:", i++)
 6| ~                                       │;
 7| ~                                       │  console.log("C Loop iteration:", i++)
 8| ~                                       │;
 9| ~                                       │  console.log("D Loop iteration:", i++)
10| ~                                       │;
11| ~                                       │}, 1000);
12| ~                                       │~
13| ~                                       │~
14| ~                                       │~
15| ~                                       │~
16| ~                                       │~
17| ~                                       │~
18| ~                                       │~
19| ~                                       │~
20| ~                                       │~
21| ~                                       │~
22| ~                                       │~
23| <e variables [1] [RO] 3,1            All <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: nested_object_expanded
Size: 24x80
Cursor: [13, 0] (line 13, col 0)
Mode: n

 1|   Local                                 │let i = 0;
 2|   Closure                               │setInterval(() => {
 3|   Global                                │●  ◆console.log("A Loop iteration:", i+
 4|     AbortController (function): value   │+);
 5|     AbortSignal (function): value       │  console.log("B Loop iteration:", i++)
 6|     atob (function): value              │;
 7|     Blob (function): value              │  console.log("C Loop iteration:", i++)
 8|     BroadcastChannel (function): value  │;
 9|     btoa (function): value              │  console.log("D Loop iteration:", i++)
10|     Buffer (function): value            │;
11|     ByteLengthQueuingStrategy (function)│}, 1000);
12|     clearImmediate (Function): value    │~
13|     clearInterval (Function): value     │~
14|       arguments (function): value       │~
15|       caller (function): value          │~
16|       length: value                     │~
17|       name: value                       │~
18|       prototype (Object): value         │~
19|       [{FunctionLocation}]: value       │~
20|       [{Prototype}] (Function): value   │~
21|       [{Scopes}] (Array): value         │~
22|     clearTimeout (Function): value      │~
23| <e variables [1] [RO] 13,1           Top <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: deep_nested_property
Size: 24x80
Cursor: [14, 0] (line 14, col 0)
Mode: n

 1|   Local                                 │let i = 0;
 2|   Closure                               │setInterval(() => {
 3|   Global                                │●  ◆console.log("A Loop iteration:", i+
 4|     AbortController (function): value   │+);
 5|     AbortSignal (function): value       │  console.log("B Loop iteration:", i++)
 6|     atob (function): value              │;
 7|     Blob (function): value              │  console.log("C Loop iteration:", i++)
 8|     BroadcastChannel (function): value  │;
 9|     btoa (function): value              │  console.log("D Loop iteration:", i++)
10|     Buffer (function): value            │;
11|     ByteLengthQueuingStrategy (function)│}, 1000);
12|     clearImmediate (Function): value    │~
13|     clearInterval (Function): value     │~
14|       arguments (function): value       │~
15|         arguments (function): value     │~
16|         caller (function): value        │~
17|         length: value                   │~
18|         name: value                     │~
19|         [{Prototype}] (Function): value │~
20|         [{Scopes}] (Array): value       │~
21|       caller (function): value          │~
22|       length: value                     │~
23| <e variables [1] [RO] 14,1           Top <xtures/loop/loop.js 3,1-2          All
24| 
]]