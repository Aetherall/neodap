-- Visual Verification Test for Variables2 Plugin
-- Tests the unified node architecture where API objects ARE NuiTree.Nodes

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load the new Variables2 plugin
  local variables2_plugin = api:getPluginInstance(require('neodap.plugins.Variables2'))
  
  -- Also load supporting plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  
  -- Set up initial state
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j")  -- Move to line with variables
  T.cmd("NeodapToggleBreakpoint")
  
  -- Launch session
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500)  -- Wait for session and breakpoint hit
  
  T.TerminalSnapshot('variables2_session_started')
  
  -- Show Variables2 window
  T.cmd("Variables2Show")
  T.sleep(300)  -- Let UI render
  T.TerminalSnapshot('variables2_window_opened')
  
  -- Navigate to Variables2 window
  T.cmd("wincmd h")  -- Move to left window
  T.TerminalSnapshot('variables2_window_focused')
  
  -- Test unified node architecture demonstration
  T.cmd("Variables2Status")
  T.sleep(200)
  T.TerminalSnapshot('variables2_status_output')
  
  -- Expand first scope (Local scope)
  T.cmd("normal! j")  -- Move to first scope
  T.cmd("execute \"normal \\<CR>\"")  -- Expand scope
  T.sleep(500)  -- Wait for async expansion
  T.TerminalSnapshot('variables2_scope_expanded')
  
  -- Move to first variable and try to expand it
  T.cmd("normal! j")  -- Move to first variable
  T.cmd("execute \"normal \\<CR>\"")  -- Try to expand variable
  T.sleep(300)
  T.TerminalSnapshot('variables2_variable_interaction')
  
  -- Test refresh functionality
  T.cmd("normal! r")  -- Press 'r' to refresh
  T.sleep(300)
  T.TerminalSnapshot('variables2_after_refresh')
  
  -- Test demonstration command
  T.cmd("Variables2Demonstrate")
  T.sleep(200)
  T.TerminalSnapshot('variables2_demo_output')
  
  -- Show cache statistics
  T.cmd("Variables2Cache")
  T.sleep(200)
  T.TerminalSnapshot('variables2_cache_stats')
  
  -- Test window toggle
  T.cmd("Variables2Toggle")  -- Should hide
  T.sleep(200)
  T.TerminalSnapshot('variables2_window_hidden')
  
  T.cmd("Variables2Toggle")  -- Should show again
  T.sleep(200)
  T.TerminalSnapshot('variables2_window_restored')
end)








--[[ TERMINAL SNAPSHOT: variables2_session_started
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
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
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24| 
]]





--[[ TERMINAL SNAPSHOT: variables2_window_opened
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|                         │// Test fixture for Variables plugin - various variable
 2| ~                       │ types
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
23| [Scratch]   0,0-1    All </fixtures/variables/complex.js [RO] 7,1            Top
24| 
]]





--[[ TERMINAL SNAPSHOT: variables2_window_focused
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|                         │// Test fixture for Variables plugin - various variable
 2| ~                       │ types
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
23| [Scratch]   0,0-1    All </fixtures/variables/complex.js [RO] 7,1            Top
24| 
]]





--[[ TERMINAL SNAPSHOT: variables2_status_output
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|                         │// Test fixture for Variables plugin - various variable
 2| ~                       │ types
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
23| [Scratch]   0,0-1    All </fixtures/variables/complex.js [RO] 7,1            Top
24| 
]]




--[[ TERMINAL SNAPSHOT: variables2_scope_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|                         │// Test fixture for Variables plugin - various variable
 2| ~                       │ types
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
23| [Scratch]   0,0-1    All </fixtures/variables/complex.js [RO] 7,1            Top
24| 
]]



--[[ TERMINAL SNAPSHOT: variables2_variable_interaction
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|                         │// Test fixture for Variables plugin - various variable
 2| ~                       │ types
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
23| [Scratch]   0,0-1    All </fixtures/variables/complex.js [RO] 7,1            Top
24| 
]]



--[[ TERMINAL SNAPSHOT: variables2_after_refresh
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|                         │// Test fixture for Variables plugin - various variable
 2| ~                       │ types
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
23| [Scratch]   0,0-1    All </fixtures/variables/complex.js [RO] 7,1            Top
24| 
]]