local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local BreakpointVirtualText = require("neodap.plugins.BreakpointVirtualText")
local nio = require("nio")

Test.Describe("LaunchJsonSupport Plugin", function()

  Test.It("launch_json_breakpoint_hit_workflow", function()
    local original_dir = vim.fn.getcwd()
    local api = prepare()
    
    -- Load plugins
    local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)
    api:getPluginInstance(BreakpointApi)
    local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
    api:getPluginInstance(BreakpointVirtualText)
    
    -- Open loop.js from fixture
    local fixture_path = vim.fn.fnamemodify("spec/fixtures/workspaces/single-node-project", ":p")
    vim.api.nvim_set_current_dir(fixture_path)
    vim.cmd("edit loop.js")
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.api.nvim_set_current_dir(original_dir)
    
    -- Visual confirmation: project file opened
    Test.TerminalSnapshot("project_file_opened")
    
    -- Set breakpoint on repeating line
    toggleBreakpoint:toggle()
    nio.sleep(20)
    
    -- Visual confirmation: breakpoint set
    Test.TerminalSnapshot("breakpoint_set_in_launch_json_project")
    
    -- Load launch.json configurations
    vim.api.nvim_set_current_dir(fixture_path)
    local configs = launchJsonSupport:loadAllConfigurations()
    assert(next(configs) ~= nil, "Should have launch.json configurations")
    vim.api.nvim_set_current_dir(original_dir)
    
    -- Visual confirmation: configurations loaded
    Test.TerminalSnapshot("launch_json_configurations_loaded")
    
    -- Track breakpoint hit
    local breakpoint_hit = false
    
    -- Register session listener
    api:onSession(function(session)
      session:onInitialized(function() end, { once = true })
      session:onThread(function(thread)
        thread:onStopped(function(event)
          if event.reason == "breakpoint" then
            breakpoint_hit = true
            -- Visual confirmation: breakpoint hit (execution stopped)
            Test.TerminalSnapshot("breakpoint_hit_from_session")
          end
        end)
      end)
    end)
    
    -- Create session from launch.json
    local workspace_info = launchJsonSupport:detectWorkspace(fixture_path)
    launchJsonSupport:createSessionFromConfig("Debug Loop []", api.manager, workspace_info)
    
    -- Wait for breakpoint hit
    vim.wait(5000, function() return breakpoint_hit end)
    
    -- Visual confirmation: workflow completed
    Test.TerminalSnapshot("launch_json_workflow_completed")
  end)


end)


--[[ TERMINAL SNAPSHOT: project_file_opened
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);
 4|  console.log("BLoop iteration: ", i++);
 5|  console.log("CLoop iteration: ", i++);
 6|  console.log("DLoop iteration: ", i++);
 7| }, 1000)
 8| ~
 9| ~
10| ~
11| ~
12| ~
13| ~
14| ~
15| ~
16| ~
17| ~
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,1            All
24| 
]]



--[[ TERMINAL SNAPSHOT: breakpoint_set_in_launch_json_project
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3| ● console.log("ALoop iteration: ", i++);
 4|  console.log("BLoop iteration: ", i++);
 5|  console.log("CLoop iteration: ", i++);
 6|  console.log("DLoop iteration: ", i++);
 7| }, 1000)
 8| ~
 9| ~
10| ~
11| ~
12| ~
13| ~
14| ~
15| ~
16| ~
17| ~
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,1-2          All
24| ✓ Terminal snapshot 'project_file_opened' matches
]]


--[[ TERMINAL SNAPSHOT: launch_json_configurations_loaded
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3| ● console.log("ALoop iteration: ", i++);
 4|  console.log("BLoop iteration: ", i++);
 5|  console.log("CLoop iteration: ", i++);
 6|  console.log("DLoop iteration: ", i++);
 7| }, 1000)
 8| ~
 9| ~
10| ~
11| ~
12| ~
13| ~
14| ~
15| ~
16| ~
17| ~
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,1-2          All
24| ✓ Terminal snapshot 'breakpoint_set_in_launch_json_project' matches
]]

--[[ TERMINAL SNAPSHOT: breakpoint_hit_from_session
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3| ● ◐console.log("ALoop iteration: ", i++);
 4|  console.log("BLoop iteration: ", i++);
 5|  console.log("CLoop iteration: ", i++);
 6|  console.log("DLoop iteration: ", i++);
 7| }, 1000)
 8| ~
 9| ~
10| ~
11| ~
12| ~
13| ~
14| ~
15| ~
16| ~
17| ~
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,1-2          All
24| 
]]

--[[ TERMINAL SNAPSHOT: launch_json_workflow_completed
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3| ● ◆console.log("ALoop iteration: ", i++);
 4|  console.log("BLoop iteration: ", i++);
 5|  console.log("CLoop iteration: ", i++);
 6|  console.log("DLoop iteration: ", i++);
 7| }, 1000)
 8| ~
 9| ~
10| ~
11| ~
12| ~
13| ~
14| ~
15| ~
16| ~
17| ~
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,1-2          All
24| 
]]