local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.BreakpointVirtualText'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  
  -- Create and register the NUI Variables implementation
  local VariablesTreeNui = require('neodap.plugins.Variables.nui_implementation')
  local variables_tree = VariablesTreeNui:new({ api = api })
  
  -- Use the loop fixture
  T.cmd("edit lua/testing/fixtures/loop/loop.js")
  
  -- Move to line 3 where we'll set a breakpoint
  T.cmd("normal! 2j")  -- Move to line 3
  
  -- Launch with the Loop config
  T.cmd("NeodapLaunchClosest Loop [loop]")
  
  -- Set a breakpoint and wait for it to hit
  T.cmd("NeodapToggleBreakpoint")
  T.sleep(2000)  -- Give time for breakpoint to be hit
  
  -- Add a small delay to ensure the frame is properly set
  T.sleep(300)
  
  -- Open Variables window using our NUI implementation
  T.cmd("VariablesShow")
  T.sleep(500)  -- Give time for window to render
  
  -- Navigate to Variables window
  T.cmd("wincmd h")
  T.sleep(300)
  
  -- Capture initial state with scopes
  T.TerminalSnapshot('nui_initial_scopes')
  
  -- Navigate to Global scope and expand it
  T.cmd("normal! jj")  -- Move to Global (third line)
  T.cmd("execute \"normal \\<CR>\"")  -- Expand Global
  T.sleep(1000)  -- Wait for variables to load
  T.TerminalSnapshot('nui_global_expanded')
  
  -- Navigate down to find an expandable variable (e.g., Buffer)
  T.cmd("normal! 10j")  -- Move down to find Buffer or another object
  
  -- Expand whatever we're on
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(800)
  T.TerminalSnapshot('nui_nested_expanded')
  
  -- Navigate into the object's properties and expand one more level
  T.cmd("normal! j")  -- Move to first property
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(600)
  T.TerminalSnapshot('nui_deep_nested')
  
  -- Test closing the window
  T.cmd("execute \"normal q\"")
  T.sleep(200)
  T.TerminalSnapshot('nui_window_closed')
  
  -- Test toggle to reopen
  T.cmd("VariablesToggle")
  T.sleep(300)
  T.TerminalSnapshot('nui_window_reopened')
end)


