-- DebugTree Unified Experience Test
-- Tests that a single DebugTree can expand from sessions all the way to variables

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load all required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Set up debugging session with complex variables
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j") -- Go to line with booleanVar = true
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(2000) -- Wait for session to start and hit breakpoint
  
  -- Open the unified DebugTree
  T.cmd("DebugTree")
  T.sleep(500)
  T.TerminalSnapshot('01_unified_tree_root')
  
  -- PHASE 1: Expand session to show threads
  T.cmd("execute \"normal \\<CR>\"") -- Expand session
  T.sleep(500)
  T.TerminalSnapshot('02_session_expanded')
  
  -- PHASE 2: Navigate to and expand thread
  T.cmd("normal! j") -- Move to thread
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread to show stack
  T.sleep(500)
  T.TerminalSnapshot('03_thread_expanded')
  
  -- PHASE 3: Navigate to and expand stack
  T.cmd("normal! j") -- Move to stack
  T.cmd("execute \"normal \\<CR>\"") -- Expand stack to show frames
  T.sleep(800) -- Extra time for frame loading
  T.TerminalSnapshot('04_stack_expanded_frames')
  
  -- PHASE 4: Navigate to and expand first frame
  T.cmd("normal! j") -- Move to first frame (testVariables)
  T.cmd("execute \"normal \\<CR>\"") -- Expand frame to show scopes
  T.sleep(800) -- Time for scope loading
  T.TerminalSnapshot('05_frame_expanded_scopes')
  
  -- PHASE 5: Navigate to and expand Local scope
  T.cmd("normal! j") -- Move to Local scope
  T.cmd("execute \"normal \\<CR>\"") -- Expand scope to show variables
  T.sleep(1000) -- Extra time for variable loading
  T.TerminalSnapshot('06_scope_expanded_variables')
  
  -- PHASE 6: Navigate to and expand a complex variable (arrayVar or objectVar)
  T.cmd("normal! j") -- Move to first variable
  T.cmd("normal! j") -- Move to next variable (might be arrayVar)
  T.cmd("execute \"normal \\<CR>\"") -- Expand variable to show children
  T.sleep(500)
  T.TerminalSnapshot('07_variable_expanded_children')
  
  -- PHASE 7: Navigate deeper into nested variable
  T.cmd("normal! j") -- Move to child variable
  T.cmd("execute \"normal \\<CR>\"") -- Try to expand if possible
  T.sleep(500)
  T.TerminalSnapshot('08_nested_variable_expansion')
  
  -- PHASE 8: Test navigation up and down the tree
  T.cmd("normal! k") -- Move up
  T.cmd("normal! k") -- Move to parent variable
  T.cmd("normal! k") -- Move to scope level
  T.TerminalSnapshot('09_navigation_up_hierarchy')
  
  -- PHASE 9: Collapse and re-expand to test state persistence
  T.cmd("execute \"normal \\<CR>\"") -- Collapse scope
  T.sleep(300)
  T.TerminalSnapshot('10_scope_collapsed')
  
  T.cmd("execute \"normal \\<CR>\"") -- Re-expand scope
  T.sleep(500)
  T.TerminalSnapshot('11_scope_re_expanded')
  
  -- PHASE 10: Final view showing complete hierarchy
  T.TerminalSnapshot('12_complete_unified_hierarchy')
  
  -- Clean up
  T.cmd("normal! q")
  T.sleep(200)
  T.TerminalSnapshot('13_cleanup')
end)


