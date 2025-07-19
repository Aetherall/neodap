-- Test: ScopeViewer plugin functionality demonstration
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local ScopeViewer = require("neodap.plugins.ScopeViewer")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("ScopeViewer Plugin", function()
    Test.It("shows_scope_popup_with_variables", function()
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

        -- Get plugin instances
        local breakpointApi = api:getPluginInstance(BreakpointApi)
        local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
        api:getPluginInstance(ScopeViewer) -- Enable ScopeViewer and its commands
        api:getPluginInstance(DebugOverlay) -- Enable DebugOverlay
        local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport) -- Enable LaunchJsonSupport for closest launch.json

        -- Open the loop.js file from single-node-project (has variables we can inspect)
        vim.cmd("edit spec/fixtures/workspaces/single-node-project/loop.js")

        -- Move cursor to line 3 (inside the loop where variables exist)
        vim.api.nvim_win_set_cursor(0, { 3, 1 })

        -- Set breakpoint at line 3
        toggleBreakpoint:toggle()
        nio.sleep(50)

        -- Take snapshot with breakpoint set
        Test.TerminalSnapshot("scope_viewer_breakpoint_set")

        -- Set up promises to wait for session events
        local session_promise = nio.control.future()
        local stopped_promise = nio.control.future()
        local scopes_ready = nio.control.future()
        
        api:onSession(function(session)
            if not session_promise.is_set() then
                session_promise.set(session)
            end
            
            session:onThread(function(thread)
                thread:onStopped(function()
                    if not stopped_promise.is_set() then
                        -- Give time for stack and scopes to be available
                        nio.sleep(100)
                        local stack = thread:stack()
                        if stack then
                            local frame = stack:top()
                            if frame then
                                local scopes = frame:scopes()
                                if scopes and #scopes > 0 and not scopes_ready.is_set() then
                                    scopes_ready.set(true)
                                end
                            end
                        end
                        stopped_promise.set(true)
                    end
                end)
            end)
        end)
        
        -- Use LaunchJsonSupport to start debugging with closest launch.json!
        -- This automatically finds the closest launch.json from current buffer
        local current_file = vim.api.nvim_buf_get_name(0)
        local workspace_info = launchJsonSupport:detectWorkspace(current_file)
        local session = launchJsonSupport:createSessionFromConfig("Debug Loop [single-node-project]", api.manager, workspace_info)
        
        -- Wait for session to start and hit breakpoint
        session_promise.wait()
        stopped_promise.wait()
        scopes_ready.wait()
        
        -- Take snapshot when stopped at breakpoint with overlay open automatically
        Test.TerminalSnapshot("scope_viewer_stopped_with_overlay")

        -- Use vim command to show the scope viewer (should be idempotent when already open)
        vim.cmd("NeodapScopeShow")
        nio.sleep(200)

        -- Take snapshot showing the scope viewer popup with variables
        Test.TerminalSnapshot("scope_viewer_popup_with_variables")

        -- Use vim command to hide the scope viewer
        vim.cmd("NeodapScopeHide")
        nio.sleep(200)
        
        -- Take snapshot with scope viewer hidden
        Test.TerminalSnapshot("scope_viewer_hidden")
        
        -- Use vim command to toggle the scope viewer back on
        vim.cmd("NeodapScopeToggle")
        nio.sleep(200)
        
        -- Take snapshot with scope viewer toggled back on
        Test.TerminalSnapshot("scope_viewer_toggled_on")
        
        -- Toggle it off again
        vim.cmd("NeodapScopeToggle")
        nio.sleep(200)
        
        -- Take final snapshot with scope viewer toggled off
        Test.TerminalSnapshot("scope_viewer_toggled_off")

        -- Clean up
        api:destroy()
    end)
end)





















































































































































































































--[[ TERMINAL SNAPSHOT: scope_viewer_breakpoint_set
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

--[[ TERMINAL SNAPSHOT: scope_viewer_stopped_with_overlay
Size: 24x80
Cursor: [3, 1] (line 3, col 1)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);      ╭──────────── Scopes ─────────────╮
 4|  console.log("BLoop iteration: ", i++);      │                                 │
 5|  console.log("CLoop iteration: ", i++);      │                                 │
 6|  console.log("DLoop iteration: ", i++);      │                                 │
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
24| [Plugin:BreakpointApi] Session 2 Thread 0 - Stopped at breakpo1,1           All
]]

--[[ TERMINAL SNAPSHOT: scope_viewer_popup_with_variables
Size: 24x80
Cursor: [3, 1] (line 3, col 1)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);      ╭──────────── Scopes ─────────────╮
 4|  console.log("BLoop iteration: ", i++);      │▼ Local                          │
 5|  console.log("CLoop iteration: ", i++);      │  this = undefined : undefined   │
 6|  console.log("DLoop iteration: ", i++);      │▼ Closure                        │
 7| }, 1000)                                     │  i = 0 : number                 │
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

--[[ TERMINAL SNAPSHOT: scope_viewer_hidden
Size: 24x80
Cursor: [3, 1] (line 3, col 1)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);      ╭──────────── Scopes ─────────────╮
 4|  console.log("BLoop iteration: ", i++);      │                                 │
 5|  console.log("CLoop iteration: ", i++);      │                                 │
 6|  console.log("DLoop iteration: ", i++);      │                                 │
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

--[[ TERMINAL SNAPSHOT: scope_viewer_toggled_on
Size: 24x80
Cursor: [3, 1] (line 3, col 1)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);      ╭──────────── Scopes ─────────────╮
 4|  console.log("BLoop iteration: ", i++);      │▼ Local                          │
 5|  console.log("CLoop iteration: ", i++);      │  this = undefined : undefined   │
 6|  console.log("DLoop iteration: ", i++);      │▼ Closure                        │
 7| }, 1000)                                     │  i = 0 : number                 │
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

--[[ TERMINAL SNAPSHOT: scope_viewer_toggled_off
Size: 24x80
Cursor: [3, 1] (line 3, col 1)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);      ╭──────────── Scopes ─────────────╮
 4|  console.log("BLoop iteration: ", i++);      │                                 │
 5|  console.log("CLoop iteration: ", i++);      │                                 │
 6|  console.log("DLoop iteration: ", i++);      │                                 │
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