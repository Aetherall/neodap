local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local FrameHighlight = require("neodap.plugins.FrameHighlight")
local nio = require("nio")

Test.Describe("Crash Reproduction Test", function()

  Test.It("aggressive_step_navigation_crash", function()
    local api = prepare()
    
    -- Load plugins
    local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)
    api:getPluginInstance(BreakpointApi)
    local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
    api:getPluginInstance(FrameHighlight)
    
    -- Use the loop.js file that matches the "Debug Loop []" configuration
    local fixture_path = vim.fn.fnamemodify("spec/fixtures/workspaces/single-node-project", ":p")
    vim.cmd("edit " .. fixture_path .. "/loop.js")
    vim.api.nvim_win_set_cursor(0, { 3, 0 })  -- Set breakpoint on loop line
    
    -- Set breakpoint
    toggleBreakpoint:toggle()
    nio.sleep(20)
    
    -- Track states
    local breakpoint_hit = false
    local step_count = 0
    local preemptions = 0
    local crashes = 0
    local test_completed = false
    
    -- More aggressive step spamming
    local function aggressive_step_spam(thread)
      print("STARTING AGGRESSIVE STEP SPAM")
      
      -- Moderate rapid fire with some error handling
      for i = 1, 10 do
        pcall(function() thread:stepIn() end)
        pcall(function() thread:stepOut() end)
        pcall(function() thread:stepOver() end)
        pcall(function() thread:stepIn() end)
        pcall(function() thread:stepOut() end)
        print("Spam batch " .. i .. " completed")
        nio.sleep(20)  -- Small delay to prevent completely overwhelming the adapter
      end
      
      print("AGGRESSIVE STEP SPAM COMPLETED - 50 commands issued")
    end
    
    -- Session listener
    api:onSession(function(session)
      if session.ref.id == 1 then return end
      
      session:onThread(function(thread)
        thread:onStopped(function(event)
          print("STOPPED EVENT - reason: " .. event.reason)
          
          if event.reason == "breakpoint" and not breakpoint_hit and not test_completed then
            breakpoint_hit = true
            print("BREAKPOINT HIT - Starting aggressive step spam")
            
            -- Use pcall to catch any crashes
            local success, error_msg = pcall(function()
              aggressive_step_spam(thread)
            end)
            
            if not success then
              crashes = crashes + 1
              print("CRASH DETECTED: " .. tostring(error_msg))
            end
            
            test_completed = true
            
          elseif event.reason == "step" then
            step_count = step_count + 1
            print("STEP EVENT " .. step_count)
            
            -- Check if we can get stack info
            local success, stack_info = pcall(function()
              local stack = thread:stack()
              if stack then
                local top_frame = stack:top()
                if top_frame then
                  return "Line " .. top_frame.ref.line
                end
              end
              return "No stack info"
            end)
            
            if not success then
              preemptions = preemptions + 1
              print("PREEMPTION/ERROR accessing stack: " .. tostring(stack_info))
            else
              print("Stack info: " .. stack_info)
            end
          end
        end)
      end)
    end)
    
    -- Create session
    local workspace_info = launchJsonSupport:detectWorkspace(fixture_path)
    launchJsonSupport:createSessionFromConfig("Debug Loop []", api.manager, workspace_info)
    
    -- Wait for breakpoint hit
    vim.wait(5000, function() return breakpoint_hit end)
    
    -- Allow time for the spam to complete (expecting much fewer events due to command failures)
    vim.wait(10000, function() return test_completed and (step_count >= 3 or crashes > 0 or preemptions > 2) end)
    
    nio.sleep(2000)
    
    print("FINAL RESULTS:")
    print("- Breakpoint hit: " .. tostring(breakpoint_hit))
    print("- Step events: " .. step_count)
    print("- Preemptions: " .. preemptions)
    print("- Crashes: " .. crashes)
    
    -- Don't fail the test - we want to see what happens
    if crashes > 0 then
      print("CRASHES REPRODUCED! Check logs for details.")
    elseif preemptions > 0 then
      print("PREEMPTIONS DETECTED! Check logs for details.")
    else
      print("NO CRASHES OR PREEMPTIONS - System handled aggressive spam well.")
    end
  end)

end)