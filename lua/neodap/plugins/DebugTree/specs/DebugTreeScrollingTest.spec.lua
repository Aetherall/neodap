-- Test navigation with scrolling in a tree that has more nodes than fit in window
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
  
  -- Open stack-specific tree to focus on many frames
  T.cmd("DebugTreeStack")
  T.sleep(500)
  T.TerminalSnapshot('01_stack_tree_initial')
  
  -- Expand stack to show all frames
  T.cmd("execute \"normal \\<CR>\"") -- Expand stack
  T.sleep(800)
  T.TerminalSnapshot('02_stack_expanded_all_frames')
  
  -- Navigate down through frames to test scrolling
  -- The popup should be smaller than 12 frames, so we'll need scrolling
  T.cmd("normal! j") -- Frame 1
  T.cmd("normal! j") -- Frame 2  
  T.cmd("normal! j") -- Frame 3
  T.cmd("normal! j") -- Frame 4
  T.cmd("normal! j") -- Frame 5
  T.cmd("normal! j") -- Frame 6
  T.cmd("normal! j") -- Frame 7
  T.cmd("normal! j") -- Frame 8
  T.TerminalSnapshot('03_navigated_to_frame8')
  
  -- Continue navigating to frames that might be off-screen
  T.cmd("normal! j") -- Frame 9
  T.cmd("normal! j") -- Frame 10
  T.cmd("normal! j") -- Frame 11
  T.cmd("normal! j") -- Frame 12 (last frame)
  T.TerminalSnapshot('04_navigated_to_bottom_frame')
  
  -- Navigate back up to test scrolling in reverse
  T.cmd("normal! 10k") -- Jump up 10 lines
  T.TerminalSnapshot('05_scrolled_back_up')
  
  -- Test page-down equivalent
  T.cmd("normal! 10j") -- Jump down 10 lines
  T.TerminalSnapshot('06_page_down_effect')
  
  -- Test navigating to top
  T.cmd("normal! gg") -- Go to top
  T.TerminalSnapshot('07_back_to_top')
  
  -- Test navigating to bottom
  T.cmd("normal! G") -- Go to bottom
  T.TerminalSnapshot('08_jumped_to_bottom')
  
  -- Clean up
  T.cmd("normal! q")
  T.sleep(200)
end)

--[[ TERMINAL SNAPSHOT: 01_stack_tree_initial
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

--[[ TERMINAL SNAPSHOT: 02_stack_expanded_all_frames
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - Stack Frames ───────────────────╮
 4|     con│▼ 📚  Stack (12 frames)                                          │
 5|     let│╰─ ▶ 🖼   global.functionFour                                    │
 6|     con│╰─ ▶ 🖼   global.functionThree                                   │
 7| }      │╰─ ▶ 🖼   global.functionTwo                                     │
 8|        │╰─ ▶ 🖼   global.functionOne                                     │
 9| functio│╰─ ▶ 🖼   global.main                                            │
10|     con│╰─ ▶ 🖼   <anonymous>                                            │
11|     let│╰─ ▶ 🖼   Module._compile                                        │
12|     ret│╰─ ▶ 🖼   Module._extensions..js                                 │
13| }      │╰─ ▶ 🖼   Module.load                                            │
14|        │╰─ ▶ 🖼   Module._load                                           │
15| functio│╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEntryPoin│
16|     con│╰─ ▶ 🖼   <anonymous>                                            │
17|     let│                                                                │
18|     ret│                                                                │
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: 03_navigated_to_frame8
Size: 24x80
Cursor: [10, 0] (line 10, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - Stack Frames ───────────────────╮
 4|     con│▼ 📚  Stack (12 frames)                                          │
 5|     let│╰─ ▶ 🖼   global.functionFour                                    │
 6|     con│╰─ ▶ 🖼   global.functionThree                                   │
 7| }      │╰─ ▶ 🖼   global.functionTwo                                     │
 8|        │╰─ ▶ 🖼   global.functionOne                                     │
 9| functio│╰─ ▶ 🖼   global.main                                            │
10|     con│╰─ ▶ 🖼   <anonymous>                                            │
11|     let│╰─ ▶ 🖼   Module._compile                                        │
12|     ret│╰─ ▶ 🖼   Module._extensions..js                                 │
13| }      │╰─ ▶ 🖼   Module.load                                            │
14|        │╰─ ▶ 🖼   Module._load                                           │
15| functio│╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEntryPoin│
16|     con│╰─ ▶ 🖼   <anonymous>                                            │
17|     let│                                                                │
18|     ret│                                                                │
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               10,1          All
]]

--[[ TERMINAL SNAPSHOT: 04_navigated_to_bottom_frame
Size: 24x80
Cursor: [13, 0] (line 13, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - Stack Frames ───────────────────╮
 4|     con│▼ 📚  Stack (12 frames)                                          │
 5|     let│╰─ ▶ 🖼   global.functionFour                                    │
 6|     con│╰─ ▶ 🖼   global.functionThree                                   │
 7| }      │╰─ ▶ 🖼   global.functionTwo                                     │
 8|        │╰─ ▶ 🖼   global.functionOne                                     │
 9| functio│╰─ ▶ 🖼   global.main                                            │
10|     con│╰─ ▶ 🖼   <anonymous>                                            │
11|     let│╰─ ▶ 🖼   Module._compile                                        │
12|     ret│╰─ ▶ 🖼   Module._extensions..js                                 │
13| }      │╰─ ▶ 🖼   Module.load                                            │
14|        │╰─ ▶ 🖼   Module._load                                           │
15| functio│╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEntryPoin│
16|     con│╰─ ▶ 🖼   <anonymous>                                            │
17|     let│                                                                │
18|     ret│                                                                │
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               13,1          All
]]

