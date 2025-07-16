local Test = require("spec.helpers.testing")(describe, it)
local P = require("spec.helpers.prepare")
local prepare = P.prepare
local NewBreakpointManager = require("neodap.plugins.BreakpointApi.BreakpointManager")
local Location = require("neodap.api.Location")
local SourceIdentifier = require("neodap.api.Location.SourceIdentifier")
local nio = require("nio")

Test.Describe("breakpoint toggle with adjusted position", function()
  Test.It("should toggle adjusted breakpoint by visual position", function()
    local api, start = prepare()
    
    -- Create new breakpoint manager
    local breakpointManager = NewBreakpointManager.create(api)
    
    local breakpointAdded = Test.spy("breakpointAdded")
    local bindingBound = Test.spy("bindingBound")
    local sessionInitialized = Test.spy("sessionInitialized")
    local sourceLoaded = Test.spy("sourceLoaded")
    
    -- Track the created breakpoint
    local createdBreakpoint = nil
    
    breakpointManager:onBreakpoint(function(breakpoint)
      print("✓ Breakpoint added:", breakpoint.id)
      createdBreakpoint = breakpoint
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
      column = 0  -- User places at start of line
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
    
    -- Verify binding was created and moved
    local binding = breakpoint:getBindings():first()
    assert(binding ~= nil, "Binding should exist")
    assert(binding.verified == true, "Binding should be verified")
    
    local requestedLocation = binding:getRequestedLocation()
    local actualLocation = binding:getActualLocation()
    
    print("Position verification:")
    print("  - Requested: line", requestedLocation.line, "column", requestedLocation.column)
    print("  - Actual: line", actualLocation.line, "column", actualLocation.column)
    
    -- Ensure the breakpoint was actually moved by DAP
    assert(actualLocation.column ~= requestedLocation.column, "DAP should have moved the breakpoint column")
    print("✓ DAP adjusted breakpoint from column", requestedLocation.column, "to column", actualLocation.column)
    
    -- Now try to toggle the breakpoint using the VISUAL position (where it appears)
    print("=== Testing Toggle Using Visual Position ===")
    
    -- Create location based on where the breakpoint visually appears
    local visualLocation = Location.create({
      sourceId = SourceIdentifier.fromPath(vim.fn.getcwd() .. "/spec/fixtures/loop.js"),
      line = actualLocation.line,
      column = actualLocation.column  -- Use the actual adjusted position
    })
    
    print("Attempting to toggle breakpoint at visual location:", visualLocation.key)
    print("Original breakpoint location:", originalLocation.key)
    
    -- Count breakpoints before toggle
    local breakpointsBeforeToggle = breakpointManager.breakpoints:count()
    print("Breakpoints before toggle:", breakpointsBeforeToggle)
    
    -- Perform the toggle using visual position
    local toggleResult = breakpointManager:toggleBreakpoint(visualLocation)
    
    -- The toggle should find and remove the existing breakpoint, not create a new one
    assert(toggleResult == nil, "Toggle should return nil when removing an existing breakpoint")
    
    local breakpointsAfterToggle = breakpointManager.breakpoints:count()
    print("Breakpoints after toggle:", breakpointsAfterToggle)
    
    assert(breakpointsAfterToggle == 0, "Should have 0 breakpoints after toggle removes the adjusted breakpoint")
    
    print("✓ Successfully toggled breakpoint using visual position")
    print("✓ Adjusted breakpoint toggle test completed successfully!")
  end)
end)
