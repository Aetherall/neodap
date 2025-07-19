-- Test: NeodapNeotreeVariableSource scope hierarchy display
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local NeodapNeotreeVariableSource = require("neodap.plugins.NeodapNeotreeVariableSource")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("NeodapNeotreeVariableSource Scope Hierarchy", function()
    Test.It("neotree_scope_hierarchy", function()
        local api, start = prepare()

        -- Get plugin instances first (this registers the source)
        local breakpointApi = api:getPluginInstance(BreakpointApi)
        local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
        local neotreeSource = api:getPluginInstance(NeodapNeotreeVariableSource)
        api:getPluginInstance(DebugOverlay)
        local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)

        -- Open the loop.js file
        vim.cmd("edit spec/fixtures/workspaces/single-node-project/loop.js")
        vim.api.nvim_win_set_cursor(0, { 3, 1 })

        -- Set breakpoint at line 3
        toggleBreakpoint:toggle()
        nio.sleep(50)

        -- Set up session promises
        local session_promise = nio.control.future()
        local stopped_promise = nio.control.future()
        
        api:onSession(function(session)
            if not session_promise.is_set() then
                session_promise.set(session)
            end
            
            session:onThread(function(thread)
                thread:onStopped(function()
                    if not stopped_promise.is_set() then
                        nio.sleep(100)
                        stopped_promise.set(true)
                    end
                end)
            end)
        end)
        
        -- Start debugging
        local current_file = vim.api.nvim_buf_get_name(0)
        local workspace_info = launchJsonSupport:detectWorkspace(current_file)
        local session = launchJsonSupport:createSessionFromConfig("Debug Loop [single-node-project]", api.manager, workspace_info)
        
        -- Wait for breakpoint hit
        session_promise.wait()
        stopped_promise.wait()

        -- Test scope hierarchy structure
        local source_module = neotreeSource.source
        local scopes_promise = nio.control.future()
        source_module.get_items(nil, nil, function(nodes)
            scopes_promise.set(nodes)
        end)
        local scope_nodes = scopes_promise.wait()
        
        -- Verify scope hierarchy and auto-expansion behavior
        assert(#scope_nodes == 3)
        assert(scope_nodes[1].name == "Local")
        assert(scope_nodes[2].name == "Closure")
        assert(scope_nodes[3].name == "Global")
        
        -- Verify auto-expansion behavior
        assert(scope_nodes[1].loaded == true)  -- Local should auto-expand
        assert(scope_nodes[2].loaded == true)  -- Closure should auto-expand  
        assert(scope_nodes[3].loaded == false) -- Global should start collapsed
        
        -- Verify all scopes have children
        for _, scope in ipairs(scope_nodes) do
            assert(scope.has_children == true)
            assert(scope.type == "scope")
        end

        -- Take snapshot showing the scope hierarchy
        Test.TerminalSnapshot("neotree_scope_hierarchy")

        -- Clean up
        api:destroy()
    end)
end)

--[[ TERMINAL SNAPSHOT: neotree_scope_hierarchy
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