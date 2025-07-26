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
  
  -- Debug: Let's analyze what the line content actually is
  -- We'll do this by adding some debug logging to understand the actual line content
  T.TerminalSnapshot('debug_initial_state')
  
  -- Let's try to print the actual line content and character positions
  -- This will help us understand what our findNameStartColumn should return
  
  -- Get the current line and analyze it character by character
  T.cmd("lua print('=== LINE CONTENT ANALYSIS ===')")
  T.cmd("lua local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ''")
  T.cmd("lua print('Line content: [' .. line .. ']')")
  T.cmd("lua print('Line length: ' .. #line)")
  T.cmd("lua for i = 1, #line do print(string.format('Pos %d: %s (byte: %d)', i, line:sub(i,i), line:byte(i))) end")
  
  T.sleep(500)
  T.TerminalSnapshot('debug_line_analysis')

  -- Close popup
  T.cmd("normal! q")
end)

--[[ TERMINAL SNAPSHOT: debug_initial_state
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