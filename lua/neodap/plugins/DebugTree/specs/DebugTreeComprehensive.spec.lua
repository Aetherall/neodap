-- Comprehensive DebugTree Test - Consolidates all features and scenarios
-- This test demonstrates the complete functionality of the DebugTree plugin
local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load all necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.DebugTree'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))

  -- ===== PART 1: BASIC SETUP AND TREE OPENING =====
  
  -- Open test file with complex variables
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 30j") -- Move to line 31 (debugger statement)
  T.TerminalSnapshot('01_file_opened')
  
  -- Launch debug session
  T.cmd("NeodapLaunchClosest Variables [variables]")
  T.sleep(1500) -- Wait for debugger to start and hit the debugger statement
  T.TerminalSnapshot('02_stopped_at_debugger')
  
  -- ===== PART 2: UNIFIED TREE VIEW (ALL SESSIONS) =====
  
  -- Open the main DebugTree showing all sessions
  T.cmd("DebugTree")
  T.sleep(300)
  T.TerminalSnapshot('03_debugtree_opened')
  
  -- Navigate and expand the session
  T.cmd("execute \"normal \\<CR>\"") -- Expand session
  T.sleep(200)
  T.TerminalSnapshot('04_session_expanded')
  
  -- Navigate to thread and expand
  T.cmd("normal! j") -- Move to thread
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread (should show stack)
  T.sleep(500)
  T.TerminalSnapshot('05_thread_expanded_with_stack')
  
  -- Check if auto-expansion worked for first frame
  T.cmd("normal! j") -- Move to stack
  T.cmd("normal! j") -- Move to first frame
  T.TerminalSnapshot('06_frame_auto_expansion_check')
  
  -- Manually expand first frame to see scopes
  T.cmd("execute \"normal \\<CR>\"") -- Expand frame
  T.sleep(300)
  T.TerminalSnapshot('07_frame_expanded_showing_scopes')
  
  -- ===== PART 3: VARIABLE INSPECTION WITH RICH FEATURES =====
  
  -- Expand Local scope to see variables
  T.cmd("normal! j") -- Move to Local scope
  T.cmd("execute \"normal \\<CR>\"") -- Expand Local scope
  T.sleep(500)
  T.TerminalSnapshot('08_local_scope_variables')
  
  -- Navigate through variables and expand complex types
  T.cmd("normal! j") -- Move to first variable
  T.cmd("normal! j") -- Move to arrayVar
  T.cmd("execute \"normal \\<CR>\"") -- Expand array
  T.sleep(200)
  T.TerminalSnapshot('09_array_expanded')
  
  -- Navigate to object variable and expand
  T.cmd("normal! /objectVar") -- Search for objectVar
  T.cmd("normal! n") -- Find first match
  T.cmd("execute \"normal \\<CR>\"") -- Expand object
  T.sleep(200)
  T.TerminalSnapshot('10_object_expanded')
  
  -- ===== PART 4: NAVIGATION FEATURES =====
  
  -- Test hjkl navigation
  T.cmd("normal! h") -- Collapse current node
  T.sleep(100)
  T.cmd("normal! l") -- Expand and enter
  T.sleep(100)
  T.TerminalSnapshot('11_hjkl_navigation')
  
  -- Test sibling navigation
  T.cmd("normal! H") -- Previous sibling
  T.sleep(100)
  T.cmd("normal! L") -- Next sibling
  T.sleep(100)
  T.TerminalSnapshot('12_sibling_navigation')
  
  -- ===== PART 5: FOCUS MODE =====
  
  -- Focus on current node (drill down)
  T.cmd("normal! f") -- Focus mode
  T.sleep(200)
  T.TerminalSnapshot('13_focus_mode_active')
  
  -- Navigate in focused view
  T.cmd("normal! j")
  T.cmd("normal! k")
  T.TerminalSnapshot('14_focus_mode_navigation')
  
  -- Unfocus to return to full view
  T.cmd("normal! F") -- Unfocus
  T.sleep(200)
  T.TerminalSnapshot('15_unfocused_full_view')
  
  -- ===== PART 6: HELP SYSTEM =====
  
  -- Show help
  T.cmd("normal! ?")
  T.sleep(500)
  T.TerminalSnapshot('16_help_displayed')
  
  -- Close notification and continue
  T.cmd("normal! q") -- Close any notification
  T.sleep(100)
  
  -- ===== PART 7: DEBUG INFO =====
  
  -- Show debug info for current node
  T.cmd("normal! !")
  T.sleep(300)
  T.TerminalSnapshot('17_debug_info_popup')
  
  -- Close debug info
  T.cmd("normal! q")
  T.sleep(100)
  
  -- Close the main tree
  T.cmd("normal! q")
  T.sleep(200)
  T.TerminalSnapshot('18_tree_closed')
  
  -- ===== PART 8: FRAME-SPECIFIC VIEW (Variables4 Compatibility) =====
  
  -- Open frame-specific tree (equivalent to Variables4)
  T.cmd("DebugTreeFrame")
  T.sleep(300)
  T.TerminalSnapshot('19_frame_tree_opened')
  
  -- This should show just the current frame's scopes and variables
  -- Navigate and expand scopes
  T.cmd("execute \"normal \\<CR>\"") -- Expand first scope
  T.sleep(300)
  T.TerminalSnapshot('20_frame_tree_scope_expanded')
  
  -- ===== PART 9: LAZY VARIABLE RESOLUTION =====
  
  -- Navigate to Global scope
  T.cmd("normal! j") -- Move down to Global scope
  T.cmd("execute \"normal \\<CR>\"") -- Expand Global
  T.sleep(1000) -- Wait for lazy loading
  T.TerminalSnapshot('21_global_scope_lazy_loaded')
  
  -- Close frame tree
  T.cmd("normal! q")
  T.sleep(200)
  
  -- ===== PART 10: STACK NAVIGATION TEST =====
  
  -- Set another breakpoint deeper in the call stack
  T.cmd("normal! 50j") -- Move down in file
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapContinue")
  T.sleep(1500) -- Wait for next breakpoint
  
  -- Open tree to see deeper stack
  T.cmd("DebugTree")
  T.sleep(300)
  T.cmd("execute \"normal \\<CR>\"") -- Expand session
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread
  T.sleep(500)
  T.TerminalSnapshot('22_deep_stack_view')
  
  -- Navigate through multiple stack frames
  T.cmd("normal! j") -- Move to stack
  T.cmd("normal! j") -- Move to first frame
  T.cmd("normal! j") -- Move to second frame
  T.cmd("normal! j") -- Move to third frame (if exists)
  T.TerminalSnapshot('23_stack_navigation')
  
  -- ===== PART 11: AUTO-EXPANSION ON STEP =====
  
  -- Close tree
  T.cmd("normal! q")
  T.sleep(200)
  
  -- Step to next line
  T.cmd("NeodapStepOver")
  T.sleep(1000)
  
  -- Reopen tree to check auto-expansion
  T.cmd("DebugTree")
  T.sleep(500)
  T.cmd("execute \"normal \\<CR>\"") -- Expand session
  T.cmd("normal! j")
  T.cmd("execute \"normal \\<CR>\"") -- Expand thread
  T.sleep(500)
  T.TerminalSnapshot('24_auto_expansion_after_step')
  
  -- ===== PART 12: RECURSIVE DATA STRUCTURES =====
  
  -- Navigate to a recursive structure if available
  T.cmd("normal! /circular")
  T.cmd("normal! n")
  T.cmd("execute \"normal \\<CR>\"") -- Try to expand circular reference
  T.sleep(200)
  T.TerminalSnapshot('25_circular_reference_handling')
  
  -- ===== PART 13: FINAL CLEANUP =====
  
  -- Close tree
  T.cmd("normal! q")
  T.sleep(200)
  
  -- Stop debugging
  T.cmd("NeodapStop")
  T.sleep(500)
  T.TerminalSnapshot('26_debugging_stopped')
  
  -- ===== VERIFICATION SUMMARY =====
  -- This comprehensive test verifies:
  -- 1. Basic tree opening and navigation
  -- 2. Session/Thread/Stack/Frame/Scope/Variable hierarchy
  -- 3. Rich variable display with type-specific icons
  -- 4. Manual and auto-expansion behavior
  -- 5. Vim-style navigation (hjkl)
  -- 6. Sibling navigation (H/L, K/J)
  -- 7. Focus mode for drilling into subtrees
  -- 8. Help system
  -- 9. Debug info display
  -- 10. Frame-specific view (Variables4 compatibility)
  -- 11. Lazy variable loading
  -- 12. Deep stack navigation
  -- 13. Auto-expansion on debugging events
  -- 14. Circular reference handling
  -- 15. Multiple view modes and their interactions
end)