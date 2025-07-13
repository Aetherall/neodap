local Test = require("spec.helpers.testing")(describe, it)
local P = require("spec.helpers.prepare")
local prepare = P.prepare
local NewBreakpointManager = require("neodap.api.Breakpoint.BreakpointManager")
local Location = require("neodap.api.Breakpoint.Location")
local nio = require("nio")

Test.Describe("breakpoint toggle with position range matching", function()
  Test.It("should match breakpoint at any position between original and adjusted locations", function()
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
    local originalLocation = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 0,  -- User places at start of line
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:0"
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
    
    -- Test toggling at various positions between original and adjusted
    local minCol = math.min(requestedLocation.column or 0, actualLocation.column or 0)
    local maxCol = math.max(requestedLocation.column or 0, actualLocation.column or 0)
    
    print("=== Testing Position Range Matching ===")
    print("Range: column", minCol, "to", maxCol)
    
    -- Test each position in the range
    for col = minCol, maxCol do
      local testLocation = Location.SourceFile:new({
        path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
        line = 3,
        column = col,
        key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:" .. col
      })
      
      print("Testing toggle at column", col)
      
      -- Count breakpoints before toggle
      local breakpointsBeforeToggle = breakpointManager.breakpoints:count()
      assert(breakpointsBeforeToggle == 1, "Should have 1 breakpoint before toggle")
      
      -- Perform the toggle
      local toggleResult = breakpointManager:toggleBreakpoint(testLocation)
      
      -- Should find and remove the existing breakpoint
      assert(toggleResult == nil, "Toggle should return nil when removing an existing breakpoint at column " .. col)
      
      local breakpointsAfterToggle = breakpointManager.breakpoints:count()
      assert(breakpointsAfterToggle == 0, "Should have 0 breakpoints after toggle removes breakpoint at column " .. col)
      
      print("✓ Successfully toggled breakpoint at column", col)
      
      -- Re-create the breakpoint for next iteration (except on last iteration)
      if col < maxCol then
        print("Re-creating breakpoint for next test...")
        breakpoint = breakpointManager:addBreakpoint(originalLocation)
        
        -- Wait for the binding to be established again
        local bindingReady = Test.spy("bindingReady")
        breakpoint:onBinding(function(_binding)
          bindingReady.trigger()
        end)
        bindingReady.wait()
        nio.sleep(100) -- Brief wait for binding to stabilize
      end
    end
    
    print("=== Testing Positions Outside Range ===")
    
    -- Re-create breakpoint for out-of-range tests
    print("Re-creating breakpoint for out-of-range tests...")
    breakpoint = breakpointManager:addBreakpoint(originalLocation)
    nio.sleep(200)
    
    -- Test position before the range (should NOT match)
    if minCol > 0 then
      local beforeLocation = Location.SourceFile:new({
        path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
        line = 3,
        column = minCol - 1,
        key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:" .. (minCol - 1)
      })
      
      print("Testing position before range at column", minCol - 1)
      local breakpointsBeforeToggle = breakpointManager.breakpoints:count()
      local toggleResult = breakpointManager:toggleBreakpoint(beforeLocation)
      local breakpointsAfterToggle = breakpointManager.breakpoints:count()
      
      -- Should NOT find the breakpoint and should create a new one
      assert(toggleResult ~= nil, "Toggle should create new breakpoint when position is outside range")
      assert(breakpointsAfterToggle == 2, "Should have 2 breakpoints after toggle creates new one")
      
      print("✓ Correctly did NOT match breakpoint at column", minCol - 1)
      
      -- Clean up the extra breakpoint
      breakpointManager:removeBreakpoint(toggleResult)
    end
    
    -- Test position after the range (should NOT match)
    local afterLocation = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = maxCol + 1,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:" .. (maxCol + 1)
    })
    
    print("Testing position after range at column", maxCol + 1)
    local breakpointsBeforeToggle = breakpointManager.breakpoints:count()
    local toggleResult = breakpointManager:toggleBreakpoint(afterLocation)
    local breakpointsAfterToggle = breakpointManager.breakpoints:count()
    
    -- Should NOT find the breakpoint and should create a new one
    assert(toggleResult ~= nil, "Toggle should create new breakpoint when position is outside range")
    assert(breakpointsAfterToggle == 2, "Should have 2 breakpoints after toggle creates new one")
    
    print("✓ Correctly did NOT match breakpoint at column", maxCol + 1)
    
    print("✓ Position range matching test completed successfully!")
  end)
end)
