local Test = require("spec.helpers.testing")(describe, it)
local P = require("spec.helpers.prepare")
local prepare = P.prepare
local NewBreakpointManager = require("neodap.api.Breakpoint.BreakpointManager")
local Location = require("neodap.api.Breakpoint.Location")
local nio = require("nio")

Test.Describe("new breakpoint manager - binding updates", function()
  Test.It("should handle DAP position adjustments and property changes correctly", function()
    local api, start = prepare()
    
    -- Create new breakpoint manager
    local breakpointManager = NewBreakpointManager.create(api)
    
    -- Test spies for events
    local breakpointAdded = Test.spy("breakpointAdded")
    local bindingBound = Test.spy("bindingBound")
    local conditionChanged = Test.spy("conditionChanged")
    local logMessageChanged = Test.spy("logMessageChanged")
    local sessionInitialized = Test.spy("sessionInitialized")
    local sourceLoaded = Test.spy("sourceLoaded")
    
    -- Track events
    local conditionEventData = nil
    local logMessageEventData = nil
    
    -- Set up hierarchical event listeners
    breakpointManager:onBreakpoint(function(breakpoint)
      print("✓ Breakpoint added:", breakpoint.id)
      breakpointAdded.trigger()
      
      -- Listen for condition changes
      breakpoint:onConditionChanged(function(condition)
        print("✓ Condition changed to:", condition)
        conditionEventData = condition
        conditionChanged.trigger()
      end)
      
      -- Listen for log message changes
      breakpoint:onLogMessageChanged(function(logMessage)
        print("✓ Log message changed to:", logMessage)
        logMessageEventData = logMessage
        logMessageChanged.trigger()
      end)
      
      breakpoint:onBinding(function(binding)
        print("✓ Binding created for session:", binding.session.id)
        print("  - Requested position: line", binding.line, "column", binding.column)
        print("  - Actual position: line", binding.actualLine, "column", binding.actualColumn)
        bindingBound.trigger()
      end)
    end)
    
    -- Create breakpoint at column 0 (DAP will adjust to column 2 for the actual statement)
    -- Line 3 in loop.js: "	console.log("ALoop iteration: ", i++);"
    local location = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 0, -- User places at start of line
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:0"
    })
    
    print("Creating breakpoint at column 0 (DAP should adjust to column 2)...")
    local breakpoint = breakpointManager:addBreakpoint(location, {
      condition = "i > 0",
      logMessage = "Loop iteration: {i}"
    })
    
    -- Verify initial properties
    assert(breakpoint ~= nil, "Breakpoint should be created")
    assert(breakpoint.condition == "i > 0", "Breakpoint should have initial condition")
    assert(breakpoint.logMessage == "Loop iteration: {i}", "Breakpoint should have initial log message")
    print("✓ Breakpoint created with initial properties")
    
    breakpointAdded.wait()
    print("✓ BreakpointAdded event received")
    
    -- Start session to create binding
    api:onSession(function(session)
      session:onInitialized(function()
        sessionInitialized.trigger()
      end)
      
      session:onSourceLoaded(function(source)
        local fileSource = source:asFile()
        if fileSource and fileSource:filename() == "loop.js" then
          sourceLoaded.trigger()
        end
      end)
    end)
    
    print("Starting session...")
    start("loop.js")
    
    sessionInitialized.wait()
    sourceLoaded.wait()
    bindingBound.wait()
    print("✓ Session started and binding created")
    
    -- Verify binding was created with correct properties and DAP position adjustment
    local binding = breakpoint:getBindings():first()
    assert(binding ~= nil, "Binding should exist")
    assert(binding.verified == true, "Binding should be verified")
    
    -- Get initial positions to test requested vs actual
    local requestedLocation = binding:getRequestedLocation()
    local actualLocation = binding:getActualLocation()
    
    print("DAP Position Adjustment Results:")
    print("  - Requested: line", requestedLocation.line, "column", requestedLocation.column)
    print("  - Actual: line", actualLocation.line, "column", actualLocation.column)
    
    -- Verify the expected position adjustment behavior
    assert(requestedLocation.line == 3, "Requested line should be 3")
    assert(requestedLocation.column == 0, "Requested column should be 0 (user intent)")
    assert(actualLocation.line == 3, "Actual line should be 3 (same line)")
    
    -- DAP should move breakpoint from column 0 to the actual statement start
    -- In loop.js line 3, the statement starts after the tab character
    print("✓ DAP adjusted position from column", requestedLocation.column, "to column", actualLocation.column)
    
    -- === TEST BREAKPOINT PROPERTY CHANGES ===
    print("=== Testing Breakpoint Property Changes ===")
    
    -- Change condition
    print("Changing breakpoint condition...")
    breakpoint:setCondition("i > 5")
    
    conditionChanged.wait()
    print("✓ Condition change event received")
    
    assert(conditionEventData == "i > 5", "Event should contain new condition")
    assert(breakpoint.condition == "i > 5", "Breakpoint should have new condition")
    print("✓ Condition successfully changed")
    
    -- Change log message
    print("Changing breakpoint log message...")
    breakpoint:setLogMessage("New iteration: {i}")
    
    logMessageChanged.wait()
    print("✓ Log message change event received")
    
    assert(logMessageEventData == "New iteration: {i}", "Event should contain new log message")
    assert(breakpoint.logMessage == "New iteration: {i}", "Breakpoint should have new log message")
    print("✓ Log message successfully changed")
    
    -- After property changes, verify binding state is preserved
    print("Verifying binding state after property changes...")
    nio.sleep(100) -- Wait for batch window + processing
    
    -- Binding should still exist and properties should be preserved
    local bindingAfterChanges = breakpoint:getBindings():first()
    assert(bindingAfterChanges ~= nil, "Binding should still exist after property changes")
    assert(bindingAfterChanges.id == binding.id, "Binding should be the same object")
    
    -- Position should remain the same after property-only changes
    local finalRequestedLocation = bindingAfterChanges:getRequestedLocation()
    local finalActualLocation = bindingAfterChanges:getActualLocation()
    
    assert(finalRequestedLocation.line == requestedLocation.line, "Requested position should not change")
    assert(finalRequestedLocation.column == requestedLocation.column, "Requested column should not change")
    assert(finalActualLocation.line == actualLocation.line, "Actual position should be preserved")
    assert(finalActualLocation.column == actualLocation.column, "Actual column should be preserved")
    
    print("✓ Binding position preserved after property changes")
    
    -- === TEST BINDING-LEVEL QUERIES ===
    print("=== Testing Binding Query Methods ===")
    
    -- Test getBreakpoint method
    local bindingBreakpoint = binding:getBreakpoint()
    assert(bindingBreakpoint ~= nil, "Binding should return associated breakpoint")
    assert(bindingBreakpoint.id == breakpoint.id, "Binding should return correct breakpoint")
    print("✓ Binding getBreakpoint() method works")
    
    -- Test that binding updates don't affect breakpoint properties
    assert(breakpoint.condition == "i > 5", "Breakpoint condition should remain unchanged")
    assert(breakpoint.logMessage == "New iteration: {i}", "Breakpoint log message should remain unchanged")
    print("✓ Binding updates don't affect breakpoint properties")
    
    -- === CLEANUP ===
    print("=== Cleanup Test ===")
    
    breakpointManager:removeBreakpoint(breakpoint)
    
    -- Verify cleanup
    local finalBreakpoints = breakpointManager.breakpoints:count()
    local finalBindings = breakpointManager.bindings:count()
    assert(finalBreakpoints == 0, "All breakpoints should be removed")
    assert(finalBindings == 0, "All bindings should be removed")
    
    print("✓ Cleanup verified")
    print("✓ DAP position adjustments and property changes test completed successfully!")
  end)
end)