-- Test: Core functionality only
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local SimpleVariableTree3 = require("neodap.plugins.SimpleVariableTree3")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("SimpleVariableTree3 Core", function()
    Test.It("core_recursive_expansion_only", function()
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

        print("Trying to open Neo-tree...")
        vim.cmd("Neotree float NeodapVariables")
        print("Neo-tree command executed")

        nio.sleep(200)
        Test.TerminalSnapshot('variable_tree_opened')

        api:destroy()
    end)
end)









--[[ TERMINAL SNAPSHOT: variable_tree_opened
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {▕ Neo-tree NeodapVariables               ▏
 3|  console.log("ALoop▕  Local                                ▏
 4|  console.log("BLoop▕  Closure                              ▏
 5|  console.log("CLoop▕  Global                               ▏
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
