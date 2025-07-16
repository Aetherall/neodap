local Test = require("spec.helpers.testing")(describe, it)
local P = require("spec.helpers.prepare")
local prepare = P.prepare
local NewBreakpointManager = require("neodap.plugins.BreakpointApi.BreakpointManager")
local Location = require("neodap.api.Location")
local SourceIdentifier = require("neodap.api.Location.SourceIdentifier")
local nio = require("nio")

Test.Describe("breakpoint cross line toggle", function()
  Test.It("should toggle breakpoint adjusted to different line", function()
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
        print("✓ Binding created - requested:", binding.line, binding.column, "actual:", binding.actualLine, binding.actualColumn)
        bindingBound.trigger()
      end)
    end)
    
    -- Create breakpoint at line 3, column 0 (will be moved to line 4, column 2 by DAP)
    local originalLocation = Location.create({
      sourceId = SourceIdentifier.fromPath(vim.fn.getcwd() .. "/spec/fixtures/loop.js"),
      line = 3,
      column = 0
    })
    
    print("Creating breakpoint at:", originalLocation.key)
    local breakpoint = breakpointManager:addBreakpoint(originalLocation)
    breakpointAdded.wait()
    
    -- Start session
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
    
    start("loop.js")
    sessionInitialized.wait()
    sourceLoaded.wait()
    bindingBound.wait()
    
    -- Simulate DAP adjusting the breakpoint to next line
    local binding = breakpoint:getBindings():first()
    if binding then
      binding.actualLine = 4
      binding.actualColumn = 2
    end
    
    print("Breakpoint adjusted from line 3 column 0 to line 4 column 2")
    
    -- Test that we can toggle at the middle of a line between original and adjusted
    local middleLocation = Location.create({
      sourceId = SourceIdentifier.fromPath(vim.fn.getcwd() .. "/spec/fixtures/loop.js"),
      line = 3,
      column = 5  -- Later on the original line
    })

    print("=== Testing Toggle at Middle Position (Line 3, Column 5) ===")
    print("Toggling at:", middleLocation.key)
    local initialBreakpoints = breakpointManager.breakpoints:atLocation(originalLocation)
    print("Breakpoints before toggle:", initialBreakpoints:count())

    -- Toggle at the middle position should remove the breakpoint
    local result = breakpointManager:toggleBreakpoint(middleLocation)
    
    local remainingBreakpoints = breakpointManager.breakpoints:atLocation(originalLocation)
    print("Breakpoints after toggle:", remainingBreakpoints:count())
    
    if result == nil then
      print("Toggle result: existing breakpoint removed")
    else
      print("Toggle result: new breakpoint created")
    end
    
    assert(remainingBreakpoints:count() == 0, "Breakpoint should have been removed")
    print("✓ Successfully toggled breakpoint at cross-line middle position!")
  end)
end)