--[[ TERMINAL SNAPSHOT: 01_unified_tree_root
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



--[[ TERMINAL SNAPSHOT: 02_session_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▼ 📡  Session 1                                                  │
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



--[[ TERMINAL SNAPSHOT: 03_thread_expanded
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▼ 📡  Session 1                                                  │
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



--[[ TERMINAL SNAPSHOT: 04_stack_expanded_frames
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▼ 📡  Session 1                                                  │
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




--[[ TERMINAL SNAPSHOT: 05_frame_expanded_scopes
Size: 24x80
Cursor: [4, 0] (line 4, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▼ 📡  Session 1                                                  │
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
15|     let││  │  ╰─ ▶ 🖼   <anonymous>                                      │
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





--[[ TERMINAL SNAPSHOT: 06_scope_expanded_variables
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▼ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|     let││  │  ╰─ ▼ 🖼   global.testVariables                             │
 9|     let││  │  │  ╰─ ▶ 📁  Local: testVariables                           │
10|     let││  │  │  ╰─ ▶ 🌍  Global                                         │lue";
11|     let││  │  ╰─ ▶ 🖼   <anonymous>                                      │e trunc
12| ated wh││  │  ╰─ ▶ 🖼   Module._compile                                  │
13|        ││  │  ╰─ ▶ 🖼   Module._extensions..js                           │
14|     // ││  │  ╰─ ▶ 🖼   Module.load                                      │
15|     let││  │  ╰─ ▶ 🖼   Module._load                                     │
16|     let││  │  ╰─ ▶ 🖼   function Module(id = '', parent) {.executeUserEnt│
17|        ││  │  ╰─ ▶ 🖼   <anonymous>                                      │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               5,1           All
]]






--[[ TERMINAL SNAPSHOT: 07_variable_expanded_children
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▼ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|     let││  │  ╰─ ▼ 🖼   global.testVariables                             │
 9|     let││  │  │  ╰─ ▶ 📁  Local: testVariables                           │
10|     let││  │  │  ╰─ ▼ 🌍  Global                                         │lue";
11|     let││  │  │  │  ╰─ ▶ 📝  AbortController: ƒ () { mod ??= require(id);│e trunc
12| ated wh││  │  │  │  ╰─ ▶ 📝  AbortSignal: ƒ () { mod ??= require(id); if │
13|        ││  │  │  │  ╰─ ▶ 📝  atob: ƒ () { mod ??= require(id); if (lazyLo│
14|     // ││  │  │  │  ╰─ ▶ 📝  Blob: ƒ () { mod ??= require(id); if (lazyLo│
15|     let││  │  │  │  ╰─ ▶ 📝  BroadcastChannel: ƒ () { mod ??= require(id)│
16|     let││  │  │  │  ╰─ ▶ 📝  btoa: ƒ () { mod ??= require(id); if (lazyLo│
17|        ││  │  │  │  ╰─ ▶ 📝  Buffer: ƒ get() { return _Buffer; }         │
18|        ││  │  │  │  ╰─ ▶ 📝  ByteLengthQueuingStrategy: ƒ () { mod ??= re│
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               7,1           Top
]]




--[[ TERMINAL SNAPSHOT: 08_nested_variable_expansion
Size: 24x80
Cursor: [8, 0] (line 8, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▼ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|     let││  │  ╰─ ▼ 🖼   global.testVariables                             │
 9|     let││  │  │  ╰─ ▶ 📁  Local: testVariables                           │
10|     let││  │  │  ╰─ ▼ 🌍  Global                                         │lue";
11|     let││  │  │  │  ╰─ ▼ 📝  AbortController: ƒ () { mod ??= require(id);│e trunc
12| ated wh││  │  │  │  │  ╰─ ▶ 📝  AbortController: class AbortController {\│
13|        ││  │  │  │  ╰─ ▶ 📝  AbortSignal: ƒ () { mod ??= require(id); if │
14|     // ││  │  │  │  ╰─ ▶ 📝  atob: ƒ () { mod ??= require(id); if (lazyLo│
15|     let││  │  │  │  ╰─ ▶ 📝  Blob: ƒ () { mod ??= require(id); if (lazyLo│
16|     let││  │  │  │  ╰─ ▶ 📝  BroadcastChannel: ƒ () { mod ??= require(id)│
17|        ││  │  │  │  ╰─ ▶ 📝  btoa: ƒ () { mod ??= require(id); if (lazyLo│
18|        ││  │  │  │  ╰─ ▶ 📝  Buffer: ƒ get() { return _Buffer; }         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               8,1           Top
]]




--[[ TERMINAL SNAPSHOT: 09_navigation_up_hierarchy
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▼ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|     let││  │  ╰─ ▼ 🖼   global.testVariables                             │
 9|     let││  │  │  ╰─ ▶ 📁  Local: testVariables                           │
10|     let││  │  │  ╰─ ▼ 🌍  Global                                         │lue";
11|     let││  │  │  │  ╰─ ▼ 📝  AbortController: ƒ () { mod ??= require(id);│e trunc
12| ated wh││  │  │  │  │  ╰─ ▶ 📝  AbortController: class AbortController {\│
13|        ││  │  │  │  ╰─ ▶ 📝  AbortSignal: ƒ () { mod ??= require(id); if │
14|     // ││  │  │  │  ╰─ ▶ 📝  atob: ƒ () { mod ??= require(id); if (lazyLo│
15|     let││  │  │  │  ╰─ ▶ 📝  Blob: ƒ () { mod ??= require(id); if (lazyLo│
16|     let││  │  │  │  ╰─ ▶ 📝  BroadcastChannel: ƒ () { mod ??= require(id)│
17|        ││  │  │  │  ╰─ ▶ 📝  btoa: ƒ () { mod ??= require(id); if (lazyLo│
18|        ││  │  │  │  ╰─ ▶ 📝  Buffer: ƒ get() { return _Buffer; }         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               5,1           Top
]]




--[[ TERMINAL SNAPSHOT: 10_scope_collapsed
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▼ 📡  Session 1                                                  │
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
15|     let││  │  ╰─ ▶ 🖼   <anonymous>                                      │
16|     let│                                                                │
17|        │                                                                │
18|        │                                                                │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               5,1           All
]]




--[[ TERMINAL SNAPSHOT: 11_scope_re_expanded
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▼ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|     let││  │  ╰─ ▼ 🖼   global.testVariables                             │
 9|     let││  │  │  ╰─ ▶ 📁  Local: testVariables                           │
10|     let││  │  │  ╰─ ▼ 🌍  Global                                         │lue";
11|     let││  │  │  │  ╰─ ▼ 📝  AbortController: ƒ () { mod ??= require(id);│e trunc
12| ated wh││  │  │  │  │  ╰─ ▶ 📝  AbortController: class AbortController {\│
13|        ││  │  │  │  ╰─ ▶ 📝  AbortSignal: ƒ () { mod ??= require(id); if │
14|     // ││  │  │  │  ╰─ ▶ 📝  atob: ƒ () { mod ??= require(id); if (lazyLo│
15|     let││  │  │  │  ╰─ ▶ 📝  Blob: ƒ () { mod ??= require(id); if (lazyLo│
16|     let││  │  │  │  ╰─ ▶ 📝  BroadcastChannel: ƒ () { mod ??= require(id)│
17|        ││  │  │  │  ╰─ ▶ 📝  btoa: ƒ () { mod ??= require(id); if (lazyLo│
18|        ││  │  │  │  ╰─ ▶ 📝  Buffer: ƒ get() { return _Buffer; }         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               5,1           Top
]]




--[[ TERMINAL SNAPSHOT: 12_complete_unified_hierarchy
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▼ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|     let││  │  ╰─ ▼ 🖼   global.testVariables                             │
 9|     let││  │  │  ╰─ ▶ 📁  Local: testVariables                           │
10|     let││  │  │  ╰─ ▼ 🌍  Global                                         │lue";
11|     let││  │  │  │  ╰─ ▼ 📝  AbortController: ƒ () { mod ??= require(id);│e trunc
12| ated wh││  │  │  │  │  ╰─ ▶ 📝  AbortController: class AbortController {\│
13|        ││  │  │  │  ╰─ ▶ 📝  AbortSignal: ƒ () { mod ??= require(id); if │
14|     // ││  │  │  │  ╰─ ▶ 📝  atob: ƒ () { mod ??= require(id); if (lazyLo│
15|     let││  │  │  │  ╰─ ▶ 📝  Blob: ƒ () { mod ??= require(id); if (lazyLo│
16|     let││  │  │  │  ╰─ ▶ 📝  BroadcastChannel: ƒ () { mod ??= require(id)│
17|        ││  │  │  │  ╰─ ▶ 📝  btoa: ƒ () { mod ??= require(id); if (lazyLo│
18|        ││  │  │  │  ╰─ ▶ 📝  Buffer: ƒ get() { return _Buffer; }         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               5,1           Top
]]




--[[ TERMINAL SNAPSHOT: 13_cleanup
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▼ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|     let││  │  ╰─ ▼ 🖼   global.testVariables                             │
 9|     let││  │  │  ╰─ ▶ 📁  Local: testVariables                           │
10|     let││  │  │  ╰─ ▼ 🌍  Global                                         │lue";
11|     let││  │  │  │  ╰─ ▼ 📝  AbortController: ƒ () { mod ??= require(id);│e trunc
12| ated wh││  │  │  │  │  ╰─ ▶ 📝  AbortController: class AbortController {\│
13|        ││  │  │  │  ╰─ ▶ 📝  AbortSignal: ƒ () { mod ??= require(id); if │
14|     // ││  │  │  │  ╰─ ▶ 📝  atob: ƒ () { mod ??= require(id); if (lazyLo│
15|     let││  │  │  │  ╰─ ▶ 📝  Blob: ƒ () { mod ??= require(id); if (lazyLo│
16|     let││  │  │  │  ╰─ ▶ 📝  BroadcastChannel: ƒ () { mod ??= require(id)│
17|        ││  │  │  │  ╰─ ▶ 📝  btoa: ƒ () { mod ??= require(id); if (lazyLo│
18|        ││  │  │  │  ╰─ ▶ 📝  Buffer: ƒ get() { return _Buffer; }         │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               5,1           Top
]]