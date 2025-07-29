-- Simple test to debug DebugTree entity traversal
vim.cmd('set runtimepath+=.')

-- Load dependencies
require('nio').setup()

-- Initialize neodap
local manager, api = require('neodap').setup()

-- Load required plugins
api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport'))
api:getPluginInstance(require('neodap.plugins.BreakpointApi'))
api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint'))
api:getPluginInstance(require('neodap.plugins.DebugTree'))

-- Edit a test file
vim.cmd('edit lua/testing/fixtures/loop/loop.js')

-- Launch debug session
vim.schedule(function()
  vim.cmd('NeodapLaunchClosest Loop [loop]')
  
  -- Wait for session to start and show debug tree
  vim.defer_fn(function()
    vim.cmd('DebugTree')
  end, 2000)
end)