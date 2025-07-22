local T = require("testing.testing")(describe, it)

T.Scenario(function(api)
  -- Load necessary plugins
  api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
  api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
  api:getPluginInstance(require('neodap.plugins.Variables'))

  -- Use the long names fixture
  T.cmd("edit lua/testing/fixtures/variables/long_names.js")

  -- Need to call the function first
  T.cmd("normal! G")
  T.cmd("normal! o")
  T.cmd("normal! itestLongValues();")
  T.cmd("write")

  -- Launch directly with node
  T.cmd("!cd lua/testing/fixtures/variables && node long_names.js &")
  T.sleep(500)
  T.cmd("NeodapAttach 9229")
  T.sleep(2000) -- Give time for debugger to hit the debugger statement

  -- Open Variables window
  T.cmd("VariablesShow")
  T.sleep(500)

  -- Navigate to Variables window
  T.cmd("wincmd h")
  T.sleep(300)

  -- Expand Local scope
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(800)
  T.TerminalSnapshot('long_values_truncated')

  -- Navigate to deeplyNestedObject and expand
  T.cmd("normal! /deeplyNestedObject")
  T.cmd("execute \"normal \\<CR>\"")
  T.sleep(600)
  T.TerminalSnapshot('long_nested_names')
end)