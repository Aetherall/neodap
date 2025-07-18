local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local FrameHighlight = require("neodap.plugins.FrameHighlight")
local nio = require("nio")

Test.Describe("Thread Destruction Crash Test", function()

  Test.It("trigger_thread_destruction_during_navigation", function()
    local original_dir = vim.fn.getcwd()
    local api = prepare()
    
    -- Load plugins
    local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)
    api:getPluginInstance(BreakpointApi)
    local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
    api:getPluginInstance(FrameHighlight)
    
    -- Use recurse.js but modify the timeout to be very short
    local fixture_path = vim.fn.fnamemodify("spec/fixtures/workspaces/single-node-project", ":p")
    vim.api.nvim_set_current_dir(fixture_path)
    vim.cmd("edit recurse.js")
    vim.api.nvim_win_set_cursor(0, { 7, 0 })  -- Line with setTimeout
    vim.api.nvim_set_current_dir(original_dir)
    
    -- Set breakpoint on the setTimeout line
    toggleBreakpoint:toggle()
    nio.sleep(20)
    
    -- Track everything
    local breakpoint_hit = false
    local thread_ref = nil
    local crashes = {}
    local terminated = false
    
    -- Session listener
    api:onSession(function(session)
      if session.ref.id == 1 then return end
      
      -- Listen for session termination
      session:onTerminated(function()
        terminated = true
        print("SESSION TERMINATED!")
        
        -- Try to access thread after termination
        if thread_ref then
          local success, err = pcall(function()
            local stack = thread_ref:stack()
            return stack and "stack exists" or "no stack"
          end)
          
          if not success then
            table.insert(crashes, { type = "post_termination", error = tostring(err) })
            print("CRASH AFTER SESSION TERMINATION: " .. tostring(err))
          end
        end
      end)
      
      session:onThread(function(thread)
        thread_ref = thread
        
        -- Listen for thread events
        thread:onStopped(function(event)
          print("THREAD STOPPED: " .. event.reason)
          
          if event.reason == "breakpoint" and not breakpoint_hit then
            breakpoint_hit = true
            print("BREAKPOINT HIT! Starting aggressive navigation...")
            
            -- Start aggressive navigation that might trigger thread destruction
            nio.run(function()
              for i = 1, 30 do
                if thread_ref and not terminated then
                  -- Try multiple rapid operations
                  local ops = {
                    function() thread_ref:stepIn() end,
                    function() thread_ref:stepOut() end,
                    function() thread_ref:stepOver() end,
                    function() 
                      local stack = thread_ref:stack()
                      if stack then
                        local top = stack:top()
                        if top then
                          local scopes = top:scopes()
                          -- Try to access variables
                          if scopes and #scopes > 0 then
                            scopes[1]:variables()
                          end
                        end
                      end
                    end
                  }
                  
                  -- Execute random operations
                  for _, op in ipairs(ops) do
                    local success, err = pcall(op)
                    if not success then
                      table.insert(crashes, { type = "during_navigation", error = tostring(err) })
                      print("CRASH DURING NAVIGATION: " .. tostring(err))
                    end
                  end
                  
                  -- Very short delay
                  nio.sleep(5)
                else
                  break
                end
              end
              
              print("Navigation spam completed")
            end)
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
    
    -- Wait for potential crashes or termination
    vim.wait(10000, function() return terminated or #crashes > 0 end)
    
    nio.sleep(1000)
    
    print("FINAL RESULTS:")
    print("- Breakpoint hit: " .. tostring(breakpoint_hit))
    print("- Session terminated: " .. tostring(terminated))
    print("- Crashes detected: " .. #crashes)
    print("- Thread reference valid: " .. tostring(thread_ref ~= nil))
    
    if #crashes > 0 then
      print("CRASHES FOUND!")
      for i, crash in ipairs(crashes) do
        print("  " .. i .. ": " .. crash.type .. " - " .. crash.error)
      end
    else
      print("No crashes detected")
    end
  end)

  Test.It("session_cleanup_race_condition", function()
    local original_dir = vim.fn.getcwd()
    local api = prepare()
    
    -- Load plugins
    local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)
    api:getPluginInstance(BreakpointApi)
    local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
    
    local fixture_path = vim.fn.fnamemodify("spec/fixtures/workspaces/single-node-project", ":p")
    vim.api.nvim_set_current_dir(fixture_path)
    vim.cmd("edit loop.js")
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.api.nvim_set_current_dir(original_dir)
    
    toggleBreakpoint:toggle()
    nio.sleep(20)
    
    local session_ref = nil
    local thread_ref = nil
    local crashes = {}
    
    -- Session listener
    api:onSession(function(session)
      if session.ref.id == 1 then return end
      session_ref = session
      
      session:onThread(function(thread)
        thread_ref = thread
        
        thread:onStopped(function(event)
          if event.reason == "breakpoint" then
            print("BREAKPOINT HIT - Starting session cleanup race test")
            
            -- Start concurrent operations
            nio.run(function()
              -- Thread 1: Try to access thread state repeatedly
              for i = 1, 50 do
                if thread_ref then
                  local success, err = pcall(function()
                    local stack = thread_ref:stack()
                    if stack then
                      local top = stack:top()
                      return top and "frame ok" or "no frame"
                    end
                    return "no stack"
                  end)
                  
                  if not success then
                    table.insert(crashes, { type = "stack_access", error = tostring(err) })
                    print("CRASH accessing stack: " .. tostring(err))
                  end
                end
                nio.sleep(1)
              end
            end)
            
            nio.run(function()
              -- Thread 2: Try to step repeatedly
              for i = 1, 50 do
                if thread_ref then
                  local success, err = pcall(function()
                    thread_ref:stepOver()
                  end)
                  
                  if not success then
                    table.insert(crashes, { type = "step_command", error = tostring(err) })
                    print("CRASH during step: " .. tostring(err))
                  end
                end
                nio.sleep(1)
              end
            end)
            
            -- Thread 3: Terminate session while operations are running
            nio.run(function()
              nio.sleep(100)  -- Let other operations start
              if session_ref then
                print("TERMINATING SESSION WHILE OPERATIONS ARE RUNNING")
                local success, err = pcall(function()
                  session_ref:destroy()
                end)
                
                if not success then
                  table.insert(crashes, { type = "session_destruction", error = tostring(err) })
                  print("CRASH during session destruction: " .. tostring(err))
                end
              end
            end)
          end
        end)
      end)
    end)
    
    -- Create session
    vim.api.nvim_set_current_dir(fixture_path)
    local workspace_info = launchJsonSupport:detectWorkspace(fixture_path)
    launchJsonSupport:createSessionFromConfig("Debug Loop []", api.manager, workspace_info)
    
    -- Wait for operations to complete
    vim.wait(5000, function() return #crashes > 0 end)
    
    nio.sleep(2000)
    
    print("RACE CONDITION TEST RESULTS:")
    print("- Crashes detected: " .. #crashes)
    
    if #crashes > 0 then
      print("RACE CONDITIONS FOUND!")
      for i, crash in ipairs(crashes) do
        print("  " .. i .. ": " .. crash.type .. " - " .. crash.error)
      end
    end
  end)

end)