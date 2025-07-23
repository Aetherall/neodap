local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.Variables'))

  -- Use the complex variables fixture
  T.cmd("edit lua/testing/fixtures/variables/complex.js")

  -- Launch with the Variables config  
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(2000) -- Give time for debugger to hit the debugger statement

  -- Open Variables window
  T.cmd("VariablesShow")
  T.sleep(500)

  -- Navigate to Variables window
  T.cmd("wincmd h")
  T.sleep(300)

  -- Expand Local scope to see variables
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(800)
  
  -- Wait for inline previews to load
  T.sleep(500)
  
  T.TerminalSnapshot('variables_with_previews')
end)

--[[ TERMINAL SNAPSHOT: variables_with_previews
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| ▾ 󰌾 Local: testVariables│// Test fixture for Variables plugin - various variable
 2| ├─  󰅪 arrayVar [1, 2, 3,│ types
 3| ├─  ◯ booleanVar: true  │
 4| ├─  󰀫 dateVar: Jan 01, 2│function testVariables() {
 5| ├─  󰊕 functionVar Functi│    // Primitive types
 6| ├─  󰀫 longStringValue: '│    let numberVar = 42;
 7| ├─  󰘿 mapVar Map(2)     │    let stringVar = "Hello, Debug!";
 8| ├─  󰀫 nullVar: null     │    let booleanVar = true;
 9| ├─  󰎠 numberVar: 42     │    let nullVar = null;
10| ├─  󰆩 objectVar {count: │    let undefinedVar = undefined;
11| ├─  󰏗 setVar Set(4)     │    let veryLongVariableNameThatExceedsNormalLimitsForD
12| ├─  󰀫 stringVar: 'Hello,│isplay = "short value";
13| ├─  󰅩 this global       │    let longStringValue = "This is a very long string v
14| ├─  󰇨 undefinedVar: unde│alue that should be truncated when displayed in the tre
15| ├─  󰀫 veryLongVariableNa│e view to prevent line wrapping";
16|   󰇧 Global              │
17| ~                       │    // Complex types
18| ~                       │    let arrayVar = [1, 2, 3, "four", { five: 5 }];
19| ~                       │    let objectVar = {
20| ~                       │        name: "Test Object",
21| ~                       │        count: 100,
22| ~                       │        nested: {
23| <ables [RO] 1,1      All <sting/fixtures/variables/complex.js 1,1            Top
24| 
]]