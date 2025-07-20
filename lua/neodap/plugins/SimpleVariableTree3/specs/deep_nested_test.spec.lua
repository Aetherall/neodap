-- Test: Deep nested variable expansion
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local SimpleVariableTree3 = require("neodap.plugins.SimpleVariableTree3")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("SimpleVariableTree3 Deep Nesting", function()
    Test.It("demonstrates_deep_nested_expansion", function()
        local api, start = prepare()

        local simpleTree = api:getPluginInstance(SimpleVariableTree3)
        local neotree = require("neo-tree")

        neotree.setup({
            sources = { "neodap.plugins.SimpleVariableTree3" },
            default_source = "NeodapVariables"
        })

        -- Get plugin instances
        local breakpointApi = api:getPluginInstance(BreakpointApi)
        local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
        local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)

        -- Open file and set breakpoint
        vim.cmd("edit spec/fixtures/workspaces/single-node-project/loop.js")
        vim.api.nvim_win_set_cursor(0, { 3, 1 })
        toggleBreakpoint:toggle()
        nio.sleep(50)

        local stopped = Test.spy('stopped')

        api:onSession(function(session)
            if session.ref.id == 1 then return end
            
            session:onThread(function(thread)
                thread:onStopped(stopped.trigger)
            end)
        end)

        -- Start debugging
        local current_file = vim.api.nvim_buf_get_name(0)
        local workspace_info = launchJsonSupport:detectWorkspace(current_file)
        launchJsonSupport:createSessionFromConfig("Debug Loop [single-node-project]", api.manager, workspace_info)

        stopped.wait()
        nio.sleep(200)

        print("Opening Neo-tree...")
        vim.cmd("Neotree float NeodapVariables")
        nio.sleep(300)

        -- Focus Neo-tree
        local windows = vim.api.nvim_list_wins()
        for _, win in ipairs(windows) do
            local buf = vim.api.nvim_win_get_buf(win)
            local filetype = vim.api.nvim_buf_get_option(buf, 'filetype')
            if filetype == 'neo-tree' then
                vim.api.nvim_set_current_win(win)
                break
            end
        end

        -- Get Neo-tree state for direct command calls
        local manager = require("neo-tree.sources.manager")
        local tree_state = manager.get_state("NeodapVariables")

        -- Navigate to Global scope and expand it
        vim.cmd("normal! gg")
        vim.cmd("normal! jj")  -- Move to Global
        nio.sleep(100)
        
        print("Expanding Global scope...")
        if tree_state.commands and tree_state.commands.toggle_node then
            tree_state.commands.toggle_node(tree_state)
        end
        nio.sleep(500)

        -- Now find and expand console object (it's more accessible than Buffer)
        print("Finding console object to expand...")
        
        -- Search for console in the expanded list
        vim.cmd("normal! gg")
        for i = 1, 30 do
            local line = vim.api.nvim_get_current_line()
            if line:match("console = ") then
                print("Found console at line", i)
                break
            end
            vim.cmd("normal! j")
        end
        nio.sleep(100)

        -- Expand console to see its methods
        print("Expanding console object...")
        if tree_state.commands and tree_state.commands.toggle_node then
            tree_state.commands.toggle_node(tree_state)
        end
        nio.sleep(500)

        Test.TerminalSnapshot('console_methods_expanded')

        -- Now expand one of console's methods to see deeper nesting
        vim.cmd("normal! j")  -- Move to first console method
        nio.sleep(100)
        
        print("Expanding console method for deeper nesting...")
        if tree_state.commands and tree_state.commands.toggle_node then
            tree_state.commands.toggle_node(tree_state)
        end
        nio.sleep(500)

        Test.TerminalSnapshot('deep_nested_properties')

        api:destroy()
    end)
end)