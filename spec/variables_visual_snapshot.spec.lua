-- Visual verification test for Variables plugin
-- This test generates snapshots to visually verify the Variables tree displays correctly
-- and allows recursive navigation through complex variable structures

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  local variables_plugin = api:getPluginInstance(require('neodap.plugins.Variables'))

  -- Set up neo-tree with the Variables source
  local neotree = require('neo-tree')
  neotree.setup({
    sources = {
      "neodap.plugins.Variables",
    },
    variables = {
      window = {
        position = "right",
        width = 40,
      }
    }
  })

  -- Change to the fixture directory and open the file
  T.cmd("cd lua/testing/fixtures/variables")
  T.cmd("edit complex.js")

  -- Take initial snapshot before debugging
  T.TerminalSnapshot('01_initial_file')

  -- Launch the debug session - this will hit the debugger statement
  T.cmd("NeodapLaunchClosest Variables [variables]")

  -- Wait for debugger to start and hit breakpoint
  T.sleep(2000)

  -- Take snapshot showing stopped at debugger
  T.TerminalSnapshot('02_stopped_at_debugger')

  -- Open the Variables window to show the DAP variables tree
  T.cmd("NeodapVariablesShow")
  T.sleep(500)

  -- Take snapshot showing the Variables window with scopes
  T.TerminalSnapshot('03_variables_window_scopes')

  -- Focus on the Variables window to interact with it
  T.cmd("NeodapVariablesFocus")
  T.sleep(100)

  -- Expand the first scope (Local) using Enter key
  T.cmd("normal! \r")
  T.sleep(1000)

  -- Take snapshot showing expanded Local scope with all variables
  T.TerminalSnapshot('04_local_scope_expanded')

  -- Navigate to objectVar and expand it (should be around line 13)
  T.cmd("normal! 13gg")
  T.sleep(100)
  T.cmd("normal! \r")
  T.sleep(500)

  -- Take snapshot showing expanded objectVar with its properties
  T.TerminalSnapshot('05_object_var_expanded')

  -- Navigate to nested property and expand it
  T.cmd("normal! jjj") -- Move down to 'nested' property
  T.sleep(100)
  T.cmd("normal! \r")
  T.sleep(500)

  -- Take snapshot showing recursive expansion of nested object
  T.TerminalSnapshot('06_nested_object_expanded')

  -- Navigate to arrayVar and expand it
  T.cmd("normal! gg")   -- Go to top
  T.sleep(100)
  T.cmd("normal! 11gg") -- Go to arrayVar line
  T.sleep(100)
  T.cmd("normal! \r")
  T.sleep(500)

  -- Take snapshot showing expanded array with indices
  T.TerminalSnapshot('07_array_var_expanded')

  -- Expand the object inside the array (index 4)
  T.cmd("normal! jjjjj") -- Move to index 4
  T.sleep(100)
  T.cmd("normal! \r")
  T.sleep(500)

  -- Take snapshot showing object inside array expanded
  T.TerminalSnapshot('08_array_object_expanded')

  -- Navigate to mapVar and expand it
  T.cmd("normal! gg")   -- Go to top
  T.sleep(100)
  T.cmd("normal! 27gg") -- Navigate to mapVar
  T.sleep(100)
  T.cmd("normal! \r")
  T.sleep(500)

  -- Take snapshot showing Map variable expanded
  T.TerminalSnapshot('09_map_var_expanded')

  -- Collapse some nodes to show collapse functionality
  T.cmd("normal! gg") -- Go to top
  T.sleep(100)
  T.cmd("normal! \r") -- Collapse Local scope
  T.sleep(500)

  -- Take snapshot showing collapsed scope
  T.TerminalSnapshot('10_scope_collapsed')

  -- Expand multiple scopes to show all available scopes
  T.cmd("normal! \r") -- Re-expand Local
  T.sleep(500)
  T.cmd("normal! G")  -- Go to bottom to find other scopes
  T.sleep(100)
  T.cmd("normal! \r") -- Expand another scope if available
  T.sleep(500)

  -- Final snapshot showing full variable tree navigation
  T.TerminalSnapshot('11_final_full_tree')
end)



