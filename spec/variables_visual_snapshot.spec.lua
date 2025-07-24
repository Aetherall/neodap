-- Visual verification test for Variables4 plugin
-- This test generates snapshots to visually verify the Variables4 NUI tree displays correctly
-- and allows interactive navigation through variable scopes

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  local variables4_plugin = api:getPluginInstance(require('neodap.plugins.Variables4'))

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

  -- Open the Variables4 NUI tree popup
  T.cmd("Variables4TreeDemo")
  T.sleep(500)

  -- Take snapshot showing the Variables4 popup with collapsed scopes
  T.TerminalSnapshot('03_variables4_popup_scopes')

  -- Expand the first scope (Local) using Enter key
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(1000)

  -- Take snapshot showing expanded Local scope with all variables
  T.TerminalSnapshot('04_local_scope_expanded')

  -- Navigate down and expand Global scope
  T.cmd("normal! j")
  T.sleep(100)
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(1000)

  -- Take snapshot showing both scopes expanded
  T.TerminalSnapshot('05_both_scopes_expanded')

  -- Navigate back to Local scope variables
  T.cmd("normal! k")
  T.cmd("normal! j")  -- Move to first variable
  T.sleep(100)

  -- Take snapshot showing navigation within variables
  T.TerminalSnapshot('06_variable_navigation')

  -- Close the popup with q
  T.cmd("normal! q")
  T.sleep(300)

  -- Take final snapshot showing return to normal editing
  T.TerminalSnapshot('07_popup_closed')
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
10|     let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
11|     let longStringValue = "This is a very long string value that should be trunc
12| ated when displayed in the tree view to prevent line wrapping";
13| 
14|     // Complex types
15|     let arrayVar = [1, 2, 3, "four", { five: 5 }];
16|     let objectVar = {
17|         name: "Test Object",
18|         count: 100,
19|         nested: {
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
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
