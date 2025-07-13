local Test = require("spec.helpers.testing")(describe, it)
local P = require("spec.helpers.prepare")
local prepare = P.prepare
local NewBreakpointManager = require("neodap.api.Breakpoint.BreakpointManager")
local Location = require("neodap.api.Breakpoint.Location")
local nio = require("nio")

Test.Describe("smart breakpoint placement", function()
  Test.It("should prevent duplicate breakpoints when DAP adjusts position", function()
    local api, start = prepare()
    
    -- Create new breakpoint manager
    local breakpointManager = NewBreakpointManager.create(api)
    
    local sessionInitialized = Test.spy("sessionInitialized")
    local sourceLoaded = Test.spy("sourceLoaded")
    local firstBreakpointAdded = Test.spy("firstBreakpointAdded")
    local secondBreakpointAttempted = Test.spy("secondBreakpointAttempted")
    
    -- Track breakpoint additions
    breakpointManager:onBreakpoint(function(breakpoint)
      print("✓ Breakpoint added:", breakpoint.id)
      firstBreakpointAdded.trigger()
    end, { once = true })
    
    -- Set up session event tracking
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
    
    -- Create first breakpoint at column 0 (will be adjusted by DAP to column 2)
    local location1 = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 0,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:0"
    })
    
    print("Creating first breakpoint at column 0...")
    local breakpoint1 = breakpointManager:addBreakpoint(location1)
    assert(breakpoint1 ~= nil, "First breakpoint should be created")
    
    firstBreakpointAdded.wait()
    print("✓ First breakpoint created")
    
    -- Start session to trigger DAP adjustment
    start("loop.js")
    sessionInitialized.wait()
    sourceLoaded.wait()
    
    -- Wait for binding to be created with actual DAP position
    nio.sleep(500)
    
    local bindings1 = breakpoint1:getBindings()
    if bindings1:count() > 0 then
      local binding1 = bindings1:first()
      if binding1 then
        print("✓ First breakpoint bound at actual position:", binding1.actualLine, binding1.actualColumn)
      end
    end
    
    -- Now try to create second breakpoint at column 2 (where DAP actually placed the first one)
    local location2 = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 2,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:2"
    })
    
    print("Attempting to create second breakpoint at column 2...")
    local breakpoint2 = breakpointManager:addBreakpoint(location2)
    
    -- Smart placement should prevent this duplicate
    if breakpoint2 == nil then
      print("✓ Smart placement correctly prevented duplicate breakpoint")
    elseif breakpoint1 and breakpoint2.id == breakpoint1.id then
      print("✓ Smart placement returned existing breakpoint instead of creating duplicate")
    else
      -- This should not happen if smart placement is working correctly
      local id = breakpoint2 and breakpoint2.id or "nil"
      error("Smart placement failed: unexpected result - breakpoint2 id: " .. id)
    end
    
    -- Verify we still only have one breakpoint
    local totalBreakpoints = breakpointManager.breakpoints:count()
    assert(totalBreakpoints == 1, "Should still have only 1 breakpoint, found: " .. totalBreakpoints)
    
    print("✓ Smart breakpoint placement test passed")
  end)

  Test.It("should use breakpointLocations when session is active", function()
    local api, start = prepare()
    
    local breakpointManager = NewBreakpointManager.create(api)
    
    local sessionInitialized = Test.spy("sessionInitialized")
    local sourceLoaded = Test.spy("sourceLoaded")
    local breakpointAdded = Test.spy("breakpointAdded")
    
    -- Track breakpoint creation
    breakpointManager:onBreakpoint(function(breakpoint)
      print("✓ Breakpoint created at:", breakpoint.location.key)
      breakpointAdded.trigger()
    end)
    
    -- Start session first so breakpointLocations is available
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
    
    start("loop.js")
    sessionInitialized.wait()
    sourceLoaded.wait()
    
    -- Now create a breakpoint - smart placement should use breakpointLocations
    local location = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 1,  -- Slightly off from valid position
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:1"
    })
    
    print("Creating breakpoint with session active (should use breakpointLocations)...")
    local breakpoint = breakpointManager:addBreakpoint(location)
    
    if breakpoint then
      print("✓ Breakpoint created at smart-adjusted location:", breakpoint.location.key)
      -- The smart placement should have adjusted the position based on breakpointLocations
      assert(breakpoint.location.column == 0 or breakpoint.location.column == 2, 
             "Smart placement should adjust to valid column position")
    else
      error("Smart placement failed to create breakpoint")
    end
    
    print("✓ breakpointLocations integration test passed")
  end)

  Test.It("should fallback to line start when no session active", function()
    local api, _start = prepare()
    
    local breakpointManager = NewBreakpointManager.create(api)
    
    -- Create breakpoint without any active session
    local location = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 5,  -- Some arbitrary column
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:5"
    })
    
    print("Creating breakpoint without active session (should fallback to column 0)...")
    local breakpoint = breakpointManager:addBreakpoint(location)
    
    assert(breakpoint ~= nil, "Breakpoint should be created")
    assert(breakpoint.location.column == 0, 
           "Smart placement should fallback to column 0, got: " .. breakpoint.location.column)
    
    print("✓ Fallback to line start test passed")
  end)

  Test.It("should move breakpoint from middle of console_log to statement start", function()
    local api, start = prepare()
    
    local breakpointManager = NewBreakpointManager.create(api)
    
    local sessionInitialized = Test.spy("sessionInitialized")
    local sourceLoaded = Test.spy("sourceLoaded")
    local breakpointAdded = Test.spy("breakpointAdded")
    
    -- Track breakpoint creation
    breakpointManager:onBreakpoint(function(breakpoint)
      print("✓ Breakpoint created at:", breakpoint.location.key)
      breakpointAdded.trigger()
    end)
    
    -- Start session first so breakpointLocations is available
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
    
    start("loop.js")
    sessionInitialized.wait()
    sourceLoaded.wait()
    
    -- Wait a bit for breakpointLocations to be available
    nio.sleep(200)
    
    -- Create a breakpoint in the middle of "console.log" on line 3
    -- Line 3: "\tconsole.log("ALoop iteration: ", i++);"
    -- Column 7 would be roughly at the 'o' in "console"
    local location = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 7,  -- Middle of "console.log"
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:7"
    })
    
    print("Creating breakpoint at column 7 (middle of console.log)...")
    local breakpoint = breakpointManager:addBreakpoint(location)
    
    assert(breakpoint ~= nil, "Breakpoint should be created")
    
    -- Wait for the binding to be established so we can see where DAP actually placed it
    breakpointAdded.wait()
    nio.sleep(300)
    
    -- Check where the breakpoint was actually placed
    print("Breakpoint location after smart placement:", breakpoint.location.line, breakpoint.location.column)
    
    -- The breakpoint should have been moved to the start of the statement
    -- In JavaScript, this would typically be at the beginning of "console" (column 1 after tab)
    -- or at the very beginning of the line (column 0)
    local validColumns = {0, 1, 2}  -- Allow for various indentation interpretations
    local isValidColumn = false
    for _, validCol in ipairs(validColumns) do
      if breakpoint.location.column == validCol then
        isValidColumn = true
        break
      end
    end
    
    assert(isValidColumn, 
           "Smart placement should move to statement start (column 0, 1, or 2), got column: " .. breakpoint.location.column)
    
    -- Verify that the breakpoint is not at the original requested column
    assert(breakpoint.location.column ~= 7, 
           "Breakpoint should have been moved from original column 7")
    
    print("✓ Smart placement correctly moved breakpoint from middle of console.log to statement start")
    
    -- Optional: Check the actual binding position after DAP response
    local bindings = breakpoint:getBindings()
    if bindings:count() > 0 then
      local binding = bindings:first()
      if binding then
        print("✓ DAP bound breakpoint at actual position:", binding.actualLine, binding.actualColumn)
        -- The actual binding position should be at a valid breakable location
        assert(binding.actualLine == 3, "Binding should be on line 3")
      end
    end
  end)
end)
