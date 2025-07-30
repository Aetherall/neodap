-- Test auto-expansion of top frame and non-expensive scopes
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
  T.sleep(500) -- Give time for auto-expansion
  T.TerminalSnapshot('auto_expanded_initial')
  
  -- Navigate to see what's expanded
  -- Should see: Session > Thread > Stack > Frame #1 (expanded) > Local scope (expanded)
  T.cmd("normal! o") -- Expand session
  T.sleep(100)
  T.cmd("normal! j") -- Move to thread
  T.cmd("normal! o") -- Expand thread (stack should auto-expand with frame #1 and Local)
  T.sleep(500) -- Wait for auto-expansion
  T.TerminalSnapshot('after_thread_expand')
  
  -- Continue execution to see if auto-expansion works on next stop
  T.cmd("NeodapContinue")
  T.sleep(1500) -- Wait for next breakpoint
  T.TerminalSnapshot('auto_expanded_after_continue')
  
  -- Verify the tree structure is properly expanded
  T.cmd("normal! gg") -- Go to top
  T.cmd("normal! /Local") -- Search for Local scope
  T.cmd("normal! n") -- Find first match
  T.TerminalSnapshot('local_scope_visible')
end)

--[[ TERMINAL SNAPSHOT: auto_expanded_initial
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