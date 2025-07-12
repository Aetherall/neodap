local Test = require("spec.helpers.testing")(describe, it)
local P = require("spec.helpers.prepare")
local prepare = P.prepare
local NewBreakpointManager = require("neodap.api.Breakpoint.BreakpointManager")
local Location = require("neodap.api.Breakpoint.Location")
local nio = require("nio")

Test.Describe("new breakpoint manager - toggle functionality", function()
  Test.It("should toggle breakpoints on and off correctly", function()
    local api, start = prepare()
    
    -- Create new breakpoint manager
    local breakpointManager = NewBreakpointManager.create(api)
    
    -- Create location for toggle testing
    local location = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 0,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:0"
    })
    
    print("Testing toggle functionality at:", location.path, "line", location.line)
    
    -- Verify initial state: no breakpoints
    local initialBreakpoints = breakpointManager.breakpoints:count()
    assert(initialBreakpoints == 0, "Should start with no breakpoints")
    print("✓ Initial state: 0 breakpoints")
    
    -- === FIRST TOGGLE (ON) ===
    print("=== First Toggle (Should Create) ===")
    local result1 = breakpointManager:toggleBreakpoint(location)
    
    -- Verify breakpoint was created
    assert(result1 ~= nil, "Toggle should return breakpoint when creating")
    assert(result1.id == location.key, "Returned breakpoint should have correct ID")
    
    local breakpointsAfterToggleOn = breakpointManager.breakpoints:count()
    assert(breakpointsAfterToggleOn == 1, "Should have 1 breakpoint after toggle on")
    print("✓ Toggle ON: created breakpoint, returned object")
    
    -- Verify the breakpoint exists in manager's collection
    local existingBreakpoint = breakpointManager.breakpoints:atLocation(location):first()
    assert(existingBreakpoint ~= nil, "Breakpoint should exist in manager collection")
    assert(existingBreakpoint.id == result1.id, "Collection breakpoint should match returned breakpoint")
    print("✓ Breakpoint properly stored in collection")
    
    -- === SECOND TOGGLE (OFF) ===
    print("=== Second Toggle (Should Remove) ===")
    local result2 = breakpointManager:toggleBreakpoint(location)
    
    -- Verify breakpoint was removed
    assert(result2 == nil, "Toggle should return nil when removing")
    
    local breakpointsAfterToggleOff = breakpointManager.breakpoints:count()
    assert(breakpointsAfterToggleOff == 0, "Should have 0 breakpoints after toggle off")
    print("✓ Toggle OFF: removed breakpoint, returned nil")
    
    -- Verify the breakpoint no longer exists in manager's collection
    local removedBreakpoint = breakpointManager.breakpoints:atLocation(location):first()
    assert(removedBreakpoint == nil, "Breakpoint should not exist in manager collection")
    print("✓ Breakpoint properly removed from collection")
    
    -- === THIRD TOGGLE (ON AGAIN) ===
    print("=== Third Toggle (Should Create Again) ===")
    local result3 = breakpointManager:toggleBreakpoint(location)
    
    -- Verify breakpoint was created again
    assert(result3 ~= nil, "Toggle should return breakpoint when creating again")
    assert(result3.id == location.key, "Returned breakpoint should have correct ID")
    
    local breakpointsAfterSecondToggleOn = breakpointManager.breakpoints:count()
    assert(breakpointsAfterSecondToggleOn == 1, "Should have 1 breakpoint after second toggle on")
    print("✓ Toggle ON (again): created breakpoint, returned object")
    
    -- Verify it's a new breakpoint object (not the same as before)
    assert(result3 ~= result1, "Second toggle should create a new breakpoint object")
    print("✓ New breakpoint object created (not reused)")
    
    -- === FOURTH TOGGLE (OFF AGAIN) ===
    print("=== Fourth Toggle (Cleanup) ===")
    local result4 = breakpointManager:toggleBreakpoint(location)
    assert(result4 == nil, "Final toggle should return nil")
    
    -- Verify final cleanup
    local finalBreakpoints = breakpointManager.breakpoints:count()
    assert(finalBreakpoints == 0, "Should end with 0 breakpoints")
    print("✓ Final cleanup verified")
    
    -- === TEST WITH SESSION FOR BINDING BEHAVIOR ===
    print("=== Testing Toggle with Session (Binding Behavior) ===")
    
    -- Start a session
    local sessionStarted = Test.spy("sessionStarted")
    local sourceLoaded = Test.spy("sourceLoaded")
    
    api:onSession(function(session)
      session:onInitialized(function()
        sessionStarted.trigger()
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
    
    sessionStarted.wait()
    sourceLoaded.wait()
    print("✓ Session started and source loaded")
    
    -- Toggle breakpoint ON with active session
    local resultWithSession = breakpointManager:toggleBreakpoint(location)
    assert(resultWithSession ~= nil, "Toggle should create breakpoint with session")
    
    local breakpointsWithSession = breakpointManager.breakpoints:count()
    assert(breakpointsWithSession == 1, "Should have 1 breakpoint with session")
    print("✓ Toggle ON with session: breakpoint created")
    
    -- Wait a bit for binding creation (50ms batch + processing time)
    nio.sleep(100)
    
    -- Verify binding was created (check multiple times if needed due to async nature)
    local bindingsWithSession = breakpointManager.bindings:count()
    if bindingsWithSession ~= 1 then
      -- Wait a bit more and check again
      nio.sleep(100)
      bindingsWithSession = breakpointManager.bindings:count()
    end
    assert(bindingsWithSession == 1, "Should have 1 binding with session")
    
    local binding = resultWithSession:getBindings():first()
    assert(binding ~= nil, "Breakpoint should have binding with active session")
    assert(binding.verified == true, "Binding should be verified")
    print("✓ Binding created and verified with session")
    
    -- Toggle breakpoint OFF with active session
    local resultRemoveWithSession = breakpointManager:toggleBreakpoint(location)
    assert(resultRemoveWithSession == nil, "Toggle should remove breakpoint with session")
    
    -- Wait a bit for cleanup
    nio.sleep(100)
    
    local finalBreakpointsWithSession = breakpointManager.breakpoints:count()
    local finalBindingsWithSession = breakpointManager.bindings:count()
    assert(finalBreakpointsWithSession == 0, "Should have 0 breakpoints after removal with session")
    assert(finalBindingsWithSession == 0, "Should have 0 bindings after removal with session")
    print("✓ Toggle OFF with session: complete cleanup")
    
    print("✓ Toggle functionality test completed successfully!")
  end)
end)