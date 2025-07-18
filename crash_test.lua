-- Manual crash reproduction test
-- Run this in the playground: make play

local LaunchJsonSupport = require("neodap.plugins.LaunchJsonSupport")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local FrameHighlight = require("neodap.plugins.FrameHighlight")
local nio = require("nio")

-- Create API instance
local Manager = require("neodap.session.manager")
local Api = require("neodap.api.Api")
local manager = Manager.create()
local api = Api.register(manager)

-- Load plugins
local launchJsonSupport = api:getPluginInstance(LaunchJsonSupport)
api:getPluginInstance(BreakpointApi)
local toggleBreakpoint = api:getPluginInstance(ToggleBreakpoint)
api:getPluginInstance(FrameHighlight)

print("CRASH TEST - Setting up debugging session...")

-- Open test file
local fixture_path = vim.fn.fnamemodify("spec/fixtures/workspaces/single-node-project", ":p")
vim.api.nvim_set_current_dir(fixture_path)
vim.cmd("edit loop.js")
vim.api.nvim_win_set_cursor(0, { 3, 0 })

-- Set breakpoint
toggleBreakpoint:toggle()

local thread_ref = nil
local session_ref = nil

-- Session listener
api:onSession(function(session)
  if session.ref.id == 1 then return end
  session_ref = session
  print("Session " .. session.ref.id .. " started")
  
  session:onThread(function(thread)
    thread_ref = thread
    print("Thread " .. thread.ref.id .. " started")
    
    thread:onStopped(function(event)
      print("THREAD STOPPED: " .. event.reason)
      
      if event.reason == "breakpoint" then
        print("BREAKPOINT HIT!")
        print("Now you can manually test key mashing...")
        print("Try these commands rapidly:")
        print("  thread_ref:stepIn()")
        print("  thread_ref:stepOut()")
        print("  thread_ref:stepOver()")
        print("  thread_ref:stack()")
        print("  session_ref:destroy()")
        print("")
        print("Look for preemption messages or crashes in the output!")
      end
    end)
  end)
end)

-- Create session
local workspace_info = launchJsonSupport:detectWorkspace(fixture_path)
launchJsonSupport:createSessionFromConfig("Debug Loop []", api.manager, workspace_info)

print("Session created. Waiting for breakpoint hit...")
print("After hitting breakpoint, you can manually test rapid commands:")
print("  - Try calling thread_ref:stepIn() multiple times rapidly")
print("  - Try accessing thread_ref:stack() while stepping")
print("  - Try calling session_ref:destroy() while operations are running")
print("")
print("Watch for:")
print("  - Preemption messages")
print("  - Hookable destruction errors")
print("  - Thread reference becoming invalid")
print("  - Race conditions during cleanup")