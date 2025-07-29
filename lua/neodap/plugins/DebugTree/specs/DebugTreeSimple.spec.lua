-- Simple DebugTree Test
-- Tests basic expansion to understand what's happening

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Set up debugging session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j")
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(2000)
  
  -- Open DebugTree and expand step by step
  T.cmd("DebugTree")
  T.sleep(500)
  T.TerminalSnapshot('01_initial_tree')
  
  -- Expand first session - cursor should be on Session 1
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500) 
  T.TerminalSnapshot('02_session_1_expanded')
  
  -- Move to Session 2 and expand it  
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500)
  T.TerminalSnapshot('03_session_2_expanded')
  
  -- Move to Thread and expand it
  T.cmd("normal! j") 
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(500)
  T.TerminalSnapshot('04_thread_expanded')
  
  -- Move to Stack and expand it - this should show frames
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(1000) -- Give extra time for frames to load
  T.TerminalSnapshot('05_stack_expanded_should_show_frames')
  
  -- Try to move to first frame if it exists
  T.cmd("normal! j")
  T.TerminalSnapshot('06_moved_to_potential_frame')
  
  -- Try to expand whatever we're on now
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(800)
  T.TerminalSnapshot('07_expanded_potential_frame')
  
  T.cmd("normal! q")
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



--[[ TERMINAL SNAPSHOT: 02_session_1_expanded
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



--[[ TERMINAL SNAPSHOT: 03_session_2_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]



--[[ TERMINAL SNAPSHOT: 04_thread_expanded
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
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
24|                                                               3,1           All
]]



--[[ TERMINAL SNAPSHOT: 05_stack_expanded_should_show_frames
Size: 24x80
Cursor: [4, 0] (line 4, col 0)
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
24|                                                               4,1           All
]]



--[[ TERMINAL SNAPSHOT: 06_moved_to_potential_frame
Size: 24x80
Cursor: [4, 0] (line 4, col 0)
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
24|                                                               4,1           All
]]



--[[ TERMINAL SNAPSHOT: 07_expanded_potential_frame
Size: 24x80
Cursor: [4, 0] (line 4, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|     let││  │  ╰─ ▶ 🖼   global.testVariables                             │
 9|     let││  │  ╰─ ▶ 🖼   <anonymous>                                      │
10|     let││  │  ╰─ ▶ 🖼   Module._compile                                  │lue";
11|     let││  │  ╰─ ▶ 🖼   Module._extensions..js                           │e trunc
12| ated wh││  │  ╰─ ▶ 🖼   Module.load                                      │
13|        ││  │  ╰─ ▶ 🖼   Module._load                                     │
14|     // ││  │  ╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEnt│
15|     let│ryPoint                                                         │
16|     let││  │  ╰─ ▶ 🖼   <anonymous>                                      │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               4,1           All
]]