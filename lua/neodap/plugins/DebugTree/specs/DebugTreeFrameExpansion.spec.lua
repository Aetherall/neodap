-- Test frame expansion to scopes and variables
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
  
  -- Open DebugTree and navigate to frame
  T.cmd("DebugTree")
  T.sleep(500)
  
  -- Expand Session 2
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(300)
  
  -- Expand Thread
  T.cmd("normal! j") 
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(300)
  
  -- Expand Stack
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(800)
  T.TerminalSnapshot('stack_expanded_with_frames')
  
  -- Try to expand first frame
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(1000) -- Give time for async scope loading
  T.TerminalSnapshot('frame_expanded_should_show_scopes')
  
  -- Try to expand a scope if it exists
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(1000) -- Give time for async variable loading
  T.TerminalSnapshot('scope_expanded_should_show_variables')
  
  T.cmd("normal! q")
end)


--[[ TERMINAL SNAPSHOT: stack_expanded_with_frames
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


--[[ TERMINAL SNAPSHOT: frame_expanded_should_show_scopes
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
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
17|        │ryPoint                                                         │
18|        ││  │  ╰─ ▶ 🖼   <anonymous>                                      │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               5,1           All
]]



--[[ TERMINAL SNAPSHOT: scope_expanded_should_show_variables
Size: 24x80
Cursor: [6, 0] (line 6, col 0)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭────────────────── Debug Tree - All Sessions ───────────────────╮
 4|     // │▶ 📡  Session 1                                                  │
 5|     let│▼ 📡  Session 2                                                  │
 6|     let│╰─ ▼ ⏸  Thread 0 (stopped)                                      │
 7|     let││  ╰─ ▼ 📚  Stack (8 frames)                                     │
 8|     let││  │  ╰─ ▼ 🖼   global.testVariables                             │
 9|     let││  │  │  ╰─ ▼ 📁  Local: testVariables                           │
10|     let││  │  │  │  ╰─ ▶ 📝  arrayVar: (5) [1, 2, 3, 'four', {…}]        │lue";
11|     let││  │  │  │  ╰─   📝  booleanVar: true                            │e trunc
12| ated wh││  │  │  │  ╰─   📝  dateVar: Mon Jan 01 2024 01:00:00 GMT+0100 (│
13|        │Central Euro...                                                 │
14|     // ││  │  │  │  ╰─ ▶ 📝  functionVar: ƒ (x) { return x * 2; }        │
15|     let││  │  │  │  ╰─   📝  longStringValue: 'This is a very long string│
16|     let│ value that should b...                                         │
17|        ││  │  │  │  ╰─ ▶ 📝  mapVar: Map(2) {size: 2, key1 => value1, key│
18|        │2 => value2}                                                    │
19|        ╰────────────────────────────────────────────────────────────────╯
20|             level: 2,
21|             data: ["a", "b", "c"]
22|         },
23| lua/testing/fixtures/variables/complex.js                     7,1            Top
24|                                                               6,1           Top
]]