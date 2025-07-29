-- Test to verify hierarchical IDs are working correctly with full tree expansion
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))

  -- Open test file and set breakpoint
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 9j") -- Move to line 10
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500) -- Wait for debugger to hit breakpoint
  
  -- Open debug tree
  T.cmd("DebugTree")
  T.sleep(300)
  T.TerminalSnapshot('tree_initial')
  
  -- Expand session
  T.cmd("normal! o") -- Expand first session
  T.sleep(100)
  T.TerminalSnapshot('session_expanded')
  
  -- Navigate to thread and expand
  T.cmd("normal! j") -- Move to thread
  T.cmd("normal! o") -- Expand thread
  T.sleep(100)
  T.TerminalSnapshot('thread_expanded')
  
  -- Navigate to stack and expand
  T.cmd("normal! j") -- Move to stack
  T.cmd("normal! o") -- Expand stack
  T.sleep(200) -- Wait for frames to load
  T.TerminalSnapshot('stack_expanded')
  
  -- Navigate to frame and expand  
  T.cmd("normal! j") -- Move to first frame
  T.cmd("normal! o") -- Expand frame
  T.sleep(200) -- Wait for scopes to load
  T.TerminalSnapshot('frame_expanded')
  
  -- Navigate to scope and show debug info
  T.cmd("normal! j") -- Move to first scope
  T.cmd("normal! !") -- Show debug info
  T.sleep(200)
  T.TerminalSnapshot('scope_debug_info')
  T.cmd("normal! q") -- Close debug popup
  
  -- Expand scope to see variables
  T.cmd("normal! o") -- Expand scope
  T.sleep(200) -- Wait for variables to load
  T.TerminalSnapshot('scope_expanded')
  
  -- Navigate to a variable and show debug info
  T.cmd("normal! j") -- Move to first variable
  T.cmd("normal! !") -- Show debug info
  T.sleep(200)
  T.TerminalSnapshot('variable_debug_info')
  T.cmd("normal! q") -- Close debug popup
  
  -- Expand a complex variable if it has children
  T.cmd("normal! j") -- Move to next variable
  T.cmd("normal! j") -- Move to another one that might be complex
  T.cmd("normal! o") -- Try to expand it
  T.sleep(200)
  T.TerminalSnapshot('nested_variable_expanded')
end)

--[[ TERMINAL SNAPSHOT: tree_initial
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
23| lua/testing/fixtures/variables/complex.js                     10,1           Top
24|                                                               1,1           All
]]