--[[ TERMINAL SNAPSHOT: nui_initial_scopes
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| ▸ 󰅩 Local                               │let i = 0;
 2| ▸ 󰅩 Closure                             │setInterval(() => {
 3| ▸ 󰅩 Global                              │●  ◆console.log("A Loop iteration:", i+
 4| ~                                       │+);
 5| ~                                       │  console.log("B Loop iteration:", i++)
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
23| <riables [1] 1,1                     All <xtures/loop/loop.js 3,1-2          All
24| 
]]


--[[ TERMINAL SNAPSHOT: nui_global_expanded
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| ▸ 󰅩 Local                               │let i = 0;
 2| ▸ 󰅩 Closure                             │setInterval(() => {
 3| ▾ 󰅩 Global                              │●  ◆console.log("A Loop iteration:", i+
 4|   ▸ 󰅩 AbortController (function)       │+);
 5|   ▸ 󰅩 AbortSignal (function)           │  console.log("B Loop iteration:", i++)
 6|   󰀫 atob: function atob() { [native co │;
 7|   ▸ 󰅩 Blob (function)                  │  console.log("C Loop iteration:", i++)
 8|   ▸ 󰅩 BroadcastChannel (function)      │;
 9|   󰀫 btoa: function btoa() { [native co │  console.log("D Loop iteration:", i++)
10|   ▸ 󰅩 Buffer (function)                │;
11|   ▸ 󰅩 ByteLengthQueuingStrategy (funct │}, 1000);
12|   ▸ 󰅩 clearImmediate (Function)        │~
13|   ▸ 󰅩 clearInterval (Function)         │~
14|   ▸ 󰅩 clearTimeout (Function)          │~
15|   ▸ 󰅩 CloseEvent (function)            │~
16|   ▸ 󰅩 CompressionStream (function)     │~
17|   ▸ 󰅩 console (Object)                 │~
18|   ▸ 󰅩 CountQueuingStrategy (function)  │~
19|   ▸ 󰅩 crypto (Crypto)                  │~
20|   ▸ 󰅩 Crypto (function)                │~
21|   ▸ 󰅩 CryptoKey (function)             │~
22|   󰀫 CustomEvent: [Getter]              │~
23| <riables [1] 3,1                     Top <xtures/loop/loop.js 3,1-2          All
24| 
]]


--[[ TERMINAL SNAPSHOT: nui_nested_expanded
Size: 24x80
Cursor: [13, 0] (line 13, col 0)
Mode: n

 1| ▸ 󰅩 Local                               │let i = 0;
 2| ▸ 󰅩 Closure                             │setInterval(() => {
 3| ▾ 󰅩 Global                              │●  ◆console.log("A Loop iteration:", i+
 4|   ▸ 󰅩 AbortController (function)       │+);
 5|   ▸ 󰅩 AbortSignal (function)           │  console.log("B Loop iteration:", i++)
 6|   󰀫 atob: function atob() { [native co │;
 7|   ▸ 󰅩 Blob (function)                  │  console.log("C Loop iteration:", i++)
 8|   ▸ 󰅩 BroadcastChannel (function)      │;
 9|   󰀫 btoa: function btoa() { [native co │  console.log("D Loop iteration:", i++)
10|   ▸ 󰅩 Buffer (function)                │;
11|   ▸ 󰅩 ByteLengthQueuingStrategy (funct │}, 1000);
12|   ▸ 󰅩 clearImmediate (Function)        │~
13|   ▾ 󰅩 clearInterval (Function)         │~
14|     ▸ 󰅩 arguments (function)            │~
15|     ▸ 󰅩 caller (function)               │~
16|     󰀫 length: 1                         │~
17|     󰀫 name: clearInterval               │~
18|     ▸ 󰅩 prototype (Object)              │~
19|     󰀫 [[FunctionLocation]]: node:timers │~
20|     ▸ 󰅩 [[Prototype]] (Function)        │~
21|     ▸ 󰅩 [[Scopes]] (Array)              │~
22|   ▸ 󰅩 clearTimeout (Function)          │~
23| <riables [1] 13,1                    Top <xtures/loop/loop.js 3,1-2          All
24| 
]]


--[[ TERMINAL SNAPSHOT: nui_deep_nested
Size: 24x80
Cursor: [14, 0] (line 14, col 0)
Mode: n

 1| ▸ 󰅩 Local                               │let i = 0;
 2| ▸ 󰅩 Closure                             │setInterval(() => {
 3| ▾ 󰅩 Global                              │●  ◆console.log("A Loop iteration:", i+
 4|   ▸ 󰅩 AbortController (function)       │+);
 5|   ▸ 󰅩 AbortSignal (function)           │  console.log("B Loop iteration:", i++)
 6|   󰀫 atob: function atob() { [native co │;
 7|   ▸ 󰅩 Blob (function)                  │  console.log("C Loop iteration:", i++)
 8|   ▸ 󰅩 BroadcastChannel (function)      │;
 9|   󰀫 btoa: function btoa() { [native co │  console.log("D Loop iteration:", i++)
10|   ▸ 󰅩 Buffer (function)                │;
11|   ▸ 󰅩 ByteLengthQueuingStrategy (funct │}, 1000);
12|   ▸ 󰅩 clearImmediate (Function)        │~
13|   ▾ 󰅩 clearInterval (Function)         │~
14|     ▾ 󰅩 arguments (function)            │~
15|       ▸ 󰅩 arguments (function)          │~
16|       ▸ 󰅩 caller (function)             │~
17|       󰀫 length: 0                       │~
18|       󰀫 name: throwTypeError            │~
19|       ▸ 󰅩 [[Prototype]] (Function)      │~
20|       ▸ 󰅩 [[Scopes]] (Array)            │~
21|     ▸ 󰅩 caller (function)               │~
22|     󰀫 length: 1                         │~
23| <riables [1] 14,1                    Top <xtures/loop/loop.js 3,1-2          All
24| 
]]


--[[ TERMINAL SNAPSHOT: nui_window_closed
Size: 24x80
Cursor: [3, 1] (line 3, col 1)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3| ●  ◆console.log("A Loop iteration:", i++);
 4|   console.log("B Loop iteration:", i++);
 5|   console.log("C Loop iteration:", i++);
 6|   console.log("D Loop iteration:", i++);
 7| }, 1000);
 8| ~
 9| ~
10| ~
11| ~
12| ~
13| ~
14| ~
15| ~
16| ~
17| ~
18| ~
19| ~
20| ~
21| ~
22| ~
23| lua/testing/fixtures/loop/loop.js 3,1-2                                     All
24| 
]]


--[[ TERMINAL SNAPSHOT: nui_window_reopened
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| ▸ 󰅩 Local                               │let i = 0;
 2| ▸ 󰅩 Closure                             │setInterval(() => {
 3| ▸ 󰅩 Global                              │●  ◆console.log("A Loop iteration:", i+
 4| ~                                       │+);
 5| ~                                       │  console.log("B Loop iteration:", i++)
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
23| <riables [1] 1,1                     All <xtures/loop/loop.js 3,1-2          All
24| 
]]