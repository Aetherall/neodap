local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.FrameHighlight'))
  api:getPluginInstance(require('neodap.plugins.StackNavigation'))

  -- Set up the initial state with a file that has multiple function calls
  T.cmd("edit lua/testing/fixtures/stack/deep.js")
  T.cmd("NeodapLaunchClosest Stack [stack]")

  -- Wait for the debugger to hit the breakpoint at line 29
  T.sleep(1000)

  -- Capture the initial state (should be stopped at debugger statement in functionFour)
  T.TerminalSnapshot('initial_state')

  -- Test navigating up the stack
  T.cmd("NeodapStackNavigationUp")
  T.TerminalSnapshot('after_up')
  T.cmd("NeodapStackNavigationDown")
  T.TerminalSnapshot('after_down')
  T.cmd("NeodapStackNavigationTop")
  T.TerminalSnapshot('after_top')
  T.cmd("NeodapStackNavigationUp")
  T.cmd("NeodapStackNavigationUp")
  T.TerminalSnapshot('after_multiple_up')
end)


--[[ TERMINAL SNAPSHOT: initial_state
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| function main() {
 4|     console.log("Starting main");
 5|     let result = functionOne(10);
 6|     console.log("Main result:", result);
 7| }
 8| 
 9| function functionOne(x) {
10|     console.log("In functionOne with x =", x);
11|     let value = x * 2;
12|     return functionTwo(value);
13| }
14| 
15| function functionTwo(y) {
16|     console.log("In functionTwo with y =", y);
17|     let value = y + 5;
18|     return functionThree(value);
19| }
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            1,1            Top
24| 
]]

--[[ TERMINAL SNAPSHOT: after_up
Size: 24x80
Cursor: [5, 17] (line 5, col 17)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| function main() {
 4|     console.log("Starting main");
 5|     let result = functionOne(10);
 6|     console.log("Main result:", result);
 7| }
 8| 
 9| function functionOne(x) {
10|     console.log("In functionOne with x =", x);
11|     let value = x * 2;
12|     return functionTwo(value);
13| }
14| 
15| function functionTwo(y) {
16|     console.log("In functionTwo with y =", y);
17|     let value = y + 5;
18|     return functionThree(value);
19| }
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            5,18           Top
24| 
]]

--[[ TERMINAL SNAPSHOT: after_down
Size: 24x80
Cursor: [34, 0] (line 34, col 0)
Mode: n

13| }
14| 
15| function functionTwo(y) {
16|     console.log("In functionTwo with y =", y);
17|     let value = y + 5;
18|     return functionThree(value);
19| }
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23|     let value = z / 2;
24|     return functionFour(value);
25| }
26| 
27| function functionFour(w) {
28|     console.log("In functionFour with w =", w);
29|     debugger; // Breakpoint here to create a stack
30|     return w * w;
31| }
32| 
33| // Start the program
34| main();
35| lua/testing/fixtures/stack/deep.js                            34,1           Bot
36| 
]]

--[[ TERMINAL SNAPSHOT: after_top
Size: 24x80
Cursor: [29, 4] (line 29, col 4)
Mode: n

13| }
14| 
15| function functionTwo(y) {
16|     console.log("In functionTwo with y =", y);
17|     let value = y + 5;
18|     return functionThree(value);
19| }
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23|     let value = z / 2;
24|     return functionFour(value);
25| }
26| 
27| function functionFour(w) {
28|     console.log("In functionFour with w =", w);
29|     debugger; // Breakpoint here to create a stack
30|     return w * w;
31| }
32| 
33| // Start the program
34| main();
35| lua/testing/fixtures/stack/deep.js                            29,5           Bot
36| 
]]

--[[ TERMINAL SNAPSHOT: after_multiple_up
Size: 24x80
Cursor: [29, 4] (line 29, col 4)
Mode: n

13| }
14| 
15| function functionTwo(y) {
16|     console.log("In functionTwo with y =", y);
17|     let value = y + 5;
18|     return functionThree(value);
19| }
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23|     let value = z / 2;
24|     return functionFour(value);
25| }
26| 
27| function functionFour(w) {
28|     console.log("In functionFour with w =", w);
29|     debugger; // Breakpoint here to create a stack
30|     return w * w;
31| }
32| 
33| // Start the program
34| main();
35| lua/testing/fixtures/stack/deep.js                            29,5           Bot
36| 
]]