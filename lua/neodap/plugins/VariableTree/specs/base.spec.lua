-- Test: VariableTree plugin functionality demonstration
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local VariableTree = require("neodap.plugins.VariableTree")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("VariableTree Plugin", function()
    Test.It("shows_variable_tree_with_modern_design", function()
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
        Test.TerminalSnapshot("variable_tree_breakpoint_set")

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
        Test.TerminalSnapshot("variable_tree_stopped_at_breakpoint")

        -- Test VariableTree status command
        vim.cmd("NeodapVariableTreeStatus")
        nio.sleep(100)
        
        -- Take snapshot showing status message
        Test.TerminalSnapshot("variable_tree_status_shown")
        
        -- Show VariableTree floating window
        vim.cmd("NeodapVariableTreeShow")
        nio.sleep(300) -- Give time for the complex dual-pane window to render
        
        -- Take snapshot showing the variable tree floating window with dual panes
        Test.TerminalSnapshot("variable_tree_floating_window_shown")
        
        -- Test navigation - simulate cursor movement to select different variables
        -- The window should be focused, so we can move cursor
        vim.cmd("normal! j") -- Move down to select a variable
        nio.sleep(100)
        
        -- Take snapshot showing variable selection and preview update
        Test.TerminalSnapshot("variable_tree_variable_selected")
        
        -- Test Global scope expansion (which is collapsed by default)
        vim.cmd("normal! gg") -- Go to top 
        vim.cmd("normal! jjj") -- Move down to Global scope (3rd scope)
        nio.sleep(100)
        vim.cmd("normal! \\<CR>") -- Press Enter to expand Global scope
        nio.sleep(500) -- Give more time for async operations
        
        -- Take snapshot showing Global scope expanded
        Test.TerminalSnapshot("variable_tree_global_scope_expanded")
        
        -- Now collapse it again by pressing Enter
        vim.cmd("normal! \\<CR>") -- Press Enter to collapse again
        nio.sleep(500)
        
        -- Take snapshot showing Global scope collapsed
        Test.TerminalSnapshot("variable_tree_global_scope_collapsed")
        
        -- Test Local scope collapse (user override of auto-expansion)
        vim.cmd("normal! gg") -- Go back to Local scope (first line)
        nio.sleep(100)
        vim.cmd("normal! \\<CR>") -- Press Enter to collapse Local scope (overriding auto-expansion)
        nio.sleep(500)
        
        -- Take snapshot showing Local scope collapsed
        Test.TerminalSnapshot("variable_tree_local_scope_collapsed")
        
        -- Now expand Local scope again by pressing Enter
        vim.cmd("normal! \\<CR>") -- Press Enter to expand Local scope again
        nio.sleep(500)
        
        -- Take snapshot showing Local scope re-expanded  
        Test.TerminalSnapshot("variable_tree_local_scope_expanded")
        
        -- Navigate to a variable and show the preview pane content
        vim.cmd("normal! j") -- Move to first variable
        nio.sleep(100)
        
        -- Take snapshot showing variable preview
        Test.TerminalSnapshot("variable_tree_variable_preview")
        
        -- Test toggling (hide)
        vim.cmd("NeodapVariableTreeToggle")
        nio.sleep(200)
        
        -- Take snapshot showing variables window hidden
        Test.TerminalSnapshot("variable_tree_toggled_hidden")
        
        -- Test toggling (show again)
        vim.cmd("NeodapVariableTreeToggle")
        nio.sleep(300)
        
        -- Take snapshot showing variables window shown again
        Test.TerminalSnapshot("variable_tree_toggled_shown")
        
        -- Test explicit hide command
        vim.cmd("NeodapVariableTreeHide")
        nio.sleep(200)
        
        -- Take final snapshot showing variables hidden
        Test.TerminalSnapshot("variable_tree_explicitly_hidden")
        
        -- Clean up
        api:destroy()
    end)
end)






































































































--[[ TERMINAL SNAPSHOT: variable_tree_breakpoint_set
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

--[[ TERMINAL SNAPSHOT: variable_tree_stopped_at_breakpoint
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

--[[ TERMINAL SNAPSHOT: variable_tree_status_shown
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

--[[ TERMINAL SNAPSHOT: variable_tree_floating_window_shown
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

--[[ TERMINAL SNAPSHOT: variable_tree_variable_selected
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: variable_tree_global_scope_expanded
Size: 24x80
Cursor: [4, 0] (line 4, col 0)
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
24|                                                               4,1           All
]]

--[[ TERMINAL SNAPSHOT: variable_tree_global_scope_collapsed
Size: 24x80
Cursor: [4, 0] (line 4, col 0)
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
24|                                                               4,1           All
]]

--[[ TERMINAL SNAPSHOT: variable_tree_local_scope_collapsed
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

--[[ TERMINAL SNAPSHOT: variable_tree_local_scope_expanded
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

--[[ TERMINAL SNAPSHOT: variable_tree_variable_preview
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: variable_tree_toggled_hidden
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: variable_tree_toggled_shown
Size: 24x80
Cursor: [2, 0] (line 2, col 0)
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
24|                                                               2,1           All
]]

--[[ TERMINAL SNAPSHOT: variable_tree_explicitly_hidden
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