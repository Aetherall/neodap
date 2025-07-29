-- Test smart cursor positioning in DebugTree
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Use variables fixture for rich data
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j") -- Go to line with variables
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(2000) -- Wait for session to start and hit breakpoint
  
  -- Open DebugTree
  T.cmd("DebugTree")
  T.sleep(500)
  T.TerminalSnapshot('01_initial_tree')
  
  -- Navigate to session
  T.cmd("normal! j") -- Move to Session 2
  T.TerminalSnapshot('02_navigated_to_session')
  
  -- Expand session
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(300)
  
  -- Navigate to thread
  T.cmd("normal! j")
  T.TerminalSnapshot('03_navigated_to_thread')
  
  -- Expand thread
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(300)
  
  -- Navigate to stack
  T.cmd("normal! j")
  T.TerminalSnapshot('04_navigated_to_stack')
  
  -- Expand stack
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(800)
  
  -- Navigate to frame
  T.cmd("normal! j")
  T.TerminalSnapshot('05_navigated_to_frame')
  
  -- Expand frame
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(800)
  
  -- Navigate to Local scope
  T.cmd("normal! j")
  T.TerminalSnapshot('06_navigated_to_local_scope')
  
  -- Expand scope to see variables
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(1000)
  
  -- Navigate through variables
  T.cmd("normal! j") -- First variable
  T.TerminalSnapshot('07_first_variable')
  
  T.cmd("normal! j") -- Second variable
  T.TerminalSnapshot('08_second_variable')
  
  T.cmd("normal! j") -- Third variable
  T.TerminalSnapshot('09_third_variable')
  
  -- Navigate up
  T.cmd("normal! k")
  T.TerminalSnapshot('10_navigated_back_up')
  
  -- Clean up
  T.cmd("normal! q")
  T.sleep(200)
end)

