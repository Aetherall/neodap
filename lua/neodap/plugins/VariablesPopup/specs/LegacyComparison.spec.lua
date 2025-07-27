-- Legacy Variables4 vs New VariablesPopup Comparison Tests
-- Ensures backward compatibility and equivalent functionality

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load all plugins for comparison
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables4'))
  api:getPluginInstance(require('neodap.plugins.VariablesBuffer'))
  api:getPluginInstance(require('neodap.plugins.VariablesPopup'))

  -- Set up debugging session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j")
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500)
  
  -- Test legacy Variables4Tree command (should delegate to new system)
  T.TerminalSnapshot('before_legacy_command')
  
  T.cmd("Variables4Tree")
  T.sleep(500)
  T.TerminalSnapshot('legacy_variables4_popup')
  
  -- Test navigation in legacy popup
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(300)
  T.TerminalSnapshot('legacy_navigation')
  
  -- Close legacy popup
  T.cmd("normal! q")
  T.sleep(200)
  
  -- Now test new VariablesPopup command for comparison
  T.cmd("VariablesPopup")
  T.sleep(500)
  T.TerminalSnapshot('new_variables_popup')
  
  -- Test same navigation in new popup
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(300)
  T.TerminalSnapshot('new_navigation')
  
  -- Close new popup
  T.cmd("normal! q")
  T.sleep(200)
  T.TerminalSnapshot('both_popups_closed')
end)

--[[ TERMINAL SNAPSHOT: before_legacy_command
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

--[[ TERMINAL SNAPSHOT: legacy_variables4_popup
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────── Variables Debug Tree (Legacy) ─────────────────╮
 4|     // │📁  Local: testVariables                                         │
 5|     let│📁  Global                                                       │
 6|     let│                                                                │
 7|     let│                                                                │
 8|     let│                                                                │
 9|     let│                                                                │
10|     let│                                                                │lue";
11|     let│                                                                │e trunc
12| ated wh│                                                                │
13|        │                                                                │
14|     // │                                                                │
15|     let│                                                                │
16|     let│                                                                │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: legacy_navigation
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────── Variables Debug Tree (Legacy) ─────────────────╮
 4|     // │📁  Local: testVariables                                         │
 5|     let│📁  Global                                                       │
 6|     let│                                                                │
 7|     let│                                                                │
 8|     let│                                                                │
 9|     let│                                                                │
10|     let│                                                                │lue";
11|     let│                                                                │e trunc
12| ated wh│                                                                │
13|        │                                                                │
14|     // │                                                                │
15|     let│                                                                │
16|     let│                                                                │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: new_variables_popup
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────────── Variables Debug Tree ─────────────────────╮
 4|     // │📁  Local: testVariables                                         │
 5|     let│📁  Global                                                       │
 6|     let│                                                                │
 7|     let│                                                                │
 8|     let│                                                                │
 9|     let│                                                                │
10|     let│                                                                │lue";
11|     let│                                                                │e trunc
12| ated wh│                                                                │
13|        │                                                                │
14|     // │                                                                │
15|     let│                                                                │
16|     let│                                                                │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: new_navigation
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────────── Variables Debug Tree ─────────────────────╮
 4|     // │📁  Local: testVariables                                         │
 5|     let│📁  Global                                                       │
 6|     let│                                                                │
 7|     let│                                                                │
 8|     let│                                                                │
 9|     let│                                                                │
10|     let│                                                                │lue";
11|     let│                                                                │e trunc
12| ated wh│                                                                │
13|        │                                                                │
14|     // │                                                                │
15|     let│                                                                │
16|     let│                                                                │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: both_popups_closed
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭───────────────────── Variables Debug Tree ─────────────────────╮
 4|     // │📁  Local: testVariables                                         │
 5|     let│📁  Global                                                       │
 6|     let│                                                                │
 7|     let│                                                                │
 8|     let│                                                                │
 9|     let│                                                                │
10|     let│                                                                │lue";
11|     let│                                                                │e trunc
12| ated wh│                                                                │
13|        │                                                                │
14|     // │                                                                │
15|     let│                                                                │
16|     let│                                                                │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               2,1           All
]]