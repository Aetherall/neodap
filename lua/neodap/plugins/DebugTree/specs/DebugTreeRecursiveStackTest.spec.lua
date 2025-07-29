-- Test DebugTree with recursive functions in stack
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Use deep stack fixture which has duplicate module frames
  T.cmd("edit lua/testing/fixtures/stack/deep.js")
  T.cmd("normal! 8j") -- Go to breakpoint line
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Stack [stack]")
  T.sleep(2000) -- Wait for session to start and hit breakpoint
  
  -- Open stack-specific tree
  T.cmd("DebugTreeStack")
  T.sleep(500)
  T.TerminalSnapshot('01_recursive_stack_initial')
  
  -- Expand stack to see recursive frames
  T.cmd("execute \"normal \\<CR>\"") -- Expand stack
  T.sleep(800)
  T.TerminalSnapshot('02_recursive_frames_with_indices')
  
  -- Navigate through duplicate frames
  T.cmd("normal! j") -- Frame 1
  T.cmd("normal! j") -- Frame 2
  T.cmd("normal! j") -- Frame 3
  T.TerminalSnapshot('03_navigated_to_frame3')
  
  -- Expand a frame to show it works
  T.cmd("execute \"normal \\<CR>\"") -- Expand frame
  T.sleep(800)
  T.TerminalSnapshot('04_frame3_expanded')
  
  -- Navigate to another duplicate frame
  T.cmd("normal! k") -- Back to frame 3
  T.cmd("normal! k") -- Back to frame 2
  T.cmd("normal! k") -- Back to frame 1
  T.cmd("execute \"normal \\<CR>\"") -- Expand frame 1
  T.sleep(800)
  T.TerminalSnapshot('05_frame1_expanded')
  
  -- Clean up
  T.cmd("normal! q")
  T.sleep(200)
end)


--[[ TERMINAL SNAPSHOT: 01_recursive_stack_initial
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - Stack Frames ───────────────────╮
 4|     con│▶ 📚  Stack (12 frames)                                          │
 5|     let│                                                                │
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


--[[ TERMINAL SNAPSHOT: 02_recursive_frames_with_indices
Size: 24x80
Cursor: [2, 3] (line 2, col 3)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - Stack Frames ───────────────────╮
 4|     con│▼ 📚  Stack (12 frames)                                          │
 5|     let│╰─ ▶ #1 🖼   global.functionFour                                 │
 6|     con│╰─ ▶ #2 🖼   global.functionThree                                │
 7| }      │╰─ ▶ #3 🖼   global.functionTwo                                  │
 8|        │╰─ ▶ #4 🖼   global.functionOne                                  │
 9| functio│╰─ ▶ #5 🖼   global.main                                         │
10|     con│╰─ ▶ #6 🖼   <anonymous>                                         │
11|     let│╰─ ▶ #7 🖼   Module._compile                                     │
12|     ret│╰─ ▶ #8 🖼   Module._extensions..js                              │
13| }      │╰─ ▶ #9 🖼   Module.load                                         │
14|        │╰─ ▶ #10 🖼   Module._load                                       │
15| functio│╰─ ▶ #11 🖼   function Module(id = '', parent) {.executeUserEntry│
16|     con│╰─ ▶ #12 🖼   <anonymous>                                        │
17|     let│                                                                │
18|     ret│                                                                │
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               2,4-2         All
]]


--[[ TERMINAL SNAPSHOT: 03_navigated_to_frame3
Size: 24x80
Cursor: [5, 3] (line 5, col 3)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - Stack Frames ───────────────────╮
 4|     con│▼ 📚  Stack (12 frames)                                          │
 5|     let│╰─ ▶ #1 🖼   global.functionFour                                 │
 6|     con│╰─ ▶ #2 🖼   global.functionThree                                │
 7| }      │╰─ ▶ #3 🖼   global.functionTwo                                  │
 8|        │╰─ ▶ #4 🖼   global.functionOne                                  │
 9| functio│╰─ ▶ #5 🖼   global.main                                         │
10|     con│╰─ ▶ #6 🖼   <anonymous>                                         │
11|     let│╰─ ▶ #7 🖼   Module._compile                                     │
12|     ret│╰─ ▶ #8 🖼   Module._extensions..js                              │
13| }      │╰─ ▶ #9 🖼   Module.load                                         │
14|        │╰─ ▶ #10 🖼   Module._load                                       │
15| functio│╰─ ▶ #11 🖼   function Module(id = '', parent) {.executeUserEntry│
16|     con│╰─ ▶ #12 🖼   <anonymous>                                        │
17|     let│                                                                │
18|     ret│                                                                │
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               5,4-2         All
]]


--[[ TERMINAL SNAPSHOT: 04_frame3_expanded
Size: 24x80
Cursor: [5, 3] (line 5, col 3)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - Stack Frames ───────────────────╮
 4|     con│▼ 📚  Stack (12 frames)                                          │
 5|     let│╰─ ▶ #1 🖼   global.functionFour                                 │
 6|     con│╰─ ▶ #2 🖼   global.functionThree                                │
 7| }      │╰─ ▶ #3 🖼   global.functionTwo                                  │
 8|        │╰─ ▼ #4 🖼   global.functionOne                                  │
 9| functio││  ╰─ ▶ 📁  Local: functionOne                                   │
10|     con││  ╰─ ▶ 🔒  Closure                                              │
11|     let││  ╰─ ▶ 🌍  Global                                               │
12|     ret│╰─ ▶ #5 🖼   global.main                                         │
13| }      │╰─ ▶ #6 🖼   <anonymous>                                         │
14|        │╰─ ▶ #7 🖼   Module._compile                                     │
15| functio│╰─ ▶ #8 🖼   Module._extensions..js                              │
16|     con│╰─ ▶ #9 🖼   Module.load                                         │
17|     let│╰─ ▶ #10 🖼   Module._load                                       │
18|     ret│╰─ ▶ #11 🖼   function Module(id = '', parent) {.executeUserEntry│
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               5,4-2         Top
]]


--[[ TERMINAL SNAPSHOT: 05_frame1_expanded
Size: 24x80
Cursor: [2, 3] (line 2, col 3)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - Stack Frames ───────────────────╮
 4|     con│▼ 📚  Stack (12 frames)                                          │
 5|     let│╰─ ▼ #1 🖼   global.functionFour                                 │
 6|     con││  ╰─ ▶ 📁  Local: functionFour                                  │
 7| }      ││  ╰─ ▶ 🔒  Closure                                              │
 8|        ││  ╰─ ▶ 🌍  Global                                               │
 9| functio│╰─ ▶ #2 🖼   global.functionThree                                │
10|     con│╰─ ▶ #3 🖼   global.functionTwo                                  │
11|     let│╰─ ▼ #4 🖼   global.functionOne                                  │
12|     ret││  ╰─ ▶ 📁  Local: functionOne                                   │
13| }      ││  ╰─ ▶ 🔒  Closure                                              │
14|        ││  ╰─ ▶ 🌍  Global                                               │
15| functio│╰─ ▶ #5 🖼   global.main                                         │
16|     con│╰─ ▶ #6 🖼   <anonymous>                                         │
17|     let│╰─ ▶ #7 🖼   Module._compile                                     │
18|     ret│╰─ ▶ #8 🖼   Module._extensions..js                              │
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               2,4-2         Top
]]