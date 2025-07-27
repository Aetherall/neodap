-- Variables4 Buffer-Composable Architecture Verification Test
-- Tests that all advanced Variables4 features work with the new renderToBuffer approach

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load all required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables4'))
  api:getPluginInstance(require('neodap.plugins.VariablesPopup'))

  -- Set up debugging session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j")
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500)
  
  -- Test 1: Legacy Variables4Tree command (should use buffer-composable now)
  T.TerminalSnapshot('before_enhanced_variables4')
  
  T.cmd("Variables4Tree")
  T.sleep(500)
  T.TerminalSnapshot('enhanced_variables4_popup')
  
  -- Test 2: Verify advanced navigation still works
  T.cmd("normal! j") -- Move down
  T.TerminalSnapshot('enhanced_navigation_down')
  
  T.cmd("execute \"normal \\<CR>\"") -- Expand with sophisticated logic
  T.sleep(300)
  T.TerminalSnapshot('enhanced_expansion')
  
  -- Test 3: Test focus mode (Variables4 advanced feature)
  T.cmd("normal! f") -- Focus on current scope
  T.sleep(300)
  T.TerminalSnapshot('enhanced_focus_mode')
  
  -- Test 4: Test sophisticated tree rendering with UTF-8 characters
  T.cmd("normal! l") -- Expand to see tree rendering
  T.sleep(300)
  T.TerminalSnapshot('enhanced_tree_rendering')
  
  -- Test 5: Close and test new VariablesPopup command
  T.cmd("normal! q")
  T.sleep(200)
  
  T.cmd("VariablesPopup") -- Should use enhanced Variables4 too
  T.sleep(500)
  T.TerminalSnapshot('enhanced_variables_popup_command')
  
  -- Test 6: Verify help shows advanced features
  T.cmd("normal! ?") -- Show help
  T.sleep(200)
  T.TerminalSnapshot('enhanced_help_display')
  
  -- Clean up
  T.cmd("normal! q")
  T.sleep(200)
  T.TerminalSnapshot('enhanced_cleanup')
end)

--[[ TERMINAL SNAPSHOT: before_enhanced_variables4
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

--[[ TERMINAL SNAPSHOT: enhanced_variables4_popup
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  Local: testVariables                                       │
 5|     let│╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                     │
 6|     let│╰─   ◐ booleanVar: true                                         │
 7|     let│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
 8|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
 9|     let│╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
10|     let│╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │lue";
11|     let│╰─   󰅩 nullVar: null                                            │e trunc
12| ated wh│╰─   󰎠 numberVar: 42                                            │
13|        │╰─ ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...      │
14|     // │╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                     │
15|     let│╰─   󰉿 stringVar: "'Hello, Debug!'"                             │
16|     let│╰─ ▶ 󰀬 this: global                                             │
17|        │╰─   󰟢 undefinedVar: undefined                                  │
18|        │╰─   󰉿 veryLongVariableNameThatExceedsNormalLimitsForDisplay: "'│
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24| W10: Warning: Changing a readonly file                        1,1           Top
]]

--[[ TERMINAL SNAPSHOT: enhanced_navigation_down
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  Local: testVariables                                       │
 5|     let│╰─ ▶ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                     │
 6|     let│╰─   ◐ booleanVar: true                                         │
 7|     let│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
 8|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
 9|     let│╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
10|     let│╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │lue";
11|     let│╰─   󰅩 nullVar: null                                            │e trunc
12| ated wh│╰─   󰎠 numberVar: 42                                            │
13|        │╰─ ▶ 󰅩 objectVar: {name: 'Test Object', count: 100, nes...      │
14|     // │╰─ ▶ 󰘦 setVar: Set(4) {size: 4, 1, 2, 3, 4}                     │
15|     let│╰─   󰉿 stringVar: "'Hello, Debug!'"                             │
16|     let│╰─ ▶ 󰀬 this: global                                             │
17|        │╰─   󰟢 undefinedVar: undefined                                  │
18|        │╰─   󰉿 veryLongVariableNameThatExceedsNormalLimitsForDisplay: "'│
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24| W10: Warning: Changing a readonly file                        2,1           Top
]]

--[[ TERMINAL SNAPSHOT: enhanced_expansion
Size: 24x80
Cursor: [3, 19] (line 3, col 19)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  Local: testVariables                                       │
 5|     let│╰─ ▼ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                     │
 6|     let││  ╰─   󰎠 0: 1                                                  │
 7|     let││  ╰─   󰎠 1: 2                                                  │
 8|     let││  ╰─   󰎠 2: 3                                                  │
 9|     let││  ╰─   󰉿 3: "'four'"                                           │
10|     let││  ╰─ ▶ 󰅩 4: {five: 5}                                          │lue";
11|     let││  ╰─   󰎠 length: 5                                             │e trunc
12| ated wh││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
13|        ││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
14|     // │╰─   ◐ booleanVar: true                                         │
15|     let│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
16|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
17|        │╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
18|        │╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24| W10: Warning: Changing a readonly file                        3,20-11       Top
]]

--[[ TERMINAL SNAPSHOT: enhanced_focus_mode
Size: 24x80
Cursor: [3, 19] (line 3, col 19)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  Local: testVariables                                       │
 5|     let│╰─ ▼ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                     │
 6|     let││  ╰─   󰎠 0: 1                                                  │
 7|     let││  ╰─   󰎠 1: 2                                                  │
 8|     let││  ╰─   󰎠 2: 3                                                  │
 9|     let││  ╰─   󰉿 3: "'four'"                                           │
10|     let││  ╰─ ▶ 󰅩 4: {five: 5}                                          │lue";
11|     let││  ╰─   󰎠 length: 5                                             │e trunc
12| ated wh││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
13|        ││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
14|     // │╰─   ◐ booleanVar: true                                         │
15|     let│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
16|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
17|        │╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
18|        │╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24| W10: Warning: Changing a readonly file                        3,20-11       Top
]]

--[[ TERMINAL SNAPSHOT: enhanced_tree_rendering
Size: 24x80
Cursor: [3, 20] (line 3, col 20)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▼ 📁  Local: testVariables                                       │
 5|     let│╰─ ▼ 󰅪 arrayVar: (5) [1, 2, 3, 'four', {…}]                     │
 6|     let││  ╰─   󰎠 0: 1                                                  │
 7|     let││  ╰─   󰎠 1: 2                                                  │
 8|     let││  ╰─   󰎠 2: 3                                                  │
 9|     let││  ╰─   󰉿 3: "'four'"                                           │
10|     let││  ╰─ ▶ 󰅩 4: {five: 5}                                          │lue";
11|     let││  ╰─   󰎠 length: 5                                             │e trunc
12| ated wh││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
13|        ││  ╰─ ▶ 󰅩 [{Prototype}]: Object                                 │
14|     // │╰─   ◐ booleanVar: true                                         │
15|     let│╰─   󰅩 dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (Ce...        │
16|     let│╰─ ▶ 󰊕 functionVar: ƒ (x) { return x * 2; }                     │
17|        │╰─   󰉿 longStringValue: "'This is a very long string valu..."   │
18|        │╰─ ▶ 󰘣 mapVar: Map(2) {size: 2, key1 => value1, key2...         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24| W10: Warning: Changing a readonly file                        3,21-12       Top
]]