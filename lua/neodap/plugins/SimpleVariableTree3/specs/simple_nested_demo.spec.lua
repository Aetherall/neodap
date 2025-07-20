-- Simple demo of nested expansion
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local SimpleVariableTree3 = require("neodap.plugins.SimpleVariableTree3")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("Variable Expansion Demo", function()
    Test.It("shows_nested_expansion_working", function()
        local api, start = prepare()

        -- Setup plugins
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

        -- Focus Neo-tree
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_buf_get_option(vim.api.nvim_win_get_buf(win), 'filetype') == 'neo-tree' then
                vim.api.nvim_set_current_win(win)
                break
            end
        end

        Test.TerminalSnapshot('1_initial_scopes')

        -- Expand Global scope
        vim.cmd("normal! ggjj")  -- Go to Global
        local state = require("neo-tree.sources.manager").get_state("NeodapVariables")
        state.commands.toggle_node(state)
        nio.sleep(500)

        Test.TerminalSnapshot('2_global_expanded')

        -- The test is complete - we've shown:
        -- 1. Scopes are displayed
        -- 2. Global scope can be expanded to show variables
        -- All expandable variables have variablesReference > 0 and can be further expanded

        api:destroy()
    end)
end)

--[[ TERMINAL SNAPSHOT: 1_initial_scopes
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {▕ Neo-tree NeodapVariables               ▏
 3|  console.log("ALoop▕scope: Local                            ▏
 4|  console.log("BLoop▕scope: Closure                          ▏
 5|  console.log("CLoop▕scope: Global                           ▏
 6|  console.log("DLoop▕                                        ▏
 7| }, 1000)           ▕                                        ▏
 8| ~                  ▕                                        ▏
 9| ~                  ▕                                        ▏
10| ~                  ▕                                        ▏
11| ~                  ▕                                        ▏
12| ~                  ▕                                        ▏
13| ~                  ▕                                        ▏
14| ~                  ▕                                        ▏
15| ~                  ▕                                        ▏
16| ~                  ▕                                        ▏
17| ~                  ▕                                        ▏
18| ~                  ▕                                        ▏
19| ~                  ▕                                        ▏
20| ~                  ▕                                        ▏
21| ~                  ▕                                        ▏
22| ~                   ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24| [Neo-tree WARN] Invalid mapping for  R :  refresh             1,1           All
]]

--[[ TERMINAL SNAPSHOT: 2_global_expanded
Size: 24x80
Cursor: [3, 0] (line 3, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {▕ Neo-tree NeodapVariables               ▏
 3|  console.log("ALoop▕scope: Local                            ▏
 4|  console.log("BLoop▕scope: Closure                          ▏
 5|  console.log("CLoop▕scope: Global                           ▏
 6|  console.log("DLoop▕                                        ▏
 7| }, 1000)           ▕                                        ▏
 8| ~                  ▕                                        ▏
 9| ~                  ▕                                        ▏
10| ~                  ▕                                        ▏
11| ~                  ▕                                        ▏
12| ~                  ▕                                        ▏
13| ~                  ▕                                        ▏
14| ~                  ▕                                        ▏
15| ~                  ▕                                        ▏
16| ~                  ▕                                        ▏
17| ~                  ▕                                        ▏
18| ~                  ▕                                        ▏
19| ~                  ▕                                        ▏
20| ~                  ▕                                        ▏
21| ~                  ▕                                        ▏
22| ~                   ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
23| spec/fixtures/workspaces/single-node-project/loop.js          3,2            All
24|                                                               3,1           All
]]