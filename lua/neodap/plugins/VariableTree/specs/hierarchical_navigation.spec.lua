-- Test: VariableTree hierarchical variable navigation with Neo-tree integration
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local VariableTree = require("neodap.plugins.VariableTree")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("VariableTree Hierarchical Navigation", function()
    Test.It("demonstrates_global_scope_hierarchical_expansion", function()
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

        -- Take snapshot with breakpoint set
        Test.TerminalSnapshot("hierarchical_nav_breakpoint_set")

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
        
        -- Take snapshot when stopped at breakpoint
        Test.TerminalSnapshot("hierarchical_nav_stopped_at_breakpoint")

        -- Show VariableTree floating window
        vim.cmd("NeodapVariableTreeShow")
        nio.sleep(300)
        
        -- Take snapshot showing initial state
        Test.TerminalSnapshot("hierarchical_nav_initial_state")
        
        -- Navigate to Global scope and expand it (contains complex objects)
        vim.cmd("normal! gg") -- Go to Local scope
        vim.cmd("normal! j") -- Go to Local variable
        vim.cmd("normal! j") -- Go to Closure scope
        vim.cmd("normal! j") -- Go to Closure variable
        vim.cmd("normal! j") -- Go to Global scope
        nio.sleep(100)
        
        -- Take snapshot showing cursor on Global scope
        Test.TerminalSnapshot("hierarchical_nav_global_scope_cursor")
        
        -- Expand Global scope to reveal complex global objects
        variableTree:ToggleScopeAtCursor()
        nio.sleep(500) -- Give time for expensive Global scope to load
        
        -- Take snapshot showing Global scope expanded with complex objects
        Test.TerminalSnapshot("hierarchical_nav_global_expanded")
        
        -- Navigate to a complex global object (like AbortController)
        vim.cmd("normal! j") -- Move to first global variable
        nio.sleep(100)
        
        -- Take snapshot showing cursor on complex global object
        Test.TerminalSnapshot("hierarchical_nav_complex_object_cursor")
        
        -- Try to expand the complex object if it has children
        variableTree:ToggleScopeAtCursor()
        nio.sleep(500)
        
        -- Take snapshot showing object properties expanded
        Test.TerminalSnapshot("hierarchical_nav_object_properties_expanded")
        
        -- Test navigation through expanded properties
        vim.cmd("normal! j") -- Move to first property
        vim.cmd("normal! j") -- Move to second property
        nio.sleep(100)
        
        -- Take snapshot showing navigation through object properties
        Test.TerminalSnapshot("hierarchical_nav_property_navigation")
        
        -- Test collapsing the object back
        vim.cmd("normal! k") -- Move back to parent object
        vim.cmd("normal! k") -- Move back to parent object
        variableTree:ToggleScopeAtCursor() -- Collapse the object
        nio.sleep(300)
        
        -- Take snapshot showing object collapsed
        Test.TerminalSnapshot("hierarchical_nav_object_collapsed")
        
        -- Close the variable tree window
        vim.cmd("NeodapVariableTreeHide")
        nio.sleep(200)
        
        -- Take snapshot showing variable tree hidden
        Test.TerminalSnapshot("hierarchical_nav_window_closed")
        
        -- Clean up
        api:destroy()
    end)
end)

--[[ TERMINAL SNAPSHOT: hierarchical_nav_breakpoint_set
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

--[[ TERMINAL SNAPSHOT: hierarchical_nav_stopped_at_breakpoint
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


--[[ TERMINAL SNAPSHOT: hierarchical_nav_initial_state
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


--[[ TERMINAL SNAPSHOT: hierarchical_nav_global_scope_cursor
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

--[[ TERMINAL SNAPSHOT: hierarchical_nav_global_expanded
Size: 24x80
Cursor: [5, 0] (line 5, col 0)
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
10| ~                       │▼ Local                         │
11| ~                       │    this = undefined : undefined│
12| ~                       │▼ Closure                       │
13| ~                       │    i = 0 : number              │
14| ~                       │▼ Global                        │
15| ~                       │  ▶ AbortController = ƒ () {\n  │
16| ~                       │    mod ??= require(id);\n   @@@│
17| ~                       ╰────────────────────────────────╯
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               5,1           Top
]]

--[[ TERMINAL SNAPSHOT: hierarchical_nav_complex_object_cursor
Size: 24x80
Cursor: [6, 0] (line 6, col 0)
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
10| ~                       │    this = undefined : undefined│
11| ~                       │▼ Closure                       │
12| ~                       │    i = 0 : number              │
13| ~                       │▼ Global                        │
14| ~                       │  ▶ AbortController = ƒ () {\n  │
15| ~                       │    mod ??= require(id);\n   ...│
16| ~                       │ : function                     │
17| ~                       ╰────────────────────────────────╯
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               6,1            0%
]]


--[[ TERMINAL SNAPSHOT: hierarchical_nav_object_properties_expanded
Size: 24x80
Cursor: [6, 0] (line 6, col 0)
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
10| ~                       │    this = undefined : undefined│
11| ~                       │▼ Closure                       │
12| ~                       │    i = 0 : number              │
13| ~                       │▼ Global                        │
14| ~                       │  ▼ AbortController = ƒ () {\n  │
15| ~                       │    mod ??= require(id);\n   ...│
16| ~                       │ : function                     │
17| ~                       ╰────────────────────────────────╯
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               6,1            0%
]]

--[[ TERMINAL SNAPSHOT: hierarchical_nav_property_navigation
Size: 24x80
Cursor: [8, 0] (line 8, col 0)
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
11| ~                       │  ▶ AbortController = ƒ () {\n  │
12| ~                       │    mod ??= require(id);\n   ...│
13| ~                       │ : function                     │
14| ~                       │  ▶ AbortSignal = ƒ () {\n      │
15| ~                       │mod ??= require(id);\n   ... : f│
16| ~                       │unction                         │
17| ~                       ╰────────────────────────────────╯
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               8,1            3%
]]

--[[ TERMINAL SNAPSHOT: hierarchical_nav_object_collapsed
Size: 24x80
Cursor: [6, 0] (line 6, col 0)
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
11| ~                       │  ▶ AbortController = ƒ () {\n  │
12| ~                       │    mod ??= require(id);\n   ...│
13| ~                       │ : function                     │
14| ~                       │  ▶ AbortSignal = ƒ () {\n      │
15| ~                       │mod ??= require(id);\n   ... : f│
16| ~                       │unction                         │
17| ~                       ╰────────────────────────────────╯
18| ~
19| ~
20| ~
21| ~
22| ~
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               6,1            3%
]]

--[[ TERMINAL SNAPSHOT: hierarchical_nav_window_closed
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