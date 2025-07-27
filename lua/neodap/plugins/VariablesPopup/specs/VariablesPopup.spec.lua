-- VariablesPopup Plugin Visual Verification Tests
-- Tests the new buffer-centric popup presentation plugin

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load all plugins exactly like LegacyComparison test (which works)
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables4'))
  api:getPluginInstance(require('neodap.plugins.VariablesBuffer'))
  api:getPluginInstance(require('neodap.plugins.VariablesPopup'))

  -- Set up debugging session with variables
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j") -- Navigate to line with variables
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  
  -- Wait for session to start and hit breakpoint
  T.sleep(1500)
  
  -- Test 1: Open popup using new VariablesPopup command
  T.TerminalSnapshot('before_popup')
  
  T.cmd("VariablesPopup")
  T.sleep(500) -- Let popup render
  T.TerminalSnapshot('popup_opened')
  
  -- Test 2: Navigate within the variables tree
  T.cmd("normal! j") -- Move down
  T.TerminalSnapshot('navigation_down')
  
  T.cmd("execute \"normal \\<CR>\"") -- Expand node
  T.sleep(300) -- Let expansion complete
  T.TerminalSnapshot('node_expanded')
  
  -- Test 3: Navigate to expanded content
  T.cmd("normal! j") -- Move to expanded variable
  T.TerminalSnapshot('in_expanded_content')
  
  -- Test 4: Collapse node
  T.cmd("normal! k") -- Go back to parent
  T.cmd("execute \"normal \\<Left>\"") -- Collapse with left arrow
  T.sleep(200)
  T.TerminalSnapshot('node_collapsed')
  
  -- Test 5: Refresh functionality
  T.cmd("normal! r") -- Refresh tree
  T.sleep(300)
  T.TerminalSnapshot('after_refresh')
  
  -- Test 6: Close popup with 'q'
  T.cmd("normal! q")
  T.sleep(200)
  T.TerminalSnapshot('popup_closed')
end)







--[[ TERMINAL SNAPSHOT: before_popup
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





--[[ TERMINAL SNAPSHOT: popup_opened
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





--[[ TERMINAL SNAPSHOT: navigation_down
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





--[[ TERMINAL SNAPSHOT: node_expanded
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





--[[ TERMINAL SNAPSHOT: in_expanded_content
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





--[[ TERMINAL SNAPSHOT: node_collapsed
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





--[[ TERMINAL SNAPSHOT: after_refresh
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





--[[ TERMINAL SNAPSHOT: popup_closed
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