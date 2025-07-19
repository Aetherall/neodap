-- Test: Pattern matching debug for VariableTree
local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local VariableTree = require("neodap.plugins.VariableTree")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local nio = require("nio")

Test.Describe("VariableTree Pattern Debug", function()
    Test.It("test_pattern_matching_directly", function()
        local api, start = prepare()

        -- Get plugin instances
        local breakpointApi = api:getPluginInstance(BreakpointApi)
        local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
        local variableTree = api:getPluginInstance(VariableTree)
        api:getPluginInstance(DebugOverlay)
        local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)

        -- Open the loop.js file that we know works
        vim.cmd("edit spec/fixtures/workspaces/single-node-project/loop.js")

        -- Move cursor to line 3 (inside the setInterval callback)
        vim.api.nvim_win_set_cursor(0, { 3, 1 })

        -- Set breakpoint at line 3
        toggleBreakpoint:toggle()
        nio.sleep(50)

        -- Set up promises to wait for session events
        local session_promise = nio.control.future()
        local stopped_promise = nio.control.future()
        local scopes_ready = nio.control.future()
        
        api:onSession(function(session)
            if not session_promise.is_set() then
                session_promise.set(session)
            end
            
            session:onThread(function(thread)
                thread:onStopped(function()
                    if not stopped_promise.is_set() then
                        -- Give time for stack and scopes to be available
                        nio.sleep(100)
                        local stack = thread:stack()
                        if stack then
                            local frame = stack:top()
                            if frame then
                                local scopes = frame:scopes()
                                if scopes and #scopes > 0 and not scopes_ready.is_set() then
                                    scopes_ready.set(true)
                                end
                            end
                        end
                        stopped_promise.set(true)
                    end
                end)
            end)
        end)
        
        -- Use LaunchJsonSupport to start debugging with closest launch.json!
        local current_file = vim.api.nvim_buf_get_name(0)
        local workspace_info = launchJsonSupport:detectWorkspace(current_file)
        local session = launchJsonSupport:createSessionFromConfig("Debug Loop [single-node-project]", api.manager, workspace_info)
        
        -- Wait for session to start and hit breakpoint
        session_promise.wait()
        stopped_promise.wait()
        scopes_ready.wait()

        -- Show VariableTree floating window
        vim.cmd("NeodapVariableTreeShow")
        nio.sleep(300)
        
        -- Navigate to Global scope and expand it
        vim.cmd("normal! gg") -- Go to Local scope
        vim.cmd("normal! j") -- Go to Local variable
        vim.cmd("normal! j") -- Go to Closure scope
        vim.cmd("normal! j") -- Go to Closure variable
        vim.cmd("normal! j") -- Go to Global scope
        nio.sleep(100)
        
        -- Expand Global scope to reveal complex global objects
        variableTree.logger:debug("=== MANUAL TEST: About to expand Global scope ===")
        variableTree:ToggleScopeAtCursor()
        nio.sleep(500) -- Give time for expensive Global scope to load
        
        -- Navigate to the first complex global object 
        vim.cmd("normal! j") -- Move to first global variable
        nio.sleep(100)
        
        -- Get the current line content to test pattern matching directly
        local line_num = vim.api.nvim_win_get_cursor(variableTree.popup.winid)[1]
        local line = vim.api.nvim_buf_get_lines(variableTree.popup.bufnr, line_num - 1, line_num, false)[1]
        
        variableTree.logger:debug("=== MANUAL TEST: Current line for pattern testing ===")
        variableTree.logger:debug("Line number:", line_num)
        variableTree.logger:debug("Raw line content:", vim.inspect(line))
        variableTree.logger:debug("Line length:", line and #line or "nil")
        
        if line then
            -- Test all patterns manually
            local scope_match1 = line:match("^▼ ")
            local scope_match2 = line:match("^▶ ")
            local var_match1 = line:match("^%s+▼ ")
            local var_match2 = line:match("^%s+▶ ")
            local alt_match1 = line:match("^  ▼ ")
            local alt_match2 = line:match("^  ▶ ")
            
            variableTree.logger:debug("=== PATTERN TESTING RESULTS ===")
            variableTree.logger:debug("^▼ :", scope_match1 and "MATCH" or "NO MATCH")
            variableTree.logger:debug("^▶ :", scope_match2 and "MATCH" or "NO MATCH") 
            variableTree.logger:debug("^%s+▼ :", var_match1 and "MATCH" or "NO MATCH")
            variableTree.logger:debug("^%s+▶ :", var_match2 and "MATCH" or "NO MATCH")
            variableTree.logger:debug("^  ▼ :", alt_match1 and "MATCH" or "NO MATCH")
            variableTree.logger:debug("^  ▶ :", alt_match2 and "MATCH" or "NO MATCH")
            
            -- Test what pattern SHOULD work
            local should_match = line:match("^%s*▶ ")
            variableTree.logger:debug("^%s*▶ :", should_match and "MATCH" or "NO MATCH")
        end
        
        -- Now try to expand the variable
        variableTree.logger:debug("=== MANUAL TEST: About to expand variable ===")
        variableTree:ToggleScopeAtCursor()
        nio.sleep(500)
        
        -- Clean up
        api:destroy()
    end)
end)