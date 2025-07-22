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

  -- Expand Local scope
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(800)

  -- Navigate down to arrayVar (it should be the second item)
  T.cmd("normal! j")
  -- Expand arrayVar
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(800)
  T.TerminalSnapshot('array_with_indices')
end)




--[[ TERMINAL SNAPSHOT: array_with_indices
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| ▾ 󰌾 Local: testVariables│// Test fixture for Variables plugin - various variable
 2| ├─▾ 󰅪 arrayVar Array[5] │ types
 3| │ ├─  󰎠 [0]: 1          │
 4| │ ├─  󰎠 [1]: 2          │function testVariables() {
 5| │ ├─  󰎠 [2]: 3          │    // Primitive types
 6| │ ├─  󰀫 [3]: 'four'     │    let numberVar = 42;
 7| │ ├─  󰆩 [4] Object      │    let stringVar = "Hello, Debug!";
 8| │ ├─  󰎠 length: 5       │    let booleanVar = true;
 9| │ ├─  󰅪 [{Prototype}] Ar│    let nullVar = null;
10| │ ├─  󰆩 [{Prototype}] Ob│    let undefinedVar = undefined;
11| ├─  ◯ booleanVar: true  │    let veryLongVariableNameThatExceedsNormalLimitsForD
12| ├─  󰀫 dateVar: Jan 01, 2│isplay = "short value";
13| ├─  󰊕 functionVar Functi│    let longStringValue = "This is a very long string v
14| ├─  󰀫 longStringValue: '│alue that should be truncated when displayed in the tre
15| ├─  󰘿 mapVar Map(2)     │e view to prevent line wrapping";
16| ├─  󰀫 nullVar: null     │
17| ├─  󰎠 numberVar: 42     │    // Complex types
18| ├─  󰆩 objectVar Object  │    let arrayVar = [1, 2, 3, "four", { five: 5 }];
19| ├─  󰏗 setVar Set(4)     │    let objectVar = {
20| ├─  󰀫 stringVar: 'Hello,│        name: "Test Object",
21| ├─  󰅩 this global       │        count: 100,
22| ├─  󰇨 undefinedVar: unde│        nested: {
23| <ables [RO] 2,1      Top <sting/fixtures/variables/complex.js 1,1            Top
24| 
]]