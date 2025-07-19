-- Test: Simple popup functionality test
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local VariableTree = require("neodap.plugins.VariableTree")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("VariableTree Simple Popup Test", function()
    Test.It("popup_creation_and_sizing", function()
        local api, start = prepare()

        -- Get plugin instances
        local breakpointApi = api:getPluginInstance(BreakpointApi)
        local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
        local variableTree = api:getPluginInstance(VariableTree)
        api:getPluginInstance(DebugOverlay)
        local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)

        -- Open the loop.js file
        vim.cmd("edit spec/fixtures/workspaces/single-node-project/loop.js")
        vim.api.nvim_win_set_cursor(0, { 3, 1 })

        -- Set breakpoint
        toggleBreakpoint:toggle()
        nio.sleep(50)

        -- Set up session events
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

        -- Test popup creation
        variableTree.logger:debug("=== Testing popup creation ===")
        
        -- Test ShowVariables - should create popup
        vim.cmd("NeodapVariableTreeShow")
        nio.sleep(300)
        
        -- Verify popup was created
        if variableTree.popup then
            variableTree.logger:debug("SUCCESS: Popup created")
            variableTree.logger:debug("Popup mounted:", variableTree.popup._.mounted or false)
        else
            variableTree.logger:debug("ERROR: No popup created")
        end
        
        -- Test dynamic sizing by generating content
        if variableTree.popup and variableTree.popup._.mounted then
            local lines = variableTree:generateVariableTreeContent()
            variableTree.logger:debug("Generated", #lines, "lines of content")
            
            local size = variableTree:calculateContentSize(lines)
            variableTree.logger:debug("Calculated optimal size:", size)
        end
        
        -- Clean up
        api:destroy()
    end)
end)