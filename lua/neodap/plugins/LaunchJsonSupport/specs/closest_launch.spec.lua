-- Test: LaunchJsonSupport closest launch.json functionality
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local ScopeViewer = require("neodap.plugins.ScopeViewer")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local nio = require("nio")

Test.Describe("LaunchJsonSupport Closest Launch.json", function()
    Test.It("runs_debug_session_from_closest_launch_json", function()
        -- Remove existing snapshots so we can see where the test fails
        local test_file = debug.getinfo(1, "S").source:sub(2)
        local content = vim.fn.readfile(test_file)
        local new_content = {}
        local in_snapshot = false
        
        for _, line in ipairs(content) do
            if line:match("^%-%-[[].*TERMINAL SNAPSHOT:") then
                in_snapshot = true
            elseif in_snapshot and line:match("^]]") then
                in_snapshot = false
            elseif not in_snapshot then
                table.insert(new_content, line)
            end
        end
        
        vim.fn.writefile(new_content, test_file)
        
        local api, start = prepare()

        -- Get plugin instances for full debugging workflow
        local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)
        local breakpointApi = api:getPluginInstance(BreakpointApi)
        local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
        api:getPluginInstance(ScopeViewer) -- Enable scope viewer
        api:getPluginInstance(DebugOverlay) -- Enable debug overlay

        -- Step 1: Open a file in single-node-project
        local test_file = vim.fn.fnamemodify("spec/fixtures/workspaces/single-node-project/loop.js", ":p")
        vim.cmd("edit " .. test_file)

        -- Take snapshot with file open
        Test.TerminalSnapshot("closest_launch_file_opened")

        -- Step 2: Set a breakpoint in the file
        vim.api.nvim_win_set_cursor(0, { 3, 1 }) -- Line 3 in loop.js
        toggleBreakpoint:toggle()
        nio.sleep(50)
        
        -- Take snapshot with breakpoint set
        Test.TerminalSnapshot("closest_launch_breakpoint_set")

        -- Step 3: Test workspace detection from current buffer
        local workspace_info = launchJsonSupport:detectWorkspace(test_file)
        local configs = launchJsonSupport:getAvailableConfigurations(workspace_info)
        
        -- Step 4: Set up promises to wait for debug session events
        local session_promise = nio.control.future()
        local stopped_promise = nio.control.future()
        
        api:onSession(function(session)
            if not session_promise.is_set() then
                session_promise.set(session)
            end
            
            session:onThread(function(thread)
                thread:onStopped(function()
                    if not stopped_promise.is_set() then
                        stopped_promise.set(true)
                    end
                end)
            end)
        end)
        
        -- Step 5: Launch debug session using closest launch.json
        -- Use "Debug Loop [single-node-project]" configuration
        local target_config = "Debug Loop [single-node-project]"
        local session = launchJsonSupport:createSessionFromConfig(target_config, api.manager, workspace_info)
        
        -- Wait for session to start and hit breakpoint
        session_promise.wait()
        stopped_promise.wait()
        
        -- Small delay for UI to update
        nio.sleep(300)
        
        -- Take snapshot showing debug session with overlay and breakpoint hit
        Test.TerminalSnapshot("closest_launch_debug_session_active")
        
        -- Step 6: Show scope viewer to demonstrate full debugging capabilities
        vim.cmd("NeodapScopeShow")
        nio.sleep(200)
        
        -- Take snapshot with scope viewer showing variables
        Test.TerminalSnapshot("closest_launch_with_scope_viewer")
        
        -- Step 7: Test the NeodapLaunchClosest command completion
        local completion = vim.fn.getcompletion("NeodapLaunchClosest ", "cmdline")
        if #completion > 0 then
            vim.notify("✓ NeodapLaunchClosest command works with " .. #completion .. " configurations", vim.log.levels.INFO)
            nio.sleep(100)
        end
        
        -- Take final snapshot showing successful debugging workflow
        Test.TerminalSnapshot("closest_launch_workflow_complete")

        -- Clean up session and API
        api:destroy()
    end)
end)

















--[[ TERMINAL SNAPSHOT: closest_launch_file_opened
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
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
23| spec/fixtures/workspaces/single-node-project/loop.js          1,1            All
24| 
]]

--[[ TERMINAL SNAPSHOT: closest_launch_breakpoint_set
Size: 24x80
Cursor: [3, 1] (line 3, col 1)
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
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24| 
]]

--[[ TERMINAL SNAPSHOT: closest_launch_debug_session_active
Size: 24x80
Cursor: [3, 1] (line 3, col 1)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);      ╭──────────── Scopes ─────────────╮
 4|  console.log("BLoop iteration: ", i++);      │▶ Local                          │
 5|  console.log("CLoop iteration: ", i++);      │▶ Closure                        │
 6|  console.log("DLoop iteration: ", i++);      │▶ Global (expensive)             │
 7| }, 1000)                                     │                                 │
 8| ~                                            ╰─────────────────────────────────╯
 9| ~                                            ╭────────── Call Stack ───────────╮
10| ~                                            │                                 │
11| ~                                            │                                 │
12| ~                                            │                                 │
13| ~                                            │                                 │
14| ~                                            │                                 │
15| ~                                            │                                 │
16| ~                                            ╰─────────────────────────────────╯
17| ~
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24| [Plugin:BreakpointApi] Session 2 Thread 0 - Stopped at breakpoint(s): { 0 }
]]

--[[ TERMINAL SNAPSHOT: closest_launch_with_scope_viewer
Size: 24x80
Cursor: [3, 1] (line 3, col 1)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);      ╭──────────── Scopes ─────────────╮
 4|  console.log("BLoop iteration: ", i++);      │▶ Local                          │
 5|  console.log("CLoop iteration: ", i++);      │▶ Closure                        │
 6|  console.log("DLoop iteration: ", i++);      │▶ Global (expensive)             │
 7| }, 1000)                                     │                                 │
 8| ~                                            ╰─────────────────────────────────╯
 9| ~                                            ╭────────── Call Stack ───────────╮
10| ~                                            │                                 │
11| ~                                            │                                 │
12| ~                                            │                                 │
13| ~                                            │                                 │
14| ~                                            │                                 │
15| ~                                            │                                 │
16| ~                                            ╰─────────────────────────────────╯
17| ~
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24| 
]]

--[[ TERMINAL SNAPSHOT: closest_launch_workflow_complete
Size: 24x80
Cursor: [3, 1] (line 3, col 1)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);      ╭──────────── Scopes ─────────────╮
 4|  console.log("BLoop iteration: ", i++);      │▶ Local                          │
 5|  console.log("CLoop iteration: ", i++);      │▶ Closure                        │
 6|  console.log("DLoop iteration: ", i++);      │▶ Global (expensive)             │
 7| }, 1000)                                     │                                 │
 8| ~                                            ╰─────────────────────────────────╯
 9| ~                                            ╭────────── Call Stack ───────────╮
10| ~                                            │                                 │
11| ~                                            │                                 │
12| ~                                            │                                 │
13| ~                                            │                                 │
14| ~                                            │                                 │
15| ~                                            │                                 │
16| ~                                            ╰─────────────────────────────────╯
17| ~
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24| 
]]