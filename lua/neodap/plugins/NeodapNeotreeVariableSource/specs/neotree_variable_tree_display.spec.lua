-- Test: NeodapNeotreeVariableSource variable tree display
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local NeodapNeotreeVariableSource = require("neodap.plugins.NeodapNeotreeVariableSource")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("NeodapNeotreeVariableSource Variable Tree Display", function()
    Test.It("neotree_variable_tree_display", function()
        local api, start = prepare()

        -- Get plugin instances first (this registers the source)
        local breakpointApi = api:getPluginInstance(BreakpointApi)
        local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
        local neotreeSource = api:getPluginInstance(NeodapNeotreeVariableSource)
        api:getPluginInstance(DebugOverlay)
        local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)

        -- Setup Neo-tree with our source (after it's registered)
        require("neo-tree").setup({
            sources = { 
                "filesystem", 
                "neodap-variable-tree"
            },
            ["neodap-variable-tree"] = {
                window = {
                    position = "float",
                    mappings = {
                        ["<cr>"] = "toggle_node",
                        ["<space>"] = "toggle_node", 
                        ["o"] = "toggle_node",
                        ["q"] = "close_window",
                    },
                },
                popup = {
                    size = {
                        height = "70%",
                        width = "60%", 
                    },
                    position = "50%",
                },
            },
        })

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

        -- Test that we can get variable data from the source
        local source_module = neotreeSource.source
        
        -- Get scopes
        local scopes_promise = nio.control.future()
        source_module.get_items(nil, nil, function(nodes)
            scopes_promise.set(nodes)
        end)
        local scope_nodes = scopes_promise.wait()
        
        -- Get Local scope variables
        local local_scope = nil
        for _, scope in ipairs(scope_nodes) do
            if scope.name == "Local" then
                local_scope = scope
                break
            end
        end

        local variables = {}
        if local_scope then
            local vars_promise = nio.control.future()
            source_module.get_items(nil, local_scope.id, function(nodes)
                vars_promise.set(nodes)
            end)
            variables = vars_promise.wait()
        end

        -- Verify the tree structure
        assert(#scope_nodes == 3)
        assert(local_scope ~= nil)
        assert(#variables > 0)
        assert(variables[1].type == "variable")
        assert(string.find(variables[1].name, " = ") ~= nil) -- Variable should include value

        -- Take snapshot showing the variable tree structure
        Test.TerminalSnapshot("neotree_variable_tree_display")

        -- Clean up
        api:destroy()
    end)
end)

--[[ TERMINAL SNAPSHOT: neotree_variable_tree_display
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