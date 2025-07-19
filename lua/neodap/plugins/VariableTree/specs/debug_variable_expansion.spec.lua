-- Test: VariableTree variable expansion debugging
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local VariableTree = require("neodap.plugins.VariableTree")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("VariableTree Debug Variable Expansion", function()
    Test.It("debug_variable_expansion_with_logs", function()
        local api, start = prepare()

        -- Get plugin instances
        local breakpointApi = api:getPluginInstance(BreakpointApi)
        local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
        local variableTree = api:getPluginInstance(VariableTree)
        api:getPluginInstance(DebugOverlay)
        local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)

        -- Open the loop.js file that we know works
        vim.cmd("edit spec/fixtures/workspaces/single-node-project/loop.js")

        -- Move cursor to line 3 (inside the setInterval callback)
        vim.api.nvim_win_set_cursor(0, { 3, 1 })

        -- Set breakpoint at line 3
        toggleBreakpoint:toggle()
        nio.sleep(50)

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
        local current_file = vim.api.nvim_buf_get_name(0)
        local workspace_info = launchJsonSupport:detectWorkspace(current_file)
        local session = launchJsonSupport:createSessionFromConfig("Debug Loop [single-node-project]", api.manager, workspace_info)
        
        -- Wait for session to start and hit breakpoint
        session_promise.wait()
        stopped_promise.wait()
        scopes_ready.wait()

        -- Show VariableTree floating window
        vim.cmd("NeodapVariableTreeShow")
        nio.sleep(300)
        
        -- Take snapshot showing initial state
        Test.TerminalSnapshot("debug_initial_state")
        
        -- Navigate to Global scope and expand it
        vim.cmd("normal! gg") -- Go to Local scope
        vim.cmd("normal! j") -- Go to Local variable
        vim.cmd("normal! j") -- Go to Closure scope
        vim.cmd("normal! j") -- Go to Closure variable
        vim.cmd("normal! j") -- Go to Global scope
        nio.sleep(100)
        
        -- Expand Global scope to reveal complex global objects
        variableTree:ToggleScopeAtCursor()
        nio.sleep(500) -- Give time for expensive Global scope to load
        
        -- Take snapshot showing Global scope expanded with complex objects
        Test.TerminalSnapshot("debug_global_expanded")
        
        -- Navigate to the first complex global object 
        vim.cmd("normal! j") -- Move to first global variable
        nio.sleep(100)
        
        -- Take snapshot showing cursor on complex global object
        Test.TerminalSnapshot("debug_cursor_on_variable")
        
        -- Ensure we're focused on the floating window
        if variableTree.floating_window and vim.api.nvim_win_is_valid(variableTree.floating_window) then
            vim.api.nvim_set_current_win(variableTree.floating_window)
        end
        nio.sleep(100)
        
        -- Now try to expand the variable - this should trigger our debug logs  
        -- Call the function directly instead of relying on keymap
        variableTree:ToggleScopeAtCursor()
        nio.sleep(500)
        
        -- Take snapshot to see if variable expanded
        Test.TerminalSnapshot("debug_variable_toggle_attempt")
        
        -- Try a few more times to see pattern
        vim.cmd("normal! j") -- Move to next variable
        nio.sleep(100)
        variableTree:ToggleScopeAtCursor() -- Call directly again
        nio.sleep(500)
        
        Test.TerminalSnapshot("debug_second_variable_toggle")
        
        -- Clean up
        api:destroy()
    end)
end)


--[[ TERMINAL SNAPSHOT: debug_initial_state
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


--[[ TERMINAL SNAPSHOT: debug_global_expanded
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


--[[ TERMINAL SNAPSHOT: debug_cursor_on_variable
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



--[[ TERMINAL SNAPSHOT: debug_variable_toggle_attempt
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


--[[ TERMINAL SNAPSHOT: debug_second_variable_toggle
Size: 24x80
Cursor: [7, 0] (line 7, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {
 3|  console.log("ALoop iteration: ", i++);
 4|  console.log("BLoop iteration: ", i++);
 5|  console.log("CLoop iteration: ", i++);
 6|  console.log("DLoop iteration: ", i++);
 7| }, 1000)
 8| ~
 9| ~                       ╭──────── Variable Tree ─────────╮
10| ~                       │▼ Global                        │
11| ~                       │  ▶ AbortSignal = ƒ () {\n      │
12| ~                       │mod ??= require(id);\n   ... : f│
13| ~                       │unction                         │
14| ~                       │  ▶ atob = ƒ () {\n      mod ??=│
15| ~                       │ require(id);\n   ... : function│
16| ~                       │  ▶ Blob = ƒ () {\n      mod @@@│
17| ~                       ╰────────────────────────────────╯
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               7,1            3%
]]