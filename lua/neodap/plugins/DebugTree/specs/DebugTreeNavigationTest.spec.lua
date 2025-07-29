-- Test navigation issues with j/k keys, especially in stack frames
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Use stack fixture for deep call stack
  T.cmd("edit lua/testing/fixtures/stack/deep.js")
  T.cmd("normal! 8j") -- Go to breakpoint line
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Stack [stack]")
  T.sleep(2000) -- Wait for session to start and hit breakpoint
  
  -- Open unified DebugTree 
  T.cmd("DebugTree")
  T.sleep(500)
  T.TerminalSnapshot('01_initial_tree')
  
  -- Navigate down to session
  T.cmd("normal! j") -- Move to Session 2
  T.cmd("execute \"normal \\<CR>\"") -- Expand session
  T.sleep(300)
  T.TerminalSnapshot('02_session_expanded')
  
  -- Navigate to thread
  T.cmd("normal! j") -- Move to thread
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread
  T.sleep(300)
  T.TerminalSnapshot('03_thread_expanded')
  
  -- Navigate to stack and expand
  T.cmd("normal! j") -- Move to stack
  T.cmd("execute \"normal \\<CR>\"") -- Expand stack
  T.sleep(800)
  T.TerminalSnapshot('04_stack_expanded_many_frames')
  
  -- Now test j navigation through multiple frames
  T.cmd("normal! j") -- Frame 1
  T.TerminalSnapshot('05_navigated_to_frame1')
  
  T.cmd("normal! j") -- Frame 2
  T.TerminalSnapshot('06_navigated_to_frame2')
  
  T.cmd("normal! j") -- Frame 3
  T.TerminalSnapshot('07_navigated_to_frame3')
  
  T.cmd("normal! j") -- Frame 4
  T.TerminalSnapshot('08_navigated_to_frame4')
  
  -- Test k navigation back up
  T.cmd("normal! k") -- Back to Frame 3
  T.TerminalSnapshot('09_navigated_back_to_frame3')
  
  T.cmd("normal! k") -- Back to Frame 2
  T.TerminalSnapshot('10_navigated_back_to_frame2')
  
  T.cmd("normal! k") -- Back to Frame 1
  T.TerminalSnapshot('11_navigated_back_to_frame1')
  
  T.cmd("normal! k") -- Back to Stack
  T.TerminalSnapshot('12_navigated_back_to_stack')
  
  -- Test rapid navigation
  T.cmd("normal! 5j") -- Jump down 5 nodes
  T.TerminalSnapshot('13_rapid_nav_down')
  
  T.cmd("normal! 5k") -- Jump up 5 nodes
  T.TerminalSnapshot('14_rapid_nav_up')
  
  -- Clean up
  T.cmd("normal! q")
  T.sleep(200)
end)

--[[ TERMINAL SNAPSHOT: 01_initial_tree
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     con│▶ 📡  Session 1                                                  │
 5|     let│▶ 📡  Session 2                                                  │
 6|     con│                                                                │
 7| }      │                                                                │
 8|        │                                                                │
 9| functio│                                                                │
10|     con│                                                                │
11|     let│                                                                │
12|     ret│                                                                │
13| }      │                                                                │
14|        │                                                                │
15| functio│                                                                │
16|     con│                                                                │
17|     let│                                                                │
18|     ret│                                                                │
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               1,1           All
]]


--[[ TERMINAL SNAPSHOT: 02_session_expanded
Size: 24x80
Cursor: [3, 3] (line 3, col 3)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     con│▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     con│╰─ ▶ ⏸  Thread 0 (stopped)                                      │
 7| }      │                                                                │
 8|        │                                                                │
 9| functio│                                                                │
10|     con│                                                                │
11|     let│                                                                │
12|     ret│                                                                │
13| }      │                                                                │
14|        │                                                                │
15| functio│                                                                │
16|     con│                                                                │
17|     let│                                                                │
18|     ret│                                                                │
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               3,4-2         All
]]

