local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local FrameHighlight = require("neodap.plugins.FrameHighlight")
local nio = require("nio")

Test.Describe("User Interaction Crash Test", function()

  Test.It("simulate_user_mashing_keys", function()
    local original_dir = vim.fn.getcwd()
    local api = prepare()
    
    -- Load plugins
    local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)
    api:getPluginInstance(BreakpointApi)
    local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
    api:getPluginInstance(FrameHighlight)
    
    -- Use the loop.js that we know works
    local fixture_path = vim.fn.fnamemodify("spec/fixtures/workspaces/single-node-project", ":p")
    vim.api.nvim_set_current_dir(fixture_path)
    vim.cmd("edit loop.js")
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.api.nvim_set_current_dir(original_dir)
    
    -- Set breakpoint
    toggleBreakpoint:toggle()
    nio.sleep(20)
    
    -- Track events
    local breakpoint_hit = false
    local step_events = {}
    local thread_ref = nil
    
    -- Session listener
    api:onSession(function(session)
      if session.ref.id == 1 then return end
      
      session:onThread(function(thread)
        thread_ref = thread
        
        thread:onStopped(function(event)
          table.insert(step_events, { reason = event.reason, timestamp = os.clock() })
          print("STOPPED: " .. event.reason .. " (total events: " .. #step_events .. ")")
          
          if event.reason == "breakpoint" and not breakpoint_hit then
            breakpoint_hit = true
            print("BREAKPOINT HIT! Starting user mashing simulation...")
            
            -- Simulate user rapidly pressing keys in panic/confusion
            -- This simulates what happens when a user hits a breakpoint unexpectedly
            -- and starts mashing navigation keys
            
            -- Start an async task that simulates user key mashing
            nio.run(function()
              for i = 1, 20 do
                if thread_ref then
                  -- Random rapid key presses like a confused user
                  local commands = { "stepIn", "stepOut", "stepOver" }
                  local cmd = commands[math.random(#commands)]
                  
                  print("User mashing: " .. cmd .. " (iteration " .. i .. ")")
                  
                  -- Try to call the step function
                  local success, err = pcall(function()
                    if cmd == "stepIn" then
                      thread_ref:stepIn()
                    elseif cmd == "stepOut" then
                      thread_ref:stepOut()
                    else
                      thread_ref:stepOver()
                    end
                  end)
                  
                  if not success then
                    print("ERROR during step: " .. tostring(err))
                  end
                  
                  -- Very small delay to simulate rapid key presses
                  nio.sleep(10)
                end
              end
              
              -- After the mashing, try to access thread state
              nio.sleep(100)
              print("After mashing, trying to access thread state...")
              
              if thread_ref then
                local success, result = pcall(function()
                  local stack = thread_ref:stack()
                  if stack then
                    local top = stack:top()
                    return top and top.ref.line or "no line"
                  end
                  return "no stack"
                end)
                
                if not success then
                  print("CRASH/PREEMPTION when accessing thread state: " .. tostring(result))
                else
                  print("Thread state access successful: " .. tostring(result))
                end
              end
            end)
          end
          
          -- Also respond to step events
          if event.reason == "step" then
            print("Step event received, current thread valid: " .. tostring(thread_ref ~= nil))
            
            -- Try to access stack immediately after step
            if thread_ref then
              local success, result = pcall(function()
                local stack = thread_ref:stack()
                return stack and "stack ok" or "no stack"
              end)
              
              if not success then
                print("IMMEDIATE CRASH after step: " .. tostring(result))
              end
            end
          end
        end)
      end)
    end)
    
    -- Create session
    vim.api.nvim_set_current_dir(fixture_path)
    local workspace_info = launchJsonSupport:detectWorkspace(fixture_path)
    launchJsonSupport:createSessionFromConfig("Debug Loop []", api.manager, workspace_info)
    
    -- Wait for breakpoint
    vim.wait(5000, function() return breakpoint_hit end)
    
    -- Give time for the mashing and aftermath
    vim.wait(15000, function() return #step_events >= 10 end)
    
    nio.sleep(2000)
    
    print("FINAL SUMMARY:")
    print("- Breakpoint hit: " .. tostring(breakpoint_hit))
    print("- Total step events: " .. #step_events)
    print("- Thread reference valid: " .. tostring(thread_ref ~= nil))
    
    -- Print event timeline
    print("Event timeline:")
    for i, event in ipairs(step_events) do
      print("  " .. i .. ": " .. event.reason .. " at " .. event.timestamp)
    end
  end)

end)