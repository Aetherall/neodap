-- Test: NeodapNeotreeVariableSource variable expansion
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local NeodapNeotreeVariableSource = require("neodap.plugins.NeodapNeotreeVariableSource")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("NeodapNeotreeVariableSource Variable Expansion", function()
    Test.It("neotree_variable_expansion", function()
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

        -- Test variable expansion functionality
        local source_module = neotreeSource.source
        
        -- Get Global scope
        local scopes_promise = nio.control.future()
        source_module.get_items(nil, nil, function(nodes)
            scopes_promise.set(nodes)
        end)
        local scope_nodes = scopes_promise.wait()
        
        local global_scope = nil
        for _, scope in ipairs(scope_nodes) do
            if scope.name == "Global" then
                global_scope = scope
                break
            end
        end
        
        assert(global_scope ~= nil)
        
        -- Get Global scope variables  
        local global_vars_promise = nio.control.future()
        source_module.get_items(nil, global_scope.id, function(nodes)
            global_vars_promise.set(nodes)
        end)
        local global_variables = global_vars_promise.wait()
        
        -- Find a variable that can be expanded
        local expandable_var = nil
        for _, var_node in ipairs(global_variables) do
            if var_node.has_children then
                expandable_var = var_node
                break
            end
        end
        
        -- Test expansion if we found an expandable variable
        local child_nodes = {}
        if expandable_var then
            local children_promise = nio.control.future()
            source_module.get_items(nil, expandable_var.id, function(nodes)
                children_promise.set(nodes)
            end)
            child_nodes = children_promise.wait()
            
            -- Verify expansion structure
            assert(#child_nodes > 0)
            for _, child in ipairs(child_nodes) do
                assert(child.name ~= nil)
                assert(child.type == "variable")
            end
        end
        
        -- Verify we have global variables
        assert(#global_variables > 0)

        -- Take snapshot showing variable expansion
        Test.TerminalSnapshot("neotree_variable_expansion")

        -- Clean up
        api:destroy()
    end)
end)

--[[ TERMINAL SNAPSHOT: neotree_variable_expansion
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