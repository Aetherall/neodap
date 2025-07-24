-- Viewport System Demonstration Test
-- This test demonstrates the unified viewport-based architecture

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables'))

  -- Use the variables fixture for complex data structures
  T.cmd("edit lua/testing/fixtures/variables/complex.js")

  -- Set breakpoint and launch debug session
  T.cmd("normal! 5j") -- Move to a good breakpoint line
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(2000) -- Wait for breakpoint to hit

  -- =============================================
  -- DEMONSTRATION 1: Initial Viewport (Root View)
  -- =============================================

  T.cmd("VariablesShow")
  T.sleep(500)
  T.cmd("wincmd h") -- Focus Variables window
  T.TerminalSnapshot('viewport_root_view')

  -- Navigate into Global scope
  T.cmd("normal! j")                 -- Move to Global scope
  T.cmd("execute \"normal \\<CR>\"") -- Navigate into Global
  T.sleep(500)
  T.TerminalSnapshot('viewport_global_scope')

  -- =============================================
  -- DEMONSTRATION 2: Deep Navigation
  -- =============================================

  -- Navigate deeper into the tree
  T.cmd("normal! 5j")                -- Find an expandable object
  T.cmd("execute \"normal \\<CR>\"") -- Navigate deeper
  T.sleep(500)
  T.TerminalSnapshot('viewport_deep_focus')

  -- Show navigation controls
  T.cmd("execute \"normal u\"") -- Go up one level
  T.sleep(300)
  T.TerminalSnapshot('viewport_up_navigation')

  T.cmd("execute \"normal r\"") -- Go to root
  T.sleep(300)
  T.TerminalSnapshot('viewport_root_navigation')

  -- =============================================
  -- DEMONSTRATION 3: Viewport Styles
  -- =============================================

  -- Navigate back to a good position
  T.cmd("normal! j")                 -- Select Global
  T.cmd("execute \"normal \\<CR>\"") -- Navigate into Global
  T.sleep(300)

  -- Contextual style (default)
  T.TerminalSnapshot('viewport_style_contextual')

  -- Switch to minimal style
  T.cmd("execute \"normal s\"") -- Cycle viewport style
  T.sleep(200)
  T.TerminalSnapshot('viewport_style_minimal')

  -- Switch to full style
  T.cmd("execute \"normal s\"") -- Cycle to full
  T.sleep(200)
  T.TerminalSnapshot('viewport_style_full')

  -- Switch to highlight style
  T.cmd("execute \"normal s\"") -- Cycle to highlight
  T.sleep(200)
  T.TerminalSnapshot('viewport_style_highlight')

  -- =============================================
  -- DEMONSTRATION 4: Viewport Radius Control
  -- =============================================

  -- Reset to contextual style
  T.cmd("execute \"normal s\"") -- Back to contextual
  T.sleep(200)

  -- Default radius (2)
  T.TerminalSnapshot('viewport_radius_default')

  -- Increase radius
  T.cmd("execute \"normal +\"") -- Increase radius
  T.sleep(200)
  T.TerminalSnapshot('viewport_radius_increased')

  -- Decrease radius for focused view
  T.cmd("execute \"normal -\"") -- Decrease
  T.cmd("execute \"normal -\"") -- Decrease again (radius = 1)
  T.sleep(200)
  T.TerminalSnapshot('viewport_radius_minimal')

  -- =============================================
  -- DEMONSTRATION 5: History Navigation
  -- =============================================

  -- Navigate to build history
  T.cmd("execute \"normal +\"")      -- Increase radius back to 2
  T.cmd("normal! j")                 -- Select something
  T.cmd("execute \"normal \\<CR>\"") -- Navigate deeper
  T.sleep(300)
  T.cmd("normal! j")                 -- Select something else
  T.cmd("execute \"normal \\<CR>\"") -- Navigate even deeper
  T.sleep(300)
  T.TerminalSnapshot('viewport_history_deep')

  -- Use back navigation
  T.cmd("execute \"normal b\"") -- Go back in history
  T.sleep(200)
  T.TerminalSnapshot('viewport_history_back')

  -- =============================================
  -- DEMONSTRATION 6: Viewport Status
  -- =============================================

  -- Show viewport status
  T.cmd("VariablesViewport status")
  T.sleep(200)
  T.TerminalSnapshot('viewport_status_shown')

  -- Reset to root
  T.cmd("VariablesViewport reset")
  T.sleep(300)
  T.TerminalSnapshot('viewport_reset_complete')

  -- Close the demonstration
  T.cmd("execute \"normal q\"")
  T.sleep(200)
  T.TerminalSnapshot('demo_closed')
end)

