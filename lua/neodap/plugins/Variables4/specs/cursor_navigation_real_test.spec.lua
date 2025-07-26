local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  local variables4 = api:getPluginInstance(require('neodap.plugins.Variables4'))

  -- Set up initial state and launch session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j") -- Move to line with variables
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables")
  T.sleep(1500) -- Wait for session and breakpoint hit

  -- Open the variables tree popup
  T.cmd("Variables4Tree")
  T.sleep(300)
  T.TerminalSnapshot('cursor_real_initial_position')

  -- Test: Press j key to navigate down (using execute to send to current buffer/popup)
  T.cmd("execute \"normal \\<j>\"")
  T.sleep(100)
  T.TerminalSnapshot('cursor_real_after_j_navigation')

  -- Test: Press k key to navigate back up
  T.cmd("execute \"normal \\<k>\"")
  T.sleep(100)
  T.TerminalSnapshot('cursor_real_after_k_navigation')

  -- Test: Press l key to drill down
  T.cmd("execute \"normal \\<l>\"")
  T.sleep(300)
  T.TerminalSnapshot('cursor_real_after_l_drill_down')

  -- Test: Press h key to go back up
  T.cmd("execute \"normal \\<h>\"")
  T.sleep(200)
  T.TerminalSnapshot('cursor_real_after_h_back_up')

  -- Close popup
  T.cmd("execute \"normal \\<q>\"")
  T.sleep(100)
  T.TerminalSnapshot('cursor_real_after_close')
end)

--[[ TERMINAL SNAPSHOT: cursor_real_initial_position
Size: 24x80
Cursor: [1, 4] (line 1, col 4)
Mode: n

 1| // Test fixture for Variables plugin - various variable types
 2| 
 3| functio╭──────────────────── Variables4 Debug Tree ─────────────────────╮
 4|     // │▶ 📁  Local: testVariables                                       │
 5|     let│▶ 📁  Global                                                     │
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
24|                                                               1,5-3         All
]]