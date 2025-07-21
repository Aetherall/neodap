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
  
  -- Use the loop fixture
  T.cmd("edit lua/testing/fixtures/loop/loop.js")
  
  -- Set breakpoint and launch
  T.cmd("normal! 2j")  -- Move to line 3
  T.cmd("NeodapLaunchClosest Loop [loop]")
  T.cmd("NeodapToggleBreakpoint")
  T.sleep(2000)  -- Wait for breakpoint to hit
  
  -- Add delay to ensure frame is set
  T.sleep(300)
  
  -- Open Variables window
  T.cmd("NeodapVariablesShow")
  T.sleep(1000)
  
  -- Navigate to Variables window
  T.cmd("wincmd h")
  T.sleep(300)
  
  -- Level 1: Expand Global scope
  T.cmd("normal! jj")  -- Move to Global
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(1000)
  
  -- Level 2: Navigate to clearInterval
  T.cmd("normal! 10j")  -- Move to clearInterval
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(600)
  
  -- Level 3: Expand 'arguments' property
  T.cmd("normal! j")  -- Move to arguments
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(600)
  
  -- Level 4: The arguments itself has 'arguments' - expand it
  T.cmd("normal! j")  -- Move to nested arguments
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500)
  
  -- Level 5: Go into the nested arguments properties
  T.cmd("normal! j")  -- Move to first property
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500)
  
  -- Final snapshot showing 5 levels:
  -- Global → clearInterval → arguments → arguments → property
  T.TerminalSnapshot('five_levels_deep')
end)

--[[ TERMINAL SNAPSHOT: five_levels_deep
Size: 24x80
Cursor: [16, 0] (line 16, col 0)
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
15|    │ │  arguments: ƒ ()                │~
16|    │ │ │  arguments: ƒ ()              │~
17|    │ │ │ │  arguments: ƒ ()            │~
18|    │ │ │ │  caller: ƒ ()               │~
19|    │ │ │ │ * length: 0                  │~
20|    │ │ │ │ * name: ''                   │~
21|    │ │ │ │  [[Prototype]]: ƒ ()        │~
22|    │ │ │ └  [[Scopes]]: Scopes[0]      │~
23| <e variables [1] [RO] 16,1           Top <xtures/loop/loop.js 3,1-2          All
24| 
]]