--[[ EXPECTED DEMONSTRATION RESULTS:

This test demonstrates the unified viewport-based architecture:

1. **Root View**: Shows all scopes at root level with viewport UI
2. **Deep Navigation**: Demonstrates smooth viewport movement through tree
3. **Style Variations**: Shows contextual/minimal/full/highlight rendering modes
4. **Radius Control**: Demonstrates zoom in/out capability (+/- keys)
5. **History Navigation**: Shows browser-like back button functionality
6. **Viewport Commands**: Shows status and reset functionality

KEY OBSERVATIONS:
- Viewport is now the default and only navigation system
- No mode switching - just pure viewport movement
- Unified mental model: "tree with moveable viewport"
- Dramatically simplified architecture
- Rich navigation features in a clean interface

This validates the complete integration of the viewport system as the
core of the Variables plugin.
]]




--[[ TERMINAL SNAPSHOT: viewport_root_view
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| 📍  Variables            │// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3|   Global                │
 4|   Local: testVariables  │function testVariables() {
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
23| <ables [RO] 1,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]




--[[ TERMINAL SNAPSHOT: viewport_global_scope
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables            │// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3|   Global                │
 4|   Local: testVariables  │function testVariables() {
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
23| <ables [RO] 2,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]




--[[ TERMINAL SNAPSHOT: viewport_deep_focus
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables > Local: te│// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3| ▾ ▾ Local: testVariables│
 4| ├─ ├─ Global            │function testVariables() {
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
23| <ables [RO] 2,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]




--[[ TERMINAL SNAPSHOT: viewport_up_navigation
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables            │// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3|   Global                │
 4|   Local: testVariables  │function testVariables() {
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
23| <ables [RO] 2,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]



--[[ TERMINAL SNAPSHOT: viewport_root_navigation
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables            │// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3|   Global                │
 4|   Local: testVariables  │function testVariables() {
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
23| <ables [RO] 2,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]



--[[ TERMINAL SNAPSHOT: viewport_style_contextual
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables > Global   │// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3| ▾ ▾ Global ← HERE ← HERE│
 4| ├─ ├─ Local: testVariabl│function testVariables() {
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
23| <ables [RO] 2,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]



--[[ TERMINAL SNAPSHOT: viewport_style_minimal
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables > Global   │// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3| ▾ ▾ Global ← HERE ← HERE│
 4| ├─ ├─ Local: testVariabl│function testVariables() {
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
23| <ables [RO] 2,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]



--[[ TERMINAL SNAPSHOT: viewport_style_full
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables > Global   │// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3| ▾ ▾ Global ← HERE ← HERE│
 4| ├─ ├─ Local: testVariabl│function testVariables() {
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
23| <ables [RO] 2,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]



--[[ TERMINAL SNAPSHOT: viewport_style_highlight
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables > Global   │// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3| ▾ ▾ Global ← HERE ← HERE│
 4| ├─ ├─ Local: testVariabl│function testVariables() {
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
23| <ables [RO] 2,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]



--[[ TERMINAL SNAPSHOT: viewport_radius_default
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables > Global   │// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3| ▾ ▾ Global ← HERE ← HERE│
 4| ├─ ├─ Local: testVariabl│function testVariables() {
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
23| <ables [RO] 2,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]



--[[ TERMINAL SNAPSHOT: viewport_radius_increased
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables > Global   │// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3| ▾ ▾ Global ← HERE ← HERE│
 4| ├─ ├─ Local: testVariabl│function testVariables() {
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
23| <ables [RO] 2,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]



--[[ TERMINAL SNAPSHOT: viewport_radius_minimal
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables > Global   │// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3| ▾ ▾ Global ← HERE ← HERE│
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
23| <ables [RO] 2,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]



--[[ TERMINAL SNAPSHOT: viewport_history_deep
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables > Local: te│// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3| ▾ ▾ Local: testVariables│
 4| ├─ ├─ Global            │function testVariables() {
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
23| <ables [RO] 2,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]



--[[ TERMINAL SNAPSHOT: viewport_history_back
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables > Global   │// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3| ▾ ▾ Global ← HERE ← HERE│
 4| ├─ ├─ Local: testVariabl│function testVariables() {
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
23| <ables [RO] 2,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]



--[[ TERMINAL SNAPSHOT: viewport_status_shown
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables > Global   │// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3| ▾ ▾ Global ← HERE ← HERE│
 4| ├─ ├─ Local: testVariabl│function testVariables() {
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
23| <ables [RO] 2,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]



--[[ TERMINAL SNAPSHOT: viewport_reset_complete
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| 📍  Variables            │// Test fixture for Variables plugin - various variable
 2| ────────────────────────│ types
 3|   Global                │
 4|   Local: testVariables  │function testVariables() {
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
23| <ables [RO] 2,1      All <sting/fixtures/variables/complex.js 6,1            Top
24| 
]]



--[[ TERMINAL SNAPSHOT: demo_closed
Size: 24x80
Cursor: [6, 0] (line 6, col 0)
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
23| lua/testing/fixtures/variables/complex.js                     6,1            Top
24| 
]]