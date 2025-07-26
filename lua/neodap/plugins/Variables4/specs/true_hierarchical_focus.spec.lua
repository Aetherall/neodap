local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
  api:getPluginInstance(require('neodap.plugins.Variables4'))

  -- Set up initial state and launch session
  T.cmd("edit lua/testing/fixtures/variables/complex.js")
  T.cmd("normal! 6j") -- Move to line with variables
  T.cmd("NeodapToggleBreakpoint")
  T.cmd("NeodapLaunchClosest Variables")
  T.sleep(1500) -- Wait for session and breakpoint hit

  -- Open the variables tree popup
  T.cmd("Variables4Tree")
  T.sleep(300)
  T.TerminalSnapshot('true_hierarchical_initial_all_scopes')

  -- Navigate deep into Local scope
  T.cmd("normal! l") -- Expand Local scope
  T.sleep(500)
  T.cmd("normal! j") -- Move to first variable
  T.cmd("normal! l") -- Expand first variable (if possible)
  T.sleep(300)
  T.cmd("normal! j") -- Move to child variable
  T.TerminalSnapshot('true_hierarchical_deep_in_local_scope')

  -- Enable focus mode from deep position
  T.cmd("normal! f") -- Enable focus mode
  T.sleep(200)
  T.TerminalSnapshot('true_hierarchical_focus_enabled_deep')

  -- Test the TRUE three-level hierarchy
  -- Level 1: h-key should expand from focused subtree to scope subtree
  T.cmd("normal! h") -- First h: expand to scope view
  T.sleep(300)
  T.TerminalSnapshot('true_hierarchical_h1_scope_view')

  -- Level 2: h-key should expand from scope subtree to ALL SCOPES
  T.cmd("normal! h") -- Second h: expand to all scopes view
  T.sleep(300)
  T.TerminalSnapshot('true_hierarchical_h2_all_scopes_view')

  -- Level 3: h-key should stay at all scopes (can't expand further)
  T.cmd("normal! h") -- Third h: should stay at all scopes
  T.sleep(200)
  T.TerminalSnapshot('true_hierarchical_h3_stays_at_all_scopes')

  -- Test navigation within all scopes focus mode
  T.cmd("normal! j") -- Move to Global scope
  T.sleep(100)
  T.TerminalSnapshot('true_hierarchical_navigate_to_global_in_focus')

  -- Test drilling down from Global scope
  T.cmd("normal! l") -- Expand Global scope
  T.sleep(500)
  T.TerminalSnapshot('true_hierarchical_expand_global_adjusts_focus')

  -- Navigate within Global scope variables
  T.cmd("normal! j") -- Move to global variable
  T.sleep(100)
  T.TerminalSnapshot('true_hierarchical_in_global_variables')

  -- Test h-key hierarchy from Global context
  T.cmd("normal! h") -- Should expand to scope view (Global scope)
  T.sleep(200)
  T.TerminalSnapshot('true_hierarchical_global_to_scope_view')

  T.cmd("normal! h") -- Should expand to all scopes view
  T.sleep(200)
  T.TerminalSnapshot('true_hierarchical_global_to_all_scopes')

  -- Navigate back to Local scope and test full cycle
  T.cmd("normal! k") -- Move back to Local scope
  T.cmd("normal! l") -- Drill into Local scope again
  T.sleep(300)
  T.cmd("normal! j") -- Move to local variable
  T.cmd("normal! l") -- Drill deeper
  T.sleep(300)
  T.TerminalSnapshot('true_hierarchical_back_in_local_deep')

  -- Test the full hierarchy again from different context
  T.cmd("normal! h") -- Level 1: to scope view
  T.sleep(200)
  T.TerminalSnapshot('true_hierarchical_local_deep_to_scope')

  T.cmd("normal! h") -- Level 2: to all scopes view  
  T.sleep(200)
  T.TerminalSnapshot('true_hierarchical_local_deep_to_all_scopes')

  T.cmd("normal! h") -- Level 3: stay at all scopes
  T.sleep(200)
  T.TerminalSnapshot('true_hierarchical_local_deep_max_expansion')

  -- Test exit and re-entry still works
  T.cmd("normal! f") -- Exit focus mode
  T.sleep(200)
  T.TerminalSnapshot('true_hierarchical_exit_focus_mode')

  -- Re-enter and verify hierarchy works from different starting point
  T.cmd("normal! j") -- Move to Global
  T.cmd("normal! l") -- Expand Global
  T.sleep(300)
  T.cmd("normal! f") -- Re-enter focus mode
  T.sleep(200)
  T.TerminalSnapshot('true_hierarchical_reenter_from_global')

  -- Quick test of hierarchy from Global context
  T.cmd("normal! h") -- Scope view
  T.sleep(200)
  T.cmd("normal! h") -- All scopes view
  T.sleep(200)
  T.TerminalSnapshot('true_hierarchical_global_full_hierarchy')

  -- Show updated help text
  T.cmd("normal! ?")
  T.TerminalSnapshot('true_hierarchical_updated_help')

  -- Close popup
  T.cmd("normal! q")
  T.TerminalSnapshot('true_hierarchical_test_complete')
end)