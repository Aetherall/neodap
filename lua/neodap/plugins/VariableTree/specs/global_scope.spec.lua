-- Test: VariableTree global scope expansion functionality
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local VariableTree = require("neodap.plugins.VariableTree")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("VariableTree Global Scope", function()
    Test.It("demonstrates_expensive_global_scope_manual_expansion", function()
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
        local variableTree = api:getPluginInstance(VariableTree) -- Enable VariableTree and its commands
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
        Test.TerminalSnapshot("global_scope_breakpoint_set")

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
        
        -- Take snapshot when stopped at breakpoint
        Test.TerminalSnapshot("global_scope_stopped_at_breakpoint")

        -- Show VariableTree floating window
        vim.cmd("NeodapVariableTreeShow")
        nio.sleep(300) -- Give time for the window to render
        
        -- Take snapshot showing initial state with auto-expanded Local and Closure scopes but collapsed Global scope
        Test.TerminalSnapshot("global_scope_initial_state")
        
        -- Verify that Global scope is collapsed by default (expensive scope)
        -- Navigate to Global scope line (should be line 3: after Local and Closure)
        vim.cmd("normal! gg") -- Go to first line (Local scope)
        vim.cmd("normal! j") -- Move to Local variable
        vim.cmd("normal! j") -- Move to Closure scope  
        vim.cmd("normal! j") -- Move to Closure variable
        vim.cmd("normal! j") -- Move to Global scope
        nio.sleep(100)
        
        -- Take snapshot showing cursor positioned on Global scope (should show ▶ Global)
        Test.TerminalSnapshot("global_scope_cursor_positioned")
        
        -- Test manual expansion of Global scope (should work despite being expensive)
        variableTree:ToggleScopeAtCursor() -- Call toggle function directly to expand Global
        nio.sleep(500) -- Give time for the expensive operation to complete
        
        -- Take snapshot showing Global scope manually expanded with many global variables
        Test.TerminalSnapshot("global_scope_manually_expanded")
        
        -- Navigate down to see more global variables
        vim.cmd("normal! j") -- Move to first global variable
        vim.cmd("normal! j") -- Move to second global variable
        nio.sleep(100)
        
        -- Take snapshot showing navigation through global variables
        Test.TerminalSnapshot("global_scope_variables_navigation")
        
        -- Test manual collapse of Global scope
        vim.cmd("normal! k") -- Move back up to Global scope header
        vim.cmd("normal! k") -- Move back up to Global scope header
        nio.sleep(100)
        variableTree:ToggleScopeAtCursor() -- Call toggle function directly to collapse Global
        nio.sleep(300)
        
        -- Take snapshot showing Global scope collapsed again (should show ▶ Global)
        Test.TerminalSnapshot("global_scope_manually_collapsed")
        
        -- Test that Global scope can be re-expanded immediately (no restrictions)
        variableTree:ToggleScopeAtCursor() -- Call toggle function directly to expand Global again
        nio.sleep(500) -- Give time for the expensive operation to complete again
        
        -- Take snapshot showing Global scope re-expanded successfully
        Test.TerminalSnapshot("global_scope_re_expanded")
        
        -- Test multiple rapid toggles to ensure expensive scope handling is robust
        variableTree:ToggleScopeAtCursor() -- Collapse
        nio.sleep(200)
        variableTree:ToggleScopeAtCursor() -- Expand
        nio.sleep(300)
        variableTree:ToggleScopeAtCursor() -- Collapse
        nio.sleep(200)
        
        -- Take snapshot showing final state after rapid toggles
        Test.TerminalSnapshot("global_scope_rapid_toggles_final")
        
        -- Test that other scopes still work normally while Global is collapsed
        vim.cmd("normal! gg") -- Go to Local scope
        nio.sleep(100)
        variableTree:ToggleScopeAtCursor() -- Collapse Local scope
        nio.sleep(300)
        
        -- Take snapshot showing Local collapsed, Closure expanded, Global collapsed
        Test.TerminalSnapshot("global_scope_other_scopes_still_work")
        
        -- Close the variable tree window
        vim.cmd("NeodapVariableTreeHide")
        nio.sleep(200)
        
        -- Take snapshot showing variable tree hidden
        Test.TerminalSnapshot("global_scope_window_closed")
        
        -- Clean up
        api:destroy()
    end)
end)
























