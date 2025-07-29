-- Test stack expansion and DebugTreeStack command
-- This test verifies:
-- 1. Stack frames are loaded when expanding Stack node in DebugTree
-- 2. DebugTreeStack command opens a focused stack view

local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load required plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))

  -- Setup debugging session with stack fixture
  T.cmd("edit lua/testing/fixtures/stack/deep.js")
  T.cmd("normal! 28j")  -- Move to line 29 (debugger statement)
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Stack")
  T.sleep(2000)

  -- Test 1: Open debug tree and navigate to stack
  T.cmd("DebugTree")
  T.sleep(500)
  T.TerminalSnapshot('debugtree_opened')

  -- Navigate: Session 2 -> Thread -> Stack -> Try to expand stack
  T.cmd("normal! j")                 -- Move to Session 2
  T.cmd("execute \"normal \\<CR>\"") -- Expand Session 2
  T.sleep(300)
  
  T.cmd("normal! j")                 -- Move to Thread
  T.cmd("execute \"normal \\<CR>\"") -- Expand Thread
  T.sleep(300)
  
  T.cmd("normal! j")                 -- Move to Stack
  T.TerminalSnapshot('before_stack_expand')
  
  T.cmd("execute \"normal \\<CR>\"") -- Expand Stack - this should trigger frame loading
  T.sleep(1000)  -- Wait for frame loading
  T.TerminalSnapshot('stack_expanded_with_frames')

  T.cmd("normal! q")
  
  -- Test 2: DebugTreeStack command opens focused stack view
  T.sleep(300)
  T.cmd("DebugTreeStack")
  T.sleep(500)
  T.TerminalSnapshot('debugtree_stack_focused_view')
  
  -- Expand a frame to see scopes
  T.cmd("execute \"normal \\<CR>\"") -- Expand first frame
  T.sleep(300)
  T.TerminalSnapshot('stack_frame_expanded')
  
  T.cmd("normal! q")
end)

-- Note: Terminal snapshots will be generated when test is run