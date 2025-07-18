local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local FrameHighlight = require("neodap.plugins.FrameHighlight")
local nio = require("nio")

Test.Describe("Simple Crash Test", function()

  Test.It("extreme_rapid_fire_navigation", function()
    local api = prepare()
    
    -- Load plugins
    local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)
    api:getPluginInstance(BreakpointApi)
    local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
    api:getPluginInstance(FrameHighlight)
    
    -- Use loop.js 
    local fixture_path = vim.fn.fnamemodify("spec/fixtures/workspaces/single-node-project", ":p")
    vim.cmd("edit " .. fixture_path .. "/loop.js")
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    
    -- Set breakpoint
    toggleBreakpoint:toggle()
    nio.sleep(20)
    
    -- Track everything
    local breakpoint_hit = false
    local thread_ref = nil
    local error_count = 0
    local preemption_count = 0
    
    -- Session listener
    api:onSession(function(session)
      if session.ref.id == 1 then return end
      
      session:onThread(function(thread)
        thread_ref = thread
        
        thread:onStopped(function(event)
          print("STOPPED: " .. event.reason)
          
          if event.reason == "breakpoint" and not breakpoint_hit then
            breakpoint_hit = true
            print("BREAKPOINT HIT - Starting EXTREME rapid fire test")
            
            -- Issue 1000 rapid commands to try to trigger issues
            for i = 1, 1000 do
              -- Try different combinations that might trigger race conditions
              local operations = {
                function()
                  if thread_ref then
                    thread_ref:stepIn()
                  end
                end,
                function()
                  if thread_ref then
                    thread_ref:stepOut()
                  end
                end,
                function()
                  if thread_ref then
                    thread_ref:stepOver()
                  end
                end,
                function()
                  if thread_ref then
                    local stack = thread_ref:stack()
                    if stack then
                      local top = stack:top()
                      if top then
                        local scopes = top:scopes()
                        if scopes and #scopes > 0 then
                          local vars = scopes[1]:variables()
                          -- Force evaluation of variables
                          if vars and #vars > 0 then
                            for _, var in ipairs(vars) do
                              if var.ref.variablesReference and var.ref.variablesReference > 0 then
                                var:variables()
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              }
              
              -- Execute all operations rapidly
              for _, op in ipairs(operations) do
                local success, err = pcall(op)
                if not success then
                  error_count = error_count + 1
                  local error_msg = tostring(err)
                  print("ERROR " .. error_count .. ": " .. error_msg)
                  
                  -- Check if this is a preemption-related error
                  if error_msg:find("preempt") or error_msg:find("destroyed") or error_msg:find("invalid") then
                    preemption_count = preemption_count + 1
                    print("PREEMPTION DETECTED: " .. error_msg)
                  end
                end
              end
              
              -- Print progress every 100 iterations
              if i % 100 == 0 then
                print("Completed " .. i .. " rapid fire iterations (errors: " .. error_count .. ", preemptions: " .. preemption_count .. ")")
              end
            end
            
            print("EXTREME RAPID FIRE COMPLETED")
            print("Total errors: " .. error_count)
            print("Total preemptions: " .. preemption_count)
            print("Thread reference still valid: " .. tostring(thread_ref ~= nil))
          end
        end)
      end)
    end)
    
    -- Create session
    local workspace_info = launchJsonSupport:detectWorkspace(fixture_path)
    launchJsonSupport:createSessionFromConfig("Debug Loop []", api.manager, workspace_info)
    
    -- Wait for breakpoint
    vim.wait(10000, function() return breakpoint_hit end)
    
    -- Allow extra time for the rapid fire to complete
    vim.wait(30000, function() return error_count > 0 or preemption_count > 0 end)
    
    nio.sleep(2000)
    
    print("FINAL RESULTS:")
    print("- Breakpoint hit: " .. tostring(breakpoint_hit))
    print("- Total errors: " .. error_count)
    print("- Preemptions: " .. preemption_count)
    print("- Thread valid: " .. tostring(thread_ref ~= nil))
    
    if preemption_count > 0 then
      print("SUCCESS: Reproduced preemption/crash conditions!")
    elseif error_count > 0 then
      print("PARTIAL: Found errors but no preemptions")
    else
      print("NO CRASHES: System handled extreme load well")
    end
  end)

end)