--[[ TERMINAL SNAPSHOT: 01_initial_tree
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▶ 📡  Session 2                                                  │
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

--[[ TERMINAL SNAPSHOT: 02_navigated_to_session
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▶ 📡  Session 2                                                  │
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



--[[ TERMINAL SNAPSHOT: 03_navigated_to_thread
Size: 24x80
Cursor: [3, 11] (line 3, col 11)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▶ ⏸  Thread 0 (stopped)                                      │
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
24|                                                               3,12-6        All
]]


--[[ TERMINAL SNAPSHOT: 04_navigated_to_stack
Size: 24x80
Cursor: [4, 16] (line 4, col 16)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▶ 📚  Stack (8 frames)                                     │
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
24|                                                               4,17-9        All
]]


--[[ TERMINAL SNAPSHOT: 05_navigated_to_frame
Size: 24x80
Cursor: [6, 21] (line 6, col 21)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|     let││  │  ╰─ ▶ #1 🖼   global.testVariables                          │
 9|     let││  │  ╰─ ▶ #2 🖼   <anonymous>                                   │
10|     let││  │  ╰─ ▶ #3 🖼   Module._compile                               │lue";
11|     let││  │  ╰─ ▶ #4 🖼   Module._extensions..js                        │e trunc
12| ated wh││  │  ╰─ ▶ #5 🖼   Module.load                                   │
13|        ││  │  ╰─ ▶ #6 🖼   Module._load                                  │
14|     // ││  │  ╰─ ▶ #7 🖼   function Module(id = '', parent) {.executeUser│
15|     let││  │  ╰─ ▶ #8 🖼   <anonymous>                                   │
16|     let│                                                                │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               6,22-12       All
]]


--[[ TERMINAL SNAPSHOT: 06_navigated_to_local_scope
Size: 24x80
Cursor: [7, 21] (line 7, col 21)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|     let││  │  ╰─ ▶ #1 🖼   global.testVariables                          │
 9|     let││  │  ╰─ ▼ #2 🖼   <anonymous>                                   │
10|     let││  │  │  ╰─ ▶ 📁  Local                                          │lue";
11|     let││  │  │  ╰─ ▶ 🌍  Global                                         │e trunc
12| ated wh││  │  ╰─ ▶ #3 🖼   Module._compile                               │
13|        ││  │  ╰─ ▶ #4 🖼   Module._extensions..js                        │
14|     // ││  │  ╰─ ▶ #5 🖼   Module.load                                   │
15|     let││  │  ╰─ ▶ #6 🖼   Module._load                                  │
16|     let││  │  ╰─ ▶ #7 🖼   function Module(id = '', parent) {.executeUser│
17|        ││  │  ╰─ ▶ #8 🖼   <anonymous>                                   │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               7,22-12       All
]]


--[[ TERMINAL SNAPSHOT: 07_first_variable
Size: 24x80
Cursor: [8, 19] (line 8, col 19)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|     let││  │  ╰─ ▶ #1 🖼   global.testVariables                          │
 9|     let││  │  ╰─ ▼ #2 🖼   <anonymous>                                   │
10|     let││  │  │  ╰─ ▼ 📁  Local                                          │lue";
11|     let││  │  │  │  ╰─   󰉿 __dirname: "'/home/aetherall/workspace/githu.│e trunc
12| ated wh││  │  │  │  ╰─   󰉿 __filename: "'/home/aetherall/workspace/githu│
13|        ││  │  │  │  ╰─ ▶ 󰅩 exports: {}                                  │
14|     // ││  │  │  │  ╰─ ▶ 󰀬 module: Module {id: '.', path: '/home/aethera│
15|     let││  │  │  │  ╰─ ▶ 󰊕 require: ƒ require(path) { // ...            │
16|     let││  │  │  │  ╰─ ▶ 󰊕 testVariables: ƒ testVariables() { /...      │
17|        ││  │  │  │  ╰─ ▶ 󰅩 this: {...}                                  │
18|        ││  │  │  ╰─ ▶ 🌍  Global                                         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               8,20-12       Top
]]


--[[ TERMINAL SNAPSHOT: 08_second_variable
Size: 24x80
Cursor: [9, 19] (line 9, col 19)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|     let││  │  ╰─ ▶ #1 🖼   global.testVariables                          │
 9|     let││  │  ╰─ ▼ #2 🖼   <anonymous>                                   │
10|     let││  │  │  ╰─ ▼ 📁  Local                                          │lue";
11|     let││  │  │  │  ╰─   󰉿 __dirname: "'/home/aetherall/workspace/githu.│e trunc
12| ated wh││  │  │  │  ╰─   󰉿 __filename: "'/home/aetherall/workspace/githu│
13|        ││  │  │  │  ╰─ ▶ 󰅩 exports: {}                                  │
14|     // ││  │  │  │  ╰─ ▶ 󰀬 module: Module {id: '.', path: '/home/aethera│
15|     let││  │  │  │  ╰─ ▶ 󰊕 require: ƒ require(path) { // ...            │
16|     let││  │  │  │  ╰─ ▶ 󰊕 testVariables: ƒ testVariables() { /...      │
17|        ││  │  │  │  ╰─ ▶ 󰅩 this: {...}                                  │
18|        ││  │  │  ╰─ ▶ 🌍  Global                                         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               9,20-12       Top
]]


--[[ TERMINAL SNAPSHOT: 09_third_variable
Size: 24x80
Cursor: [10, 19] (line 10, col 19)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|     let││  │  ╰─ ▶ #1 🖼   global.testVariables                          │
 9|     let││  │  ╰─ ▼ #2 🖼   <anonymous>                                   │
10|     let││  │  │  ╰─ ▼ 📁  Local                                          │lue";
11|     let││  │  │  │  ╰─   󰉿 __dirname: "'/home/aetherall/workspace/githu.│e trunc
12| ated wh││  │  │  │  ╰─   󰉿 __filename: "'/home/aetherall/workspace/githu│
13|        ││  │  │  │  ╰─ ▶ 󰅩 exports: {}                                  │
14|     // ││  │  │  │  ╰─ ▶ 󰀬 module: Module {id: '.', path: '/home/aethera│
15|     let││  │  │  │  ╰─ ▶ 󰊕 require: ƒ require(path) { // ...            │
16|     let││  │  │  │  ╰─ ▶ 󰊕 testVariables: ƒ testVariables() { /...      │
17|        ││  │  │  │  ╰─ ▶ 󰅩 this: {...}                                  │
18|        ││  │  │  ╰─ ▶ 🌍  Global                                         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               10,20-12      Top
]]


--[[ TERMINAL SNAPSHOT: 10_navigated_back_up
Size: 24x80
Cursor: [9, 19] (line 9, col 19)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|     let││  │  ╰─ ▶ #1 🖼   global.testVariables                          │
 9|     let││  │  ╰─ ▼ #2 🖼   <anonymous>                                   │
10|     let││  │  │  ╰─ ▼ 📁  Local                                          │lue";
11|     let││  │  │  │  ╰─   󰉿 __dirname: "'/home/aetherall/workspace/githu.│e trunc
12| ated wh││  │  │  │  ╰─   󰉿 __filename: "'/home/aetherall/workspace/githu│
13|        ││  │  │  │  ╰─ ▶ 󰅩 exports: {}                                  │
14|     // ││  │  │  │  ╰─ ▶ 󰀬 module: Module {id: '.', path: '/home/aethera│
15|     let││  │  │  │  ╰─ ▶ 󰊕 require: ƒ require(path) { // ...            │
16|     let││  │  │  │  ╰─ ▶ 󰊕 testVariables: ƒ testVariables() { /...      │
17|        ││  │  │  │  ╰─ ▶ 󰅩 this: {...}                                  │
18|        ││  │  │  ╰─ ▶ 🌍  Global                                         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               9,20-12       Top
]]