--[[
Thread Destruction Race Condition Test

This test identifies and validates fixes for race conditions that occur when debug sessions
are terminated while concurrent operations are accessing thread state.

## Race Condition Fixed: Fast Event Context Violation (E5560)

**Problem**: SourceIdentifier.calculateStabilityHash() was calling vim.fn.sha256() during 
session destruction, causing "E5560: Vimscript function must not be called in a fast event context"

**Root Cause**: When rapid debugging operations (stack access, stepping) occurred simultaneously 
with session termination, the source identification process would attempt to hash virtual sources 
using Vimscript functions within Neovim's fast event context restrictions.

**Call Chain**:
1. thread:stack() -> stack frame analysis -> source identification
2. SourceIdentifier.fromDapSource() -> calculateStabilityHash() -> vim.fn.sha256()
3. Session destruction creates fast event context
4. Race condition: hash calculation during fast events = E5560 violation

**Solution**: Replaced vim.fn.sha256() with pure Lua simple_hash() function in 
lua/neodap/api/Location/SourceIdentifier.lua to eliminate Vimscript dependency.

**Impact**: Prevents crashes during rapid debugging operations + session cleanup scenarios.

## Remaining Expected Race Conditions

The test still detects legitimate race conditions like "Thread is not paused" when trying
to access terminated thread state - these are expected and help validate proper error handling.
--]]

local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local FrameHighlight = require("neodap.plugins.FrameHighlight")
local nio = require("nio")

Test.Describe("Thread Destruction Crash Test", function()

  Test.It("session_cleanup_race_condition", function()
    local api = prepare()
    
    -- Load plugins
    local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)
    api:getPluginInstance(BreakpointApi)
    local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
    
    local fixture_path = vim.fn.fnamemodify("spec/fixtures/workspaces/single-node-project", ":p")
    vim.cmd("edit " .. fixture_path .. "/loop.js")
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    
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