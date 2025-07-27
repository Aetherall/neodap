-- Common test setup utilities to eliminate duplication across test files
-- Provides reusable scenarios for debugging setups

local CommonSetups = {}

---Load standard debugging plugins required by most tests
---@param api Api
---@return table plugin_instances
function CommonSetups.loadStandardPlugins(api)
  return {
    launchJsonSupport = api:getPluginInstance(require('neodap.plugins.LaunchJsonSupport')),
    breakpointApi = api:getPluginInstance(require('neodap.plugins.BreakpointApi')),
    toggleBreakpoint = api:getPluginInstance(require('neodap.plugins.ToggleBreakpoint')),
    variables4 = api:getPluginInstance(require('neodap.plugins.Variables4')),
    -- New buffer-centric plugins
    variablesBuffer = api:getPluginInstance(require('neodap.plugins.VariablesBuffer')),
    variablesPopup = api:getPluginInstance(require('neodap.plugins.VariablesPopup')),
    debugMode = api:getPluginInstance(require('neodap.plugins.DebugMode')),
    debugOverlay = api:getPluginInstance(require('neodap.plugins.DebugOverlay'))
  }
end

---Set up a Variables4 debugging session with complex fixture
---@param T table Testing framework
---@param api Api
---@param options? {fixture?: string, launch_config?: string, breakpoint_line?: number}
---@return table plugin_instances
function CommonSetups.setupVariablesDebugging(T, api, options)
  local opts = options or {}
  local fixture = opts.fixture or "lua/testing/fixtures/variables/complex.js"
  local launch_config = opts.launch_config or "Variables"
  local breakpoint_line = opts.breakpoint_line or 6
  
  -- Load plugins
  local plugins = CommonSetups.loadStandardPlugins(api)
  
  -- Set up debugging session
  T.cmd("edit " .. fixture)
  if breakpoint_line then
    T.cmd("normal! " .. breakpoint_line .. "j")
    T.cmd("NeodapToggleBreakpoint")
  end
  T.cmd("NeodapLaunchClosest " .. launch_config)
  T.sleep(1500) -- Wait for session and breakpoint hit
  
  return plugins
end

---Set up Variables4 debugging with deep nested fixture for focus mode tests
---@param T table Testing framework
---@param api Api
---@return table plugin_instances
function CommonSetups.setupDeepNestedVariables(T, api)
  return CommonSetups.setupVariablesDebugging(T, api, {
    fixture = "lua/testing/fixtures/variables/deep_nested.js",
    launch_config = "Deep Nested [variables]",
    breakpoint_line = nil -- Deep nested may not need explicit breakpoint
  })
end

---Set up Variables4 debugging with recursive reference fixture
---@param T table Testing framework
---@param api Api
---@return table plugin_instances
function CommonSetups.setupRecursiveVariables(T, api)
  return CommonSetups.setupVariablesDebugging(T, api, {
    fixture = "lua/testing/fixtures/variables/recursive.js",
    launch_config = "Recursive [variables]",
    breakpoint_line = 5
  })
end

---Open Variables4 tree popup with standard timing
---@param T table Testing framework
---@param command? string Command to open tree (default: "Variables4Tree")
function CommonSetups.openVariablesTree(T, command)
  T.cmd(command or "Variables4Tree")
  T.sleep(300) -- Standard wait for tree popup
end

---Standard sequence: setup debugging + open tree
---@param T table Testing framework  
---@param api Api
---@param options? {fixture?: string, launch_config?: string, breakpoint_line?: number}
---@return table plugin_instances
function CommonSetups.setupAndOpenVariablesTree(T, api, options)
  local plugins = CommonSetups.setupVariablesDebugging(T, api, options)
  CommonSetups.openVariablesTree(T)
  return plugins
end

---Navigation setup for hjkl/arrow key tests
---@param T table Testing framework
---@param api Api
---@return table plugin_instances
function CommonSetups.setupNavigationTest(T, api)
  local plugins = CommonSetups.setupAndOpenVariablesTree(T, api)
  
  -- Expand a few nodes for navigation testing
  T.cmd("execute \"normal \\<CR>\"") -- Expand first scope
  T.sleep(200)
  T.cmd("normal! j") -- Move to next item
  T.cmd("execute \"normal \\<CR>\"") -- Expand variable
  T.sleep(200)
  
  return plugins
end

---Focus mode testing setup with deep nested data
---@param T table Testing framework
---@param api Api
---@return table plugin_instances
function CommonSetups.setupFocusModeTest(T, api)
  local plugins = CommonSetups.setupDeepNestedVariables(T, api)
  CommonSetups.openVariablesTree(T)
  
  -- Navigate to a deep node for focus testing
  T.cmd("execute \"normal \\<CR>\"") -- Expand scope
  T.sleep(200)
  T.cmd("normal! j") -- Navigate down
  T.cmd("execute \"normal \\<CR>\"") -- Expand nested object
  T.sleep(200)
  
  return plugins
end

return CommonSetups