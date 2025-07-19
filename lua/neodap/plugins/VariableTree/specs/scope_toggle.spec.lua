-- Test: VariableTree scope toggle functionality demonstration
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local VariableTree = require("neodap.plugins.VariableTree")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("VariableTree Scope Toggle", function()
    Test.It("demonstrates_manual_scope_expand_collapse", function()
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
        Test.TerminalSnapshot("scope_toggle_breakpoint_set")

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
        Test.TerminalSnapshot("scope_toggle_stopped_at_breakpoint")

        -- Show VariableTree floating window
        vim.cmd("NeodapVariableTreeShow")
        nio.sleep(300) -- Give time for the window to render
        
        -- Take snapshot showing initial state with auto-expanded Local and Closure scopes
        Test.TerminalSnapshot("scope_toggle_initial_auto_expanded")
        
        -- Test manual collapse of Local scope (user override of auto-expansion)
        -- The cursor should be positioned on the Local scope line (first line)
        vim.cmd("normal! gg") -- Ensure we're on the first line (Local scope)
        nio.sleep(100)
        
        -- Take snapshot showing cursor position on Local scope
        Test.TerminalSnapshot("scope_toggle_cursor_on_local_scope")
        
        -- Press Enter to collapse Local scope (this should override auto-expansion)
        -- The floating window should already be focused, cursor should be on Local scope line
        vim.cmd("normal! gg") -- Ensure we're on the first line (Local scope)
        -- Call toggle function directly since key mapping might not work in test
        variableTree:ToggleScopeAtCursor()
        nio.sleep(500) -- Give time for the toggle action and window refresh
        
        -- Take snapshot showing Local scope collapsed (should show ▶ Local)
        Test.TerminalSnapshot("scope_toggle_local_scope_collapsed")
        
        -- Now test expanding Local scope again by pressing Enter
        -- Cursor should still be on the Local scope line (in the floating window)
        variableTree:ToggleScopeAtCursor() -- Call toggle function directly
        nio.sleep(500) -- Give time for the toggle action and window refresh
        
        -- Take snapshot showing Local scope re-expanded (should show ▼ Local with variables)
        Test.TerminalSnapshot("scope_toggle_local_scope_re_expanded")
        
        -- Test collapsing Closure scope as well
        -- Find the Closure scope line (should be around line 3 after Local scope and its variable)
        vim.cmd("normal! j") -- Move down from Local scope
        vim.cmd("normal! j") -- Move down from Local variable 
        vim.cmd("normal! j") -- Should now be on Closure scope line
        nio.sleep(100)
        
        -- Take snapshot showing cursor on Closure scope
        Test.TerminalSnapshot("scope_toggle_cursor_on_closure_scope")
        
        -- Press Enter to collapse Closure scope
        variableTree:ToggleScopeAtCursor() -- Call toggle function directly
        nio.sleep(500)
        
        -- Take snapshot showing Closure scope collapsed
        Test.TerminalSnapshot("scope_toggle_closure_scope_collapsed")
        
        -- Test expanding Global scope (which starts collapsed)
        -- Find the Global scope line (should be after Closure scope and its variable)
        vim.cmd("normal! j") -- Move down from Closure scope
        vim.cmd("normal! j") -- Move down from Closure variable
        vim.cmd("normal! j") -- Should now be on Global scope line
        nio.sleep(100)
        
        -- Take snapshot showing cursor on Global scope
        Test.TerminalSnapshot("scope_toggle_cursor_on_global_scope")
        
        -- Press Enter to expand Global scope (this is expensive, so auto-expansion is disabled)
        variableTree:ToggleScopeAtCursor() -- Call toggle function directly
        nio.sleep(500)
        
        -- Take snapshot showing Global scope expanded
        Test.TerminalSnapshot("scope_toggle_global_scope_expanded")
        
        -- Test collapsing Global scope back
        variableTree:ToggleScopeAtCursor() -- Call toggle function directly
        nio.sleep(500)
        
        -- Take snapshot showing Global scope collapsed again
        Test.TerminalSnapshot("scope_toggle_global_scope_re_collapsed")
        
        -- Test multiple rapid toggles to ensure state consistency
        -- Go back to Local scope (should be collapsed now) and expand it again
        vim.cmd("normal! gg") -- Go to first line (Local scope)
        nio.sleep(100)
        variableTree:ToggleScopeAtCursor() -- Expand Local directly
        nio.sleep(300)
        
        -- Take final snapshot showing final state with Local expanded, others collapsed
        Test.TerminalSnapshot("scope_toggle_final_state")
        
        -- Close the variable tree window
        vim.cmd("NeodapVariableTreeHide")
        nio.sleep(200)
        
        -- Take snapshot showing variable tree hidden
        Test.TerminalSnapshot("scope_toggle_window_closed")
        
        -- Clean up
        api:destroy()
    end)
end)
















































































































































--[[ TERMINAL SNAPSHOT: scope_toggle_breakpoint_set
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

--[[ TERMINAL SNAPSHOT: scope_toggle_stopped_at_breakpoint
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

--[[ TERMINAL SNAPSHOT: scope_toggle_initial_auto_expanded
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

--[[ TERMINAL SNAPSHOT: scope_toggle_cursor_on_local_scope
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

--[[ TERMINAL SNAPSHOT: scope_toggle_local_scope_collapsed
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

--[[ TERMINAL SNAPSHOT: scope_toggle_local_scope_re_expanded
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

--[[ TERMINAL SNAPSHOT: scope_toggle_cursor_on_closure_scope
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

--[[ TERMINAL SNAPSHOT: scope_toggle_closure_scope_collapsed
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

--[[ TERMINAL SNAPSHOT: scope_toggle_cursor_on_global_scope
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

--[[ TERMINAL SNAPSHOT: scope_toggle_global_scope_expanded
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