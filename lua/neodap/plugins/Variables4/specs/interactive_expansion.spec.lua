-- Interactive Expansion Test for Variables4 Plugin
-- Tests actual scope expansion and interaction within the NUI popup

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load the Variables4 plugin (using the alternative.lua version)
  local variables4_plugin = api:getPluginInstance(require('neodap.plugins.Variables4.alternative'))
  
  -- Load supporting plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  
  -- Set up debugging session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j")  -- Move to line with variables
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500)  -- Wait for session and breakpoint hit
  
  T.TerminalSnapshot('interactive_session_ready')
  
  -- Open the interactive tree popup
  T.cmd("Variables4Tree")
  T.sleep(500)
  T.TerminalSnapshot('interactive_popup_opened')
  
  -- Simulate key presses to expand the Local scope
  -- The popup should be focused, so we can send keys directly
  T.cmd("execute \"normal \\<CR>\"")  -- Press Enter to expand first scope
  T.sleep(300)  -- Wait for expansion
  T.TerminalSnapshot('interactive_local_expanded')
  
  -- Navigate down and try to expand a variable if it's expandable
  T.cmd("execute \"normal j\"")  -- Move down
  T.sleep(100)
  T.cmd("execute \"normal j\"")  -- Move down again
  T.sleep(100)
  T.cmd("execute \"normal \\<CR>\"")  -- Try to expand current item
  T.sleep(300)
  T.TerminalSnapshot('interactive_variable_interaction')
  
  -- Navigate to second scope and expand it
  T.cmd("execute \"normal k\"")  -- Move up
  T.sleep(100)
  T.cmd("execute \"normal k\"")  -- Move up to get to Global scope
  T.sleep(100)
  T.cmd("execute \"normal j\"")  -- Move down to Global scope
  T.sleep(100)
  T.cmd("execute \"normal \\<CR>\"")  -- Expand Global scope
  T.sleep(500)  -- Wait longer for Global scope (many variables)
  T.TerminalSnapshot('interactive_global_expanded')
  
  -- Close the popup
  T.cmd("execute \"normal q\"")  -- Press q to quit
  T.sleep(200)
  T.TerminalSnapshot('interactive_popup_closed')
end)



























--[[ TERMINAL SNAPSHOT: interactive_session_ready
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





--[[ TERMINAL SNAPSHOT: interactive_popup_opened
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





















--[[ TERMINAL SNAPSHOT: interactive_local_expanded
Size: 24x80
Cursor: [8, 4] (line 8, col 4)
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
23| lua/testing/fixtures/variables/complex.js                     8,5            Top
24| 
]]





















--[[ TERMINAL SNAPSHOT: interactive_variable_interaction
Size: 24x80
Cursor: [11, 4] (line 11, col 4)
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
23| lua/testing/fixtures/variables/complex.js                     11,5           Top
24| 
]]



















--[[ TERMINAL SNAPSHOT: interactive_global_expanded
Size: 24x80
Cursor: [11, 4] (line 11, col 4)
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
23| lua/testing/fixtures/variables/complex.js                     11,5           Top
24| 
]]





















--[[ TERMINAL SNAPSHOT: interactive_popup_closed
Size: 24x80
Cursor: [11, 4] (line 11, col 4)
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
23| lua/testing/fixtures/variables/complex.js                     11,5           Top
24| 
]]