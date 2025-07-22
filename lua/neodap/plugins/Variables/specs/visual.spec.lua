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

  -- Capture initial state
  T.TerminalSnapshot('visual_scopes')

  -- Expand Local scope to see primitive types
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(800)
  T.TerminalSnapshot('visual_primitives')

  -- Navigate to objectVar and expand it
  T.cmd("normal! /objectVar")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(600)
  T.TerminalSnapshot('visual_object_expanded')

  -- Navigate to arrayVar and expand it
  T.cmd("normal! gg")
  T.cmd("normal! /arrayVar")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(600)
  T.TerminalSnapshot('visual_array_expanded')

  -- Navigate to functionVar to see function formatting
  T.cmd("normal! gg")
  T.cmd("normal! /functionVar")
  T.sleep(200)
  T.TerminalSnapshot('visual_function_display')
end)







--[[ TERMINAL SNAPSHOT: visual_scopes
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   󰌾 Local: testVariables│// Test fixture for Variables plugin - various variable
 2|   󰇧 Global              │ types
 3| ~                       │
 4| ~                       │function testVariables() {
 5| ~                       │    // Primitive types
 6| ~                       │    let numberVar = 42;
 7| ~                       │    let stringVar = "Hello, Debug!";
 8| ~                       │    let booleanVar = true;
 9| ~                       │    let nullVar = null;
10| ~                       │    let undefinedVar = undefined;
11| ~                       │    let veryLongVariableNameThatExceedsNormalLimitsForD
12| ~                       │isplay = "short value";
13| ~                       │    let longStringValue = "This is a very long string v
14| ~                       │alue that should be truncated when displayed in the tre
15| ~                       │e view to prevent line wrapping";
16| ~                       │
17| ~                       │    // Complex types
18| ~                       │    let arrayVar = [1, 2, 3, "four", { five: 5 }];
19| ~                       │    let objectVar = {
20| ~                       │        name: "Test Object",
21| ~                       │        count: 100,
22| ~                       │        nested: {
23| <ables [RO] 1,1      All <sting/fixtures/variables/complex.js 1,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: visual_primitives
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| ▾ 󰅩 Local: testVariables│// Test fixture for Variables plugin - various variable
 2|     󰅪 arrayVar (Array)  │ types
 3|     ◯ booleanVar: true  │
 4|     󰀫 dateVar: Mon Jan 0│function testVariables() {
 5| 1 2024 01:00:00 GMT+0100│    // Primitive types
 6|  (Central...            │    let numberVar = 42;
 7|     󰊕 functionVar (Funct│    let stringVar = "Hello, Debug!";
 8| ion)                    │    let booleanVar = true;
 9|     󰘿 mapVar (Map)      │    let nullVar = null;
10|     󰀫 nullVar: null     │    let undefinedVar = undefined;
11|     󰎠 numberVar: 42     │
12|     󰆩 objectVar (Object)│    // Complex types
13|     󰏗 setVar (Set)      │    let arrayVar = [1, 2, 3, "four", { five: 5 }];
14|     󰀫 stringVar: "'Hello│    let objectVar = {
15| , Debug!'"              │        name: "Test Object",
16|     󰅩 this (global)     │        count: 100,
17|     󰇨 undefinedVar: unde│        nested: {
18| fined                   │            level: 2,
19|   󰇧 Global              │            data: ["a", "b", "c"]
20| ~                       │        },
21| ~                       │        method: function() { return "method"; }
22| ~                       │    };
23| <ables [RO] 1,1      All <sting/fixtures/variables/complex.js 1,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: visual_object_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| ▸ 󰅩 Local: testVariables│// Test fixture for Variables plugin - various variable
 2|   󰇧 Global              │ types
 3| ~                       │
 4| ~                       │function testVariables() {
 5| ~                       │    // Primitive types
 6| ~                       │    let numberVar = 42;
 7| ~                       │    let stringVar = "Hello, Debug!";
 8| ~                       │    let booleanVar = true;
 9| ~                       │    let nullVar = null;
10| ~                       │    let undefinedVar = undefined;
11| ~                       │
12| ~                       │    // Complex types
13| ~                       │    let arrayVar = [1, 2, 3, "four", { five: 5 }];
14| ~                       │    let objectVar = {
15| ~                       │        name: "Test Object",
16| ~                       │        count: 100,
17| ~                       │        nested: {
18| ~                       │            level: 2,
19| ~                       │            data: ["a", "b", "c"]
20| ~                       │        },
21| ~                       │        method: function() { return "method"; }
22| ~                       │    };
23| <ables [RO] 1,1      All <sting/fixtures/variables/complex.js 1,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: visual_array_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| ▾ 󰅩 Local: testVariables│// Test fixture for Variables plugin - various variable
 2|     󰅪 arrayVar (Array)  │ types
 3|     ◯ booleanVar: true  │
 4|     󰀫 dateVar: Mon Jan 0│function testVariables() {
 5| 1 2024 01:00:00 GMT+0100│    // Primitive types
 6|  (Central...            │    let numberVar = 42;
 7|     󰊕 functionVar (Funct│    let stringVar = "Hello, Debug!";
 8| ion)                    │    let booleanVar = true;
 9|     󰘿 mapVar (Map)      │    let nullVar = null;
10|     󰀫 nullVar: null     │    let undefinedVar = undefined;
11|     󰎠 numberVar: 42     │
12|     󰆩 objectVar (Object)│    // Complex types
13|     󰏗 setVar (Set)      │    let arrayVar = [1, 2, 3, "four", { five: 5 }];
14|     󰀫 stringVar: "'Hello│    let objectVar = {
15| , Debug!'"              │        name: "Test Object",
16|     󰅩 this (global)     │        count: 100,
17|     󰇨 undefinedVar: unde│        nested: {
18| fined                   │            level: 2,
19|   󰇧 Global              │            data: ["a", "b", "c"]
20| ~                       │        },
21| ~                       │        method: function() { return "method"; }
22| ~                       │    };
23| <ables [RO] 1,1      All <sting/fixtures/variables/complex.js 1,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: visual_function_display
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| ▾ 󰅩 Local: testVariables│// Test fixture for Variables plugin - various variable
 2|     󰅪 arrayVar (Array)  │ types
 3|     ◯ booleanVar: true  │
 4|     󰀫 dateVar: Mon Jan 0│function testVariables() {
 5| 1 2024 01:00:00 GMT+0100│    // Primitive types
 6|  (Central...            │    let numberVar = 42;
 7|     󰊕 functionVar (Funct│    let stringVar = "Hello, Debug!";
 8| ion)                    │    let booleanVar = true;
 9|     󰘿 mapVar (Map)      │    let nullVar = null;
10|     󰀫 nullVar: null     │    let undefinedVar = undefined;
11|     󰎠 numberVar: 42     │
12|     󰆩 objectVar (Object)│    // Complex types
13|     󰏗 setVar (Set)      │    let arrayVar = [1, 2, 3, "four", { five: 5 }];
14|     󰀫 stringVar: "'Hello│    let objectVar = {
15| , Debug!'"              │        name: "Test Object",
16|     󰅩 this (global)     │        count: 100,
17|     󰇨 undefinedVar: unde│        nested: {
18| fined                   │            level: 2,
19|   󰇧 Global              │            data: ["a", "b", "c"]
20| ~                       │        },
21| ~                       │        method: function() { return "method"; }
22| ~                       │    };
23| <ables [RO] 1,1      All <sting/fixtures/variables/complex.js 1,1            Top
24| 
]]