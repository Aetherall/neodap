local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local FrameHighlight = require("neodap.plugins.FrameHighlight")
local nio = require("nio")

Test.Describe("Step Navigation Stress Test", function()

  Test.It("rapid_step_navigation_stress", function()
    local original_dir = vim.fn.getcwd()
    local api = prepare()
    
    -- Load plugins
    local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)
    api:getPluginInstance(BreakpointApi)
    local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
    api:getPluginInstance(FrameHighlight)
    
    -- Open loop.js from fixture (using working config)
    local fixture_path = vim.fn.fnamemodify("spec/fixtures/workspaces/single-node-project", ":p")
    vim.api.nvim_set_current_dir(fixture_path)
    vim.cmd("edit loop.js")
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.api.nvim_set_current_dir(original_dir)
    
    -- Set breakpoint on loop line
    toggleBreakpoint:toggle()
    nio.sleep(20)
    
    -- Track execution states
    local breakpoint_hit = false
    local step_count = 0
    local max_steps = 10
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
              print("Step " .. i .. " - stepIn")
              thread:stepIn()
              print("Step " .. i .. " - stepOut")  
              thread:stepOut()
              print("Step " .. i .. " - stepOver")
              thread:stepOver()
            end
            
          elseif event.reason == "step" then
            step_count = step_count + 1
            print("STEP EVENT " .. step_count .. " - reason: " .. event.reason)
            
            -- Check if we've completed all steps
            if step_count >= max_steps then
              print("STRESS TEST COMPLETED - " .. step_count .. " step events processed")
            end
          end
        end)
      end)
    end)
    
    -- Create session from launch.json (using Debug Loop config)
    vim.api.nvim_set_current_dir(fixture_path)
    local workspace_info = launchJsonSupport:detectWorkspace(fixture_path)
    launchJsonSupport:createSessionFromConfig("Debug Loop []", api.manager, workspace_info)
    
    -- Wait for breakpoint hit
    vim.wait(5000, function() return breakpoint_hit end)
    
    -- Allow time for all step operations to complete
    vim.wait(10000, function() return step_count >= max_steps end)
    
    nio.sleep(1000)
    
    print("FINAL RESULT: breakpoint_hit=" .. tostring(breakpoint_hit) .. ", step_count=" .. step_count)
  end)

end)