--[[ TERMINAL SNAPSHOT: 03_thread_expanded
Size: 24x80
Cursor: [4, 0] (line 4, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     con│▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     con│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7| }      ││  ╰─ ▶ 📚  Stack (12 frames)                                    │
 8|        │                                                                │
 9| functio│                                                                │
10|     con│                                                                │
11|     let│                                                                │
12|     ret│                                                                │
13| }      │                                                                │
14|        │                                                                │
15| functio│                                                                │
16|     con│                                                                │
17|     let│                                                                │
18|     ret│                                                                │
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               4,1           All
]]

--[[ TERMINAL SNAPSHOT: 04_stack_expanded_many_frames
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     con│▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     con│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7| }      ││  ╰─ ▼ 📚  Stack (12 frames)                                    │
 8|        ││  │  ╰─ ▶ 🖼   global.functionFour                              │
 9| functio││  │  ╰─ ▶ 🖼   global.functionThree                             │
10|     con││  │  ╰─ ▶ 🖼   global.functionTwo                               │
11|     let││  │  ╰─ ▶ 🖼   global.functionOne                               │
12|     ret││  │  ╰─ ▶ 🖼   global.main                                      │
13| }      ││  │  ╰─ ▶ 🖼   <anonymous>                                      │
14|        ││  │  ╰─ ▶ 🖼   Module._compile                                  │
15| functio││  │  ╰─ ▶ 🖼   Module._extensions..js                           │
16|     con││  │  ╰─ ▶ 🖼   Module.load                                      │
17|     let││  │  ╰─ ▶ 🖼   Module._load                                     │
18|     ret││  │  ╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEnt│
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               5,1           Top
]]

--[[ TERMINAL SNAPSHOT: 05_navigated_to_frame1
Size: 24x80
Cursor: [6, 0] (line 6, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     con│▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     con│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7| }      ││  ╰─ ▼ 📚  Stack (12 frames)                                    │
 8|        ││  │  ╰─ ▶ 🖼   global.functionFour                              │
 9| functio││  │  ╰─ ▶ 🖼   global.functionThree                             │
10|     con││  │  ╰─ ▶ 🖼   global.functionTwo                               │
11|     let││  │  ╰─ ▶ 🖼   global.functionOne                               │
12|     ret││  │  ╰─ ▶ 🖼   global.main                                      │
13| }      ││  │  ╰─ ▶ 🖼   <anonymous>                                      │
14|        ││  │  ╰─ ▶ 🖼   Module._compile                                  │
15| functio││  │  ╰─ ▶ 🖼   Module._extensions..js                           │
16|     con││  │  ╰─ ▶ 🖼   Module.load                                      │
17|     let││  │  ╰─ ▶ 🖼   Module._load                                     │
18|     ret││  │  ╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEnt│
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               6,1           Top
]]

--[[ TERMINAL SNAPSHOT: 06_navigated_to_frame2
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     con│▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     con│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7| }      ││  ╰─ ▼ 📚  Stack (12 frames)                                    │
 8|        ││  │  ╰─ ▶ 🖼   global.functionFour                              │
 9| functio││  │  ╰─ ▶ 🖼   global.functionThree                             │
10|     con││  │  ╰─ ▶ 🖼   global.functionTwo                               │
11|     let││  │  ╰─ ▶ 🖼   global.functionOne                               │
12|     ret││  │  ╰─ ▶ 🖼   global.main                                      │
13| }      ││  │  ╰─ ▶ 🖼   <anonymous>                                      │
14|        ││  │  ╰─ ▶ 🖼   Module._compile                                  │
15| functio││  │  ╰─ ▶ 🖼   Module._extensions..js                           │
16|     con││  │  ╰─ ▶ 🖼   Module.load                                      │
17|     let││  │  ╰─ ▶ 🖼   Module._load                                     │
18|     ret││  │  ╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEnt│
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               7,1           Top
]]