--[[ TERMINAL SNAPSHOT: 01_initial_file
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| function testVariables() {
 4|     // Primitive types
 5|     let numberVar = 42;
 6|     let stringVar = "Hello, Debug!";
 7|     let booleanVar = true;
 8|     let nullVar = null;
 9|     let undefinedVar = undefined;
10| 
11|     // Complex types
12|     let arrayVar = [1, 2, 3, "four", { five: 5 }];
13|     let objectVar = {
14|         name: "Test Object",
15|         count: 100,
16|         nested: {
17|             level: 2,
18|             data: ["a", "b", "c"]
19|         },
20|         method: function() { return "method"; }
21|     };
22| 
23| complex.js                                                    1,1            Top
24| 
]]


--[[ TERMINAL SNAPSHOT: 02_stopped_at_debugger
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2|
 3| function testVariables() {
 4|     // Primitive types
 5|     let numberVar = 42;
 6|     let stringVar = "Hello, Debug!";
 7|     let booleanVar = true;
 8|     let nullVar = null;
 9|     let undefinedVar = undefined;
10|
11|     // Complex types
12|     let arrayVar = [1, 2, 3, "four", { five: 5 }];
13|     let objectVar = {
14|         name: "Test Object",
15|         count: 100,
16|         nested: {
17|             level: 2,
18|             data: ["a", "b", "c"]
19|         },
20|         method: function() { return "method"; }
21|     };
22|
23| complex.js                                                    1,1            Top
24|
]]

--[[ TERMINAL SNAPSHOT: 03_variables_window_scopes
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - │
 2| various variable types                 │~
 3|                                        │~
 4| function testVariables() {             │~
 5|     // Primitive types                 │~
 6|     let numberVar = 42;                │~
 7|     let stringVar = "Hello, Debug!";   │~
 8|     let booleanVar = true;             │~
 9|     let nullVar = null;                │~
10|     let undefinedVar = undefined;      │~
11|                                        │~
12|     // Complex types                   │~
13|     let arrayVar = [1, 2, 3, "four", { │~
14| five: 5 }];                            │~
15|     let objectVar = {                  │~
16|         name: "Test Object",           │~
17|         count: 100,                    │~
18|         nested: {                      │~
19|             level: 2,                  │~
20|             data: ["a", "b", "c"]      │~
21|         },                             │~
22|         method: function() { return @@@│~
23| <ariables/complex.js 1,1            Top <e variables [1] [RO] 0,0-1          All
24|
]]

--[[ TERMINAL SNAPSHOT: 04_local_scope_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - │
 2| various variable types                 │~
 3|                                        │~
 4| function testVariables() {             │~
 5|     // Primitive types                 │~
 6|     let numberVar = 42;                │~
 7|     let stringVar = "Hello, Debug!";   │~
 8|     let booleanVar = true;             │~
 9|     let nullVar = null;                │~
10|     let undefinedVar = undefined;      │~
11|                                        │~
12|     // Complex types                   │~
13|     let arrayVar = [1, 2, 3, "four", { │~
14| five: 5 }];                            │~
15|     let objectVar = {                  │~
16|         name: "Test Object",           │~
17|         count: 100,                    │~
18|         nested: {                      │~
19|             level: 2,                  │~
20|             data: ["a", "b", "c"]      │~
21|         },                             │~
22|         method: function() { return @@@│~
23| <ariables/complex.js 1,1            Top <e variables [1] [RO] 0,0-1          All
24|
]]

--[[ TERMINAL SNAPSHOT: 05_object_var_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - │
 2| various variable types                 │~
 3|                                        │~
 4| function testVariables() {             │~
 5|     // Primitive types                 │~
 6|     let numberVar = 42;                │~
 7|     let stringVar = "Hello, Debug!";   │~
 8|     let booleanVar = true;             │~
 9|     let nullVar = null;                │~
10|     let undefinedVar = undefined;      │~
11|                                        │~
12|     // Complex types                   │~
13|     let arrayVar = [1, 2, 3, "four", { │~
14| five: 5 }];                            │~
15|     let objectVar = {                  │~
16|         name: "Test Object",           │~
17|         count: 100,                    │~
18|         nested: {                      │~
19|             level: 2,                  │~
20|             data: ["a", "b", "c"]      │~
21|         },                             │~
22|         method: function() { return @@@│~
23| <ariables/complex.js 1,1            Top <e variables [1] [RO] 0,0-1          All
24|
]]

--[[ TERMINAL SNAPSHOT: 06_nested_object_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - │
 2| various variable types                 │~
 3|                                        │~
 4| function testVariables() {             │~
 5|     // Primitive types                 │~
 6|     let numberVar = 42;                │~
 7|     let stringVar = "Hello, Debug!";   │~
 8|     let booleanVar = true;             │~
 9|     let nullVar = null;                │~
10|     let undefinedVar = undefined;      │~
11|                                        │~
12|     // Complex types                   │~
13|     let arrayVar = [1, 2, 3, "four", { │~
14| five: 5 }];                            │~
15|     let objectVar = {                  │~
16|         name: "Test Object",           │~
17|         count: 100,                    │~
18|         nested: {                      │~
19|             level: 2,                  │~
20|             data: ["a", "b", "c"]      │~
21|         },                             │~
22|         method: function() { return @@@│~
23| <ariables/complex.js 1,1            Top <e variables [1] [RO] 0,0-1          All
24|
]]
