-- Verify expansion actually works
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local SimpleVariableTree3 = require("neodap.plugins.SimpleVariableTree3")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("Verify Variable Expansion", function()
    Test.It("actually_expands_variables", function()
        local api, start = prepare()

        -- Setup
        api:getPluginInstance(SimpleVariableTree3)
        require("neo-tree").setup({
            sources = { "neodap.plugins.SimpleVariableTree3" },
            default_source = "NeodapVariables"
        })

        -- Set breakpoint
        vim.cmd("edit spec/fixtures/workspaces/single-node-project/loop.js")
        vim.api.nvim_win_set_cursor(0, { 3, 1 })
        api:getPluginInstance(ToggleBreakpoint):toggle()
        nio.sleep(50)

        local stopped = Test.spy('stopped')
        api:onSession(function(session)
            if session.ref.id == 1 then return end
            session:onThread(function(thread)
                thread:onStopped(stopped.trigger)
            end)
        end)

        -- Start debugging
        local file = vim.api.nvim_buf_get_name(0)
        local ws = api:getPluginInstance(LaunchJsonSupport):detectWorkspace(file)
        api:getPluginInstance(LaunchJsonSupport):createSessionFromConfig("Debug Loop [single-node-project]", api.manager, ws)

        stopped.wait()
        nio.sleep(200)

        -- Open tree
        vim.cmd("Neotree float NeodapVariables")
        nio.sleep(300)

        -- Focus Neo-tree window
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_buf_get_option(vim.api.nvim_win_get_buf(win), 'filetype') == 'neo-tree' then
                vim.api.nvim_set_current_win(win)
                break
            end
        end

        -- Get initial state
        local initial_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        print("Initial tree (should show 3 scopes):")
        for i, line in ipairs(initial_lines) do
            print(i, line)
        end

        -- Expand Global scope
        vim.cmd("normal! ggjj")  -- Go to Global
        local state = require("neo-tree.sources.manager").get_state("NeodapVariables")
        
        print("\nExpanding Global scope...")
        state.commands.toggle_node(state)
        nio.sleep(500)

        -- Get expanded state
        local expanded_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        print("\nExpanded tree (should show Global variables):")
        for i, line in ipairs(expanded_lines) do
            if i <= 10 then  -- Just show first 10 lines
                print(i, line)
            end
        end
        
        -- Verify expansion happened
        local found_variables = false
        for _, line in ipairs(expanded_lines) do
            if line:match("=") then  -- Variables have "name = value" format
                found_variables = true
                break
            end
        end

        Test.assert(found_variables, "Should find variables after expanding Global scope")
        print("\n✅ Variables found after expansion!")

        api:destroy()
    end)
end)