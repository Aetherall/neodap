local Test = require("spec.helpers.testing")(describe, it)
local P = require("spec.helpers.prepare")
local prepare = P.prepare
local NewBreakpointManager = require("neodap.plugins.BreakpointApi.BreakpointManager")
local Location = require("neodap.api.Location")
local SourceIdentifier = require("neodap.api.Location.SourceIdentifier")
local nio = require("nio")

Test.Describe("breakpoint range matching debug", function()
  Test.It("should test range matching with debug output", function()
    local api, start = prepare()
    
    -- Create new breakpoint manager
    local breakpointManager = NewBreakpointManager.create(api)
    
    local breakpointAdded = Test.spy("breakpointAdded")
    local bindingBound = Test.spy("bindingBound")
    local sessionInitialized = Test.spy("sessionInitialized")
    local sourceLoaded = Test.spy("sourceLoaded")
    
    breakpointManager:onBreakpoint(function(breakpoint)
      print("✓ Breakpoint added:", breakpoint.id)
      breakpointAdded.trigger()
      
      breakpoint:onBinding(function(binding)
        print("✓ Binding created for session:", binding.session.id)
        print("  - Requested position: line", binding.line, "column", binding.column)
        print("  - Actual position: line", binding.actualLine, "column", binding.actualColumn)
        bindingBound.trigger()
      end)
    end)
    
    -- Create breakpoint at column 0 (will be moved to column 2 by DAP)
    local originalLocation = Location.create({
      sourceId = SourceIdentifier.fromPath(vim.fn.getcwd() .. "/spec/fixtures/loop.js"),
      line = 3,
      column = 0
    })
    
    print("Creating breakpoint at original location:", originalLocation.key)
    local breakpoint = breakpointManager:addBreakpoint(originalLocation)
    breakpointAdded.wait()
    
    -- Start session to create binding and trigger DAP adjustment
    api:onSession(function(session)
      session:onInitialized(function()
        sessionInitialized.trigger()
      end)
      
      session:onSourceLoaded(function(source)
        if source:isFile() and source:filename() == "loop.js" then
          sourceLoaded.trigger()
        end
      end)
    end)
    
    print("Starting session...")
    start("loop.js")
    
    sessionInitialized.wait()
    sourceLoaded.wait()
    bindingBound.wait()
    
    -- Give time for binding to establish with adjusted position
    nio.sleep(200)
    
    -- Test range matching at column 1 (between 0 and 2)
    local testLocation = Location.create({
      sourceId = SourceIdentifier.fromPath(vim.fn.getcwd() .. "/spec/fixtures/loop.js"),
      line = 3,
      column = 1
    })
    
    print("=== Testing Range Matching at Column 1 ===")
    print("Looking for breakpoint at:", testLocation.key)
    
    -- Test the atLocation method directly
    local foundBreakpoints = breakpointManager.breakpoints:atLocation(testLocation)
    print("Found", foundBreakpoints:count(), "breakpoints")
    
    if foundBreakpoints:count() > 0 then
      print("✓ Range matching works!")
    else
      print("✗ Range matching failed")
    end
    
    print("✓ Range matching debug test completed!")
  end)
end)
