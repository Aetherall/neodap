-- Test: NeotreeAutoIntegration hybrid registration functionality
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local NeodapNeotreeVariableSource = require("neodap.plugins.NeodapNeotreeVariableSource")
local NeotreeAutoIntegration = require("neodap.plugins.NeotreeAutoIntegration")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("NeotreeAutoIntegration Hybrid Registration", function()
    Test.It("hybrid_auto_registration_service", function()
        local api, start = prepare()

        -- Get plugin instances
        local breakpointApi = api:getPluginInstance(BreakpointApi)
        local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
        local integrationService = api:getPluginInstance(NeotreeAutoIntegration)
        local neotreeSource = api:getPluginInstance(NeodapNeotreeVariableSource)
        api:getPluginInstance(DebugOverlay)
        local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)

        -- Setup basic Neo-tree first (this makes the sources manager available)
        require("neo-tree").setup({
            sources = { "filesystem" },
            filesystem = {
                window = { position = "left", width = 40 }
            }
        })

        -- Verify the integration service exists
        assert(integrationService ~= nil)
        assert(integrationService.name == "NeotreeAutoIntegration")

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

        -- Verify variable source is working
        assert(neotreeSource.current_frame ~= nil)
        assert(neotreeSource.name == "neodap.plugins.NeodapNeotreeVariableSource")

        -- Get the variable tree data to verify
        local scopes = neotreeSource.current_frame:scopes()
        assert(scopes ~= nil)
        assert(#scopes == 3)

        -- Wait for auto-registration to complete
        nio.sleep(500)

        -- Check registration status via integration service
        local status = integrationService:getSourceStatus(neotreeSource.name)
        assert(status ~= nil)
        assert(status.module.name == neotreeSource.name)

        -- List all registered sources
        local sources = integrationService:listRegisteredSources()
        assert(#sources >= 1)
        
        -- Find our source in the list
        local found_our_source = false
        for _, source_info in ipairs(sources) do
            if source_info.name == neotreeSource.name then
                found_our_source = true
                assert(source_info.display_name == "🐛 Variables")
                break
            end
        end
        assert(found_our_source)

        -- Test that Neo-tree command works (the ultimate test!)
        vim.cmd("Neotree float neodap.plugins.NeodapNeotreeVariableSource")

        -- Take snapshot showing the hybrid registration working
        Test.TerminalSnapshot("hybrid_auto_registration_service")

        -- Clean up
        api:destroy()
    end)
end)

--[[ TERMINAL SNAPSHOT: hybrid_auto_registration_service
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

Highlights:
  Comment[1:1-1:8]
  Comment[2:1-2:8]
  Comment[3:1-3:8]

 1| let i = 0;
 2| setInterval(() => {▕ Neo-tree Neodap.plugins.NeodapNeotreeV…▏
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