--[[ TERMINAL SNAPSHOT: 07_navigated_to_frame3
Size: 24x80
Cursor: [8, 0] (line 8, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     con│▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     con│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7| }      ││  ╰─ ▼ 📚  Stack (12 frames)                                    │
 8|        ││  │  ╰─ ▶ 🖼   global.functionFour                              │
 9| functio││  │  ╰─ ▶ 🖼   global.functionThree                             │
10|     con││  │  ╰─ ▶ 🖼   global.functionTwo                               │
11|     let││  │  ╰─ ▶ 🖼   global.functionOne                               │
12|     ret││  │  ╰─ ▶ 🖼   global.main                                      │
13| }      ││  │  ╰─ ▶ 🖼   <anonymous>                                      │
14|        ││  │  ╰─ ▶ 🖼   Module._compile                                  │
15| functio││  │  ╰─ ▶ 🖼   Module._extensions..js                           │
16|     con││  │  ╰─ ▶ 🖼   Module.load                                      │
17|     let││  │  ╰─ ▶ 🖼   Module._load                                     │
18|     ret││  │  ╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEnt│
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               8,1           Top
]]

--[[ TERMINAL SNAPSHOT: 08_navigated_to_frame4
Size: 24x80
Cursor: [9, 0] (line 9, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     con│▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     con│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7| }      ││  ╰─ ▼ 📚  Stack (12 frames)                                    │
 8|        ││  │  ╰─ ▶ 🖼   global.functionFour                              │
 9| functio││  │  ╰─ ▶ 🖼   global.functionThree                             │
10|     con││  │  ╰─ ▶ 🖼   global.functionTwo                               │
11|     let││  │  ╰─ ▶ 🖼   global.functionOne                               │
12|     ret││  │  ╰─ ▶ 🖼   global.main                                      │
13| }      ││  │  ╰─ ▶ 🖼   <anonymous>                                      │
14|        ││  │  ╰─ ▶ 🖼   Module._compile                                  │
15| functio││  │  ╰─ ▶ 🖼   Module._extensions..js                           │
16|     con││  │  ╰─ ▶ 🖼   Module.load                                      │
17|     let││  │  ╰─ ▶ 🖼   Module._load                                     │
18|     ret││  │  ╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEnt│
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               9,1           Top
]]

--[[ TERMINAL SNAPSHOT: 09_navigated_back_to_frame3
Size: 24x80
Cursor: [8, 0] (line 8, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     con│▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     con│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7| }      ││  ╰─ ▼ 📚  Stack (12 frames)                                    │
 8|        ││  │  ╰─ ▶ 🖼   global.functionFour                              │
 9| functio││  │  ╰─ ▶ 🖼   global.functionThree                             │
10|     con││  │  ╰─ ▶ 🖼   global.functionTwo                               │
11|     let││  │  ╰─ ▶ 🖼   global.functionOne                               │
12|     ret││  │  ╰─ ▶ 🖼   global.main                                      │
13| }      ││  │  ╰─ ▶ 🖼   <anonymous>                                      │
14|        ││  │  ╰─ ▶ 🖼   Module._compile                                  │
15| functio││  │  ╰─ ▶ 🖼   Module._extensions..js                           │
16|     con││  │  ╰─ ▶ 🖼   Module.load                                      │
17|     let││  │  ╰─ ▶ 🖼   Module._load                                     │
18|     ret││  │  ╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEnt│
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               8,1           Top
]]

--[[ TERMINAL SNAPSHOT: 10_navigated_back_to_frame2
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     con│▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     con│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7| }      ││  ╰─ ▼ 📚  Stack (12 frames)                                    │
 8|        ││  │  ╰─ ▶ 🖼   global.functionFour                              │
 9| functio││  │  ╰─ ▶ 🖼   global.functionThree                             │
10|     con││  │  ╰─ ▶ 🖼   global.functionTwo                               │
11|     let││  │  ╰─ ▶ 🖼   global.functionOne                               │
12|     ret││  │  ╰─ ▶ 🖼   global.main                                      │
13| }      ││  │  ╰─ ▶ 🖼   <anonymous>                                      │
14|        ││  │  ╰─ ▶ 🖼   Module._compile                                  │
15| functio││  │  ╰─ ▶ 🖼   Module._extensions..js                           │
16|     con││  │  ╰─ ▶ 🖼   Module.load                                      │
17|     let││  │  ╰─ ▶ 🖼   Module._load                                     │
18|     ret││  │  ╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEnt│
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               7,1           Top
]]

