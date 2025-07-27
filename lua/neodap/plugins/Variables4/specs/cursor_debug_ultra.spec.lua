local T = require("testing.testing")(describe, it)
local CommonSetups = require("testing.common_setups")

T.Scenario(function(api)
  -- Use common setup - replaces 11 lines with 1 line!
  CommonSetups.setupAndOpenVariablesTree(T, api)

  -- Debug: Check if the plugin instance has the debugging state we need
  T.TerminalSnapshot('debug_before_tree_check_state')
  T.TerminalSnapshot('debug_tree_opened_or_failed')

  -- Test if the popup actually opened by trying to close it
  T.cmd("normal! q") -- Try to close
  T.sleep(200)
  T.TerminalSnapshot('debug_after_close_attempt')
end)