--[[ TERMINAL SNAPSHOT: global_scope_breakpoint_set
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

--[[ TERMINAL SNAPSHOT: global_scope_stopped_at_breakpoint
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

--[[ TERMINAL SNAPSHOT: global_scope_initial_state
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);
 4|  console.log("BLoop iteration: ", i++);
 5|  console.log("CLoop iteration: ", i++);
 6|  console.log("DLoop╭──────────── Variable Tree ─────────────╮
 7| }, 1000)           │▼ Local                                 │
 8| ~                  │    this = undefined : undefined        │
 9| ~                  │▼ Closure                               │
10| ~                  │    i = 0 : number                      │
11| ~                  │▶ Global                                │
12| ~                  │                                        │
13| ~                  │                                        │
14| ~                  │                                        │
15| ~                  │                                        │
16| ~                  │                                        │
17| ~                  ╰────────────────────────────────────────╯
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               1,1           All
]]

--[[ TERMINAL SNAPSHOT: global_scope_cursor_positioned
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);
 4|  console.log("BLoop iteration: ", i++);
 5|  console.log("CLoop iteration: ", i++);
 6|  console.log("DLoop╭──────────── Variable Tree ─────────────╮
 7| }, 1000)           │▼ Local                                 │
 8| ~                  │    this = undefined : undefined        │
 9| ~                  │▼ Closure                               │
10| ~                  │    i = 0 : number                      │
11| ~                  │▶ Global                                │
12| ~                  │                                        │
13| ~                  │                                        │
14| ~                  │                                        │
15| ~                  │                                        │
16| ~                  │                                        │
17| ~                  ╰────────────────────────────────────────╯
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               5,1           All
]]

--[[ TERMINAL SNAPSHOT: global_scope_manually_expanded
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);
 4|  console.log("BLoop iteration: ", i++);
 5|  console.log("CLoop iteration: ", i++);
 6|  console.log("DLoop╭──────────── Variable Tree ─────────────╮
 7| }, 1000)           │▼ Local                                 │
 8| ~                  │    this = undefined : undefined        │
 9| ~                  │▼ Closure                               │
10| ~                  │    i = 0 : number                      │
11| ~                  │▶ Global                                │
12| ~                  │                                        │
13| ~                  │                                        │
14| ~                  │                                        │
15| ~                  │                                        │
16| ~                  │                                        │
17| ~                  ╰────────────────────────────────────────╯
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               5,1           All
]]

--[[ TERMINAL SNAPSHOT: global_scope_variables_navigation
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);
 4|  console.log("BLoop iteration: ", i++);
 5|  console.log("CLoop iteration: ", i++);
 6|  console.log("DLoop╭──────────── Variable Tree ─────────────╮
 7| }, 1000)           │▼ Local                                 │
 8| ~                  │    this = undefined : undefined        │
 9| ~                  │▼ Closure                               │
10| ~                  │    i = 0 : number                      │
11| ~                  │▶ Global                                │
12| ~                  │                                        │
13| ~                  │                                        │
14| ~                  │                                        │
15| ~                  │                                        │
16| ~                  │                                        │
17| ~                  ╰────────────────────────────────────────╯
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               5,1           All
]]

--[[ TERMINAL SNAPSHOT: global_scope_manually_collapsed
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);
 4|  console.log("BLoop iteration: ", i++);
 5|  console.log("CLoop iteration: ", i++);
 6|  console.log("DLoop╭──────────── Variable Tree ─────────────╮
 7| }, 1000)           │▼ Local                                 │
 8| ~                  │    this = undefined : undefined        │
 9| ~                  │▼ Closure                               │
10| ~                  │    i = 0 : number                      │
11| ~                  │▶ Global                                │
12| ~                  │                                        │
13| ~                  │                                        │
14| ~                  │                                        │
15| ~                  │                                        │
16| ~                  │                                        │
17| ~                  ╰────────────────────────────────────────╯
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               3,1           All
]]

--[[ TERMINAL SNAPSHOT: global_scope_re_expanded
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);
 4|  console.log("BLoop iteration: ", i++);
 5|  console.log("CLoop iteration: ", i++);
 6|  console.log("DLoop╭──────────── Variable Tree ─────────────╮
 7| }, 1000)           │▼ Local                                 │
 8| ~                  │    this = undefined : undefined        │
 9| ~                  │▼ Closure                               │
10| ~                  │    i = 0 : number                      │
11| ~                  │▶ Global                                │
12| ~                  │                                        │
13| ~                  │                                        │
14| ~                  │                                        │
15| ~                  │                                        │
16| ~                  │                                        │
17| ~                  ╰────────────────────────────────────────╯
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               3,1           All
]]

--[[ TERMINAL SNAPSHOT: global_scope_rapid_toggles_final
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);
 4|  console.log("BLoop iteration: ", i++);
 5|  console.log("CLoop iteration: ", i++);
 6|  console.log("DLoop╭──────────── Variable Tree ─────────────╮
 7| }, 1000)           │▼ Local                                 │
 8| ~                  │    this = undefined : undefined        │
 9| ~                  │▼ Closure                               │
10| ~                  │    i = 0 : number                      │
11| ~                  │▶ Global                                │
12| ~                  │                                        │
13| ~                  │                                        │
14| ~                  │                                        │
15| ~                  │                                        │
16| ~                  │                                        │
17| ~                  ╰────────────────────────────────────────╯
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               3,1           All
]]