--[[ TERMINAL SNAPSHOT: 11_navigated_back_to_frame1
Size: 24x80
Cursor: [6, 0] (line 6, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     con│▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     con│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7| }      ││  ╰─ ▼ 📚  Stack (12 frames)                                    │
 8|        ││  │  ╰─ ▶ 🖼   global.functionFour                              │
 9| functio││  │  ╰─ ▶ 🖼   global.functionThree                             │
10|     con││  │  ╰─ ▶ 🖼   global.functionTwo                               │
11|     let││  │  ╰─ ▶ 🖼   global.functionOne                               │
12|     ret││  │  ╰─ ▶ 🖼   global.main                                      │
13| }      ││  │  ╰─ ▶ 🖼   <anonymous>                                      │
14|        ││  │  ╰─ ▶ 🖼   Module._compile                                  │
15| functio││  │  ╰─ ▶ 🖼   Module._extensions..js                           │
16|     con││  │  ╰─ ▶ 🖼   Module.load                                      │
17|     let││  │  ╰─ ▶ 🖼   Module._load                                     │
18|     ret││  │  ╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEnt│
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               6,1           Top
]]

--[[ TERMINAL SNAPSHOT: 12_navigated_back_to_stack
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     con│▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     con│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7| }      ││  ╰─ ▼ 📚  Stack (12 frames)                                    │
 8|        ││  │  ╰─ ▶ 🖼   global.functionFour                              │
 9| functio││  │  ╰─ ▶ 🖼   global.functionThree                             │
10|     con││  │  ╰─ ▶ 🖼   global.functionTwo                               │
11|     let││  │  ╰─ ▶ 🖼   global.functionOne                               │
12|     ret││  │  ╰─ ▶ 🖼   global.main                                      │
13| }      ││  │  ╰─ ▶ 🖼   <anonymous>                                      │
14|        ││  │  ╰─ ▶ 🖼   Module._compile                                  │
15| functio││  │  ╰─ ▶ 🖼   Module._extensions..js                           │
16|     con││  │  ╰─ ▶ 🖼   Module.load                                      │
17|     let││  │  ╰─ ▶ 🖼   Module._load                                     │
18|     ret││  │  ╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEnt│
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               5,1           Top
]]

--[[ TERMINAL SNAPSHOT: 13_rapid_nav_down
Size: 24x80
Cursor: [10, 0] (line 10, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     con│▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     con│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7| }      ││  ╰─ ▼ 📚  Stack (12 frames)                                    │
 8|        ││  │  ╰─ ▶ 🖼   global.functionFour                              │
 9| functio││  │  ╰─ ▶ 🖼   global.functionThree                             │
10|     con││  │  ╰─ ▶ 🖼   global.functionTwo                               │
11|     let││  │  ╰─ ▶ 🖼   global.functionOne                               │
12|     ret││  │  ╰─ ▶ 🖼   global.main                                      │
13| }      ││  │  ╰─ ▶ 🖼   <anonymous>                                      │
14|        ││  │  ╰─ ▶ 🖼   Module._compile                                  │
15| functio││  │  ╰─ ▶ 🖼   Module._extensions..js                           │
16|     con││  │  ╰─ ▶ 🖼   Module.load                                      │
17|     let││  │  ╰─ ▶ 🖼   Module._load                                     │
18|     ret││  │  ╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEnt│
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               10,1          Top
]]

--[[ TERMINAL SNAPSHOT: 14_rapid_nav_up
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     con│▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     con│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7| }      ││  ╰─ ▼ 📚  Stack (12 frames)                                    │
 8|        ││  │  ╰─ ▶ 🖼   global.functionFour                              │
 9| functio││  │  ╰─ ▶ 🖼   global.functionThree                             │
10|     con││  │  ╰─ ▶ 🖼   global.functionTwo                               │
11|     let││  │  ╰─ ▶ 🖼   global.functionOne                               │
12|     ret││  │  ╰─ ▶ 🖼   global.main                                      │
13| }      ││  │  ╰─ ▶ 🖼   <anonymous>                                      │
14|        ││  │  ╰─ ▶ 🖼   Module._compile                                  │
15| functio││  │  ╰─ ▶ 🖼   Module._extensions..js                           │
16|     con││  │  ╰─ ▶ 🖼   Module.load                                      │
17|     let││  │  ╰─ ▶ 🖼   Module._load                                     │
18|     ret││  │  ╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEnt│
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               5,1           Top
]]