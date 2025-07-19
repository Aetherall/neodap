-- Test: NeodapNeotreeVariableSource basic source registration
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local NeodapNeotreeVariableSource = require("neodap.plugins.NeodapNeotreeVariableSource")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("NeodapNeotreeVariableSource Source Registration", function()
    Test.It("neotree_source_registration", function()
        local api, start = prepare()

        -- Get plugin instances first (this registers the source)
        local breakpointApi = api:getPluginInstance(BreakpointApi)
        local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
        local neotreeSource = api:getPluginInstance(NeodapNeotreeVariableSource)
        api:getPluginInstance(DebugOverlay)
        local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)

        -- Setup Neo-tree configuration with our source
        require("neo-tree").setup({
            sources = { "filesystem", "neodap-variable-tree" },
            filesystem = {
                window = { position = "left", width = 40 }
            },
            ["neodap-variable-tree"] = {
                window = {
                    position = "float",
                    mappings = {
                        ["<cr>"] = "toggle_node",
                        ["<space>"] = "toggle_node",
                        ["o"] = "toggle_node",
                    },
                },
                popup = {
                    size = { height = "60%", width = "50%" },
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

        -- Verify plugin state
        assert(neotreeSource.current_frame ~= nil)
        assert(neotreeSource.name == "neodap-variable-tree")

        -- Get the variable tree data to verify
        local scopes = neotreeSource.current_frame:scopes()
        assert(scopes ~= nil)
        assert(#scopes == 3)

        -- Wait for source registration to complete
        nio.sleep(200)
        
        -- Open real Neo-tree with our variable source
        vim.cmd("Neotree float neodap-variable-tree")

        -- Take snapshot showing the actual Neo-tree interface
        Test.TerminalSnapshot("neotree_source_registration")

        -- Clean up
        api:destroy()
    end)
end)




--[[ TERMINAL SNAPSHOT: neotree_source_registration
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

Highlights:
  Comment[1:1-1:8]
  Comment[2:1-2:8]
  Comment[3:1-3:8]

 1| let i = 0;
 2| setInterval(() => {▕ Neo-tree Neodap-variable-tree          ▏
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
24|                                                               1,1           All
]]