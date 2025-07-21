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
  T.cmd("normal! 2j")  -- Move to line 3
  
  -- Launch with the Loop config
  T.cmd("NeodapLaunchClosest Loop [loop]")
  
  -- Set a breakpoint and wait for it to hit
  T.cmd("NeodapToggleBreakpoint")
  T.sleep(2000)  -- Give time for breakpoint to be hit
  
  -- Add a small delay to ensure the frame is properly set
  T.sleep(300)
  
  -- Open Variables window
  T.cmd("NeodapVariablesShow")
  T.sleep(1000)  -- Give time for Neo-tree to render and load scopes
  
  -- Navigate to Variables window
  T.cmd("wincmd h")
  T.sleep(300)
  
  -- Navigate to Global scope and expand it
  T.cmd("normal! jj")  -- Move to Global
  T.cmd("execute \"normal \\<CR>\"")  -- Expand Global
  T.sleep(1500)  -- Wait for global variables to load
  T.TerminalSnapshot('global_expanded')
  
  -- Navigate down and find an object to expand
  T.cmd("normal! 10j")  -- Move down to find Buffer or another object
  
  -- Expand whatever we're on
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(1000)
  T.TerminalSnapshot('nested_object_expanded')
  
  -- Navigate into the object's properties and expand one more level
  T.cmd("normal! j")  -- Move to first property
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(800)
  T.TerminalSnapshot('deep_nested_property')
end)

--[[ TERMINAL SNAPSHOT: global_expanded
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|   Closure                              │setInterval(() => {
 3|   Global                               │●  ◆console.log("A Loop iteration:", i+
 4|     AbortController: ƒ () {       mod ?│+);
 5|     AbortSignal: ƒ () {       mod ??= r│  console.log("B Loop iteration:", i++)
 6|     atob: ƒ () {       mod ??= require(│;
 7|     Blob: ƒ () {       mod ??= require(│  console.log("C Loop iteration:", i++)
 8|     BroadcastChannel: ƒ () {       mod │;
 9|     btoa: ƒ () {       mod ??= require(│  console.log("D Loop iteration:", i++)
10|     Buffer: ƒ get() {       return _Buf│;
11|     ByteLengthQueuingStrategy: ƒ () {  │}, 1000);
12|     clearImmediate: ƒ clearImmediate(im│~
13|     clearInterval: ƒ clearInterval(time│~
14|     clearTimeout: ƒ clearTimeout(timer)│~
15|     CompressionStream: ƒ () {       mod│~
16|     CountQueuingStrategy: ƒ () {       │~
17|     crypto: ƒ () {       if (check !== │~
18|     Crypto: ƒ () {       mod ??= requir│~
19|     CryptoKey: ƒ () {       mod ??= req│~
20|     DecompressionStream: ƒ () {       m│~
21|     DOMException: () => {              │~
22|     fetch: ƒ fetch(input, init = undefi│~
23| <e variables [1] [RO] 3,1            Top <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: nested_object_expanded
Size: 24x80
Cursor: [13, 0] (line 13, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|   Closure                              │setInterval(() => {
 3|   Global                               │●  ◆console.log("A Loop iteration:", i+
 4|     AbortController: ƒ () {       mod ?│+);
 5|     AbortSignal: ƒ () {       mod ??= r│  console.log("B Loop iteration:", i++)
 6|     atob: ƒ () {       mod ??= require(│;
 7|     Blob: ƒ () {       mod ??= require(│  console.log("C Loop iteration:", i++)
 8|     BroadcastChannel: ƒ () {       mod │;
 9|     btoa: ƒ () {       mod ??= require(│  console.log("D Loop iteration:", i++)
10|     Buffer: ƒ get() {       return _Buf│;
11|     ByteLengthQueuingStrategy: ƒ () {  │}, 1000);
12|     clearImmediate: ƒ clearImmediate(im│~
13|     clearInterval: ƒ clearInterval(time│~
14|    │  arguments: ƒ ()                  │~
15|    │  caller: ƒ ()                     │~
16|    │ * length: 1                        │~
17|    │ * name: 'clearInterval'            │~
18|    │  prototype: {constructor: ƒ}      │~
19|    │ * [[FunctionLocation]]: @ <node_int│~
20|    │  [[Prototype]]: ƒ ()              │~
21|    └  [[Scopes]]: Scopes[2]            │~
22|     clearTimeout: ƒ clearTimeout(timer)│~
23| <e variables [1] [RO] 13,1           Top <xtures/loop/loop.js 3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: deep_nested_property
Size: 24x80
Cursor: [14, 0] (line 14, col 0)
Mode: n

 1|   Local                                │let i = 0;
 2|   Closure                              │setInterval(() => {
 3|   Global                               │●  ◆console.log("A Loop iteration:", i+
 4|     AbortController: ƒ () {       mod ?│+);
 5|     AbortSignal: ƒ () {       mod ??= r│  console.log("B Loop iteration:", i++)
 6|     atob: ƒ () {       mod ??= require(│;
 7|     Blob: ƒ () {       mod ??= require(│  console.log("C Loop iteration:", i++)
 8|     BroadcastChannel: ƒ () {       mod │;
 9|     btoa: ƒ () {       mod ??= require(│  console.log("D Loop iteration:", i++)
10|     Buffer: ƒ get() {       return _Buf│;
11|     ByteLengthQueuingStrategy: ƒ () {  │}, 1000);
12|     clearImmediate: ƒ clearImmediate(im│~
13|     clearInterval: ƒ clearInterval(time│~
14|    │  arguments: ƒ ()                  │~
15|    │ │  arguments: ƒ ()                │~
16|    │ │  caller: ƒ ()                   │~
17|    │ │ * length: 0                      │~
18|    │ │ * name: ''                       │~
19|    │ │  [[Prototype]]: ƒ ()            │~
20|    │ └  [[Scopes]]: Scopes[0]          │~
21|    │  caller: ƒ ()                     │~
22|    │ * length: 1                        │~
23| <e variables [1] [RO] 14,1           Top <xtures/loop/loop.js 3,1-2          All
24| 
]]