--[[ TERMINAL SNAPSHOT: 05_scrolled_back_up
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - Stack Frames ───────────────────╮
 4|     con│▼ 📚  Stack (12 frames)                                          │
 5|     let│╰─ ▶ 🖼   global.functionFour                                    │
 6|     con│╰─ ▶ 🖼   global.functionThree                                   │
 7| }      │╰─ ▶ 🖼   global.functionTwo                                     │
 8|        │╰─ ▶ 🖼   global.functionOne                                     │
 9| functio│╰─ ▶ 🖼   global.main                                            │
10|     con│╰─ ▶ 🖼   <anonymous>                                            │
11|     let│╰─ ▶ 🖼   Module._compile                                        │
12|     ret│╰─ ▶ 🖼   Module._extensions..js                                 │
13| }      │╰─ ▶ 🖼   Module.load                                            │
14|        │╰─ ▶ 🖼   Module._load                                           │
15| functio│╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEntryPoin│
16|     con│╰─ ▶ 🖼   <anonymous>                                            │
17|     let│                                                                │
18|     ret│                                                                │
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               3,1           All
]]

--[[ TERMINAL SNAPSHOT: 06_page_down_effect
Size: 24x80
Cursor: [13, 0] (line 13, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - Stack Frames ───────────────────╮
 4|     con│▼ 📚  Stack (12 frames)                                          │
 5|     let│╰─ ▶ 🖼   global.functionFour                                    │
 6|     con│╰─ ▶ 🖼   global.functionThree                                   │
 7| }      │╰─ ▶ 🖼   global.functionTwo                                     │
 8|        │╰─ ▶ 🖼   global.functionOne                                     │
 9| functio│╰─ ▶ 🖼   global.main                                            │
10|     con│╰─ ▶ 🖼   <anonymous>                                            │
11|     let│╰─ ▶ 🖼   Module._compile                                        │
12|     ret│╰─ ▶ 🖼   Module._extensions..js                                 │
13| }      │╰─ ▶ 🖼   Module.load                                            │
14|        │╰─ ▶ 🖼   Module._load                                           │
15| functio│╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEntryPoin│
16|     con│╰─ ▶ 🖼   <anonymous>                                            │
17|     let│                                                                │
18|     ret│                                                                │
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               13,1          All
]]

--[[ TERMINAL SNAPSHOT: 07_back_to_top
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - Stack Frames ───────────────────╮
 4|     con│▼ 📚  Stack (12 frames)                                          │
 5|     let│╰─ ▶ 🖼   global.functionFour                                    │
 6|     con│╰─ ▶ 🖼   global.functionThree                                   │
 7| }      │╰─ ▶ 🖼   global.functionTwo                                     │
 8|        │╰─ ▶ 🖼   global.functionOne                                     │
 9| functio│╰─ ▶ 🖼   global.main                                            │
10|     con│╰─ ▶ 🖼   <anonymous>                                            │
11|     let│╰─ ▶ 🖼   Module._compile                                        │
12|     ret│╰─ ▶ 🖼   Module._extensions..js                                 │
13| }      │╰─ ▶ 🖼   Module.load                                            │
14|        │╰─ ▶ 🖼   Module._load                                           │
15| functio│╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEntryPoin│
16|     con│╰─ ▶ 🖼   <anonymous>                                            │
17|     let│                                                                │
18|     ret│                                                                │
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: 08_jumped_to_bottom
Size: 24x80
Cursor: [13, 0] (line 13, col 0)
Mode: n

 1| // Test fixture for stack navigation - creates a deep call stack
 2| 
 3| functio╭────────────────── Debug Tree - Stack Frames ───────────────────╮
 4|     con│▼ 📚  Stack (12 frames)                                          │
 5|     let│╰─ ▶ 🖼   global.functionFour                                    │
 6|     con│╰─ ▶ 🖼   global.functionThree                                   │
 7| }      │╰─ ▶ 🖼   global.functionTwo                                     │
 8|        │╰─ ▶ 🖼   global.functionOne                                     │
 9| functio│╰─ ▶ 🖼   global.main                                            │
10|     con│╰─ ▶ 🖼   <anonymous>                                            │
11|     let│╰─ ▶ 🖼   Module._compile                                        │
12|     ret│╰─ ▶ 🖼   Module._extensions..js                                 │
13| }      │╰─ ▶ 🖼   Module.load                                            │
14|        │╰─ ▶ 🖼   Module._load                                           │
15| functio│╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEntryPoin│
16|     con│╰─ ▶ 🖼   <anonymous>                                            │
17|     let│                                                                │
18|     ret│                                                                │
19| }      ╰────────────────────────────────────────────────────────────────╯
20| 
21| function functionThree(z) {
22|     console.log("In functionThree with z =", z);
23| lua/testing/fixtures/stack/deep.js                            9,1            Top
24|                                                               13,1          All
]]