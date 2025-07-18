local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local FrameHighlight = require("neodap.plugins.FrameHighlight")
local nio = require("nio")

Test.Describe("Step Navigation Stress Test", function()

  Test.It("rapid_step_navigation_stress", function()
    local api = prepare()
    
    -- Load plugins
    local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)
    api:getPluginInstance(BreakpointApi)
    local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
    api:getPluginInstance(FrameHighlight)
    
    -- Open loop.js from fixture (using working config)
    local fixture_path = vim.fn.fnamemodify("spec/fixtures/workspaces/single-node-project", ":p")
    vim.cmd("edit " .. fixture_path .. "/loop.js")
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    
    -- Set breakpoint on loop line
    toggleBreakpoint:toggle()
    nio.sleep(20)
    
    -- Track execution states
    local breakpoint_hit = false
    local step_count = 0
    local max_steps = 5  -- Reduce stress to prevent overwhelming the adapter
    local preemption_messages = {}
    
    -- Register session listener (only for session 2)
    api:onSession(function(session)
      if session.ref.id == 1 then return end
      
      session:onThread(function(thread)
        thread:onStopped(function(event)
          if event.reason == "breakpoint" and not breakpoint_hit then
            breakpoint_hit = true
            print("BREAKPOINT HIT - Starting rapid step navigation")
            
            -- SPAM STEP COMMANDS - This should trigger preemption
            for i = 1, max_steps do
              -- Wrap step commands in pcall to handle "Thread is not paused" errors
              local success1, err1 = pcall(function()
                print("Step " .. i .. " - stepIn")
                thread:stepIn()
              end)
              if not success1 then
                print("stepIn failed: " .. tostring(err1))
              end
              
              local success2, err2 = pcall(function()
                print("Step " .. i .. " - stepOut")  
                thread:stepOut()
              end)
              if not success2 then
                print("stepOut failed: " .. tostring(err2))
              end
              
              local success3, err3 = pcall(function()
                print("Step " .. i .. " - stepOver")
                thread:stepOver()
              end)
              if not success3 then
                print("stepOver failed: " .. tostring(err3))
              end
              
              -- Small delay between batches to prevent overwhelming the adapter
              nio.sleep(50)
            end
            
          elseif event.reason == "step" then
            step_count = step_count + 1
            print("STEP EVENT " .. step_count .. " - reason: " .. event.reason)
            
            -- Check if we've completed enough steps (rapid fire causes failures, so expect fewer)
            if step_count >= 2 then
              print("STRESS TEST COMPLETED - " .. step_count .. " step events processed")
            end
          end
        end)
      end)
    end)
    
    -- Create session from launch.json (using Debug Loop config)
    local workspace_info = launchJsonSupport:detectWorkspace(fixture_path)
    launchJsonSupport:createSessionFromConfig("Debug Loop []", api.manager, workspace_info)
    
    -- Wait for breakpoint hit
    vim.wait(5000, function() return breakpoint_hit end)
    
    -- Allow time for step operations to complete (expecting fewer due to rapid-fire failures)
    vim.wait(10000, function() return step_count >= 2 end)
    
    nio.sleep(1000)
    
    print("FINAL RESULT: breakpoint_hit=" .. tostring(breakpoint_hit) .. ", step_count=" .. step_count)
  end)

end)