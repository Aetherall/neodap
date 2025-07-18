local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local BreakpointVirtualText = require("neodap.plugins.BreakpointVirtualText")
local FrameHighlight = require("neodap.plugins.FrameHighlight")
local JumpToStoppedFrame = require("neodap.plugins.JumpToStoppedFrame")
local nio = require("nio")

Test.Describe("LaunchJsonSupport Step Over", function()

  Test.It("launch_json_step_over_workflow", function()
    local api = prepare()
    
    -- Load plugins
    local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)
    api:getPluginInstance(BreakpointApi)
    local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
    api:getPluginInstance(BreakpointVirtualText)
    api:getPluginInstance(FrameHighlight)
    api:getPluginInstance(JumpToStoppedFrame)
    
    -- Open loop.js from fixture
    local fixture_path = vim.fn.fnamemodify("spec/fixtures/workspaces/single-node-project", ":p")
    vim.cmd("edit " .. fixture_path .. "/loop.js")
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    
    -- Set breakpoint on first repeating line
    toggleBreakpoint:toggle()
    nio.sleep(20)
    
    -- Visual confirmation: breakpoint set for stepping
    Test.TerminalSnapshot("step_over_breakpoint_set")
    
    -- Track execution states
    local breakpoint_hit = false
    local stepped_over = false
    
    -- Register session listener (only for session 2 to avoid breakpoint flooding)
    api:onSession(function(session)
      if session.ref.id == 1 then return end -- Skip session 1 to avoid interference
      session:onInitialized(function() end, { once = true })
      session:onThread(function(thread)
        thread:onStopped(function(event)
          if event.reason == "breakpoint" and not breakpoint_hit then
            breakpoint_hit = true
            -- Visual confirmation: execution stopped at breakpoint
            Test.TerminalSnapshot("step_over_breakpoint_hit")
            
            -- Step over to next line
            thread:stepOver()
            
          elseif event.reason == "step" then
            stepped_over = true
            -- Check the current execution position after step
            local stack = thread:stack()
            if stack then
              local top_frame = stack:top()
              if top_frame then
                print("STEP COMPLETED - Current execution at line:", top_frame.ref.line)
              else
                print("STEP COMPLETED - No top frame available")
              end
            else
              print("STEP COMPLETED - No stack available")
            end
            -- Small delay to allow frame highlighting to complete
            nio.sleep(200)
            -- Visual confirmation: stepped over to next line
            Test.TerminalSnapshot("step_over_completed")
          end
        end)
      end)
    end)
    
    -- Create session from launch.json
    local workspace_info = launchJsonSupport:detectWorkspace(fixture_path)
    launchJsonSupport:createSessionFromConfig("Debug Loop []", api.manager, workspace_info)
    
    -- Wait for breakpoint hit then step over
    vim.wait(5000, function() return breakpoint_hit end)
    vim.wait(3000, function() return stepped_over end)

    nio.sleep(1000) -- Allow time for step over to complete
    
    -- Visual confirmation: step over workflow completed
    Test.TerminalSnapshot("step_over_workflow_completed")
  end)

end)

--[[ TERMINAL SNAPSHOT: step_over_breakpoint_set
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
24| 
]]

--[[ TERMINAL SNAPSHOT: step_over_breakpoint_hit
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

--[[ TERMINAL SNAPSHOT: step_over_completed
Size: 24x80
Cursor: [4, 1] (line 4, col 1)
Mode: n

Highlights:
  NeodapOtherFrameHighlight[2:1-2:20]
  NeodapTopFrameHighlight[4:2-4:40]

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
23| spec/fixtures/workspaces/single-node-project/loop.js          4,2            All
24| 
]]

--[[ TERMINAL SNAPSHOT: step_over_workflow_completed
Size: 24x80
Cursor: [4, 1] (line 4, col 1)
Mode: n

Highlights:
  NeodapOtherFrameHighlight[2:1-2:20]
  NeodapTopFrameHighlight[4:2-4:40]

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
23| spec/fixtures/workspaces/single-node-project/loop.js          4,2            All
24| 
]]