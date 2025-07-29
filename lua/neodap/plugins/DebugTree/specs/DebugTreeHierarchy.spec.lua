-- Test to verify DebugTree properly maintains parent-child hierarchy
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Set up debugging session
  T.cmd("edit lua/testing/fixtures/loop/loop.js")
  T.cmd("NeodapLaunchClosest Loop [loop]")
  T.sleep(2000) -- Wait for session to start

  -- Open debug tree and capture hierarchy
  T.cmd("DebugTree")
  T.sleep(500)
  T.TerminalSnapshot('01_initial_hierarchy')

  -- Expand the session to show threads
  T.cmd("execute \"normal \\<CR>\"") -- Expand first node (session)
  T.sleep(300)
  T.TerminalSnapshot('02_session_expanded')
  
  -- Navigate to thread and expand to show stack
  T.cmd("normal! j") -- Move to thread
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread
  T.sleep(300)
  T.TerminalSnapshot('03_thread_expanded')
  
  -- Navigate to stack and expand to show frames
  T.cmd("normal! j") -- Move to stack
  T.cmd("execute \"normal \\<CR>\"") -- Expand stack  
  T.sleep(300)
  T.TerminalSnapshot('04_stack_expanded')
  
  -- Collapse all to verify hierarchy is maintained
  T.cmd("normal! h") -- Collapse stack
  T.cmd("normal! k") -- Move to thread
  T.cmd("normal! h") -- Collapse thread
  T.cmd("normal! k") -- Move to session
  T.cmd("normal! h") -- Collapse session
  T.sleep(300)
  T.TerminalSnapshot('05_all_collapsed')
end)