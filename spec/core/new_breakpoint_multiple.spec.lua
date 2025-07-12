local Test = require("spec.helpers.testing")(describe, it)
local P = require("spec.helpers.prepare")
local prepare = P.prepare
local NewBreakpointManager = require("neodap.api.NewBreakpoint.BreakpointManager")
local Location = require("neodap.api.NewBreakpoint.Location")

Test.Describe("new breakpoint manager - multiple breakpoints", function()
  Test.It("should handle multiple breakpoints and session termination correctly", function()
    local api, start = prepare()
    
    -- Create new breakpoint manager
    local breakpointManager = NewBreakpointManager.create(api)
    
    -- Test spies
    local breakpointsAdded = Test.spy("breakpointsAdded")
    local bindingsCreated = Test.spy("bindingsCreated")
    local sessionTerminated = Test.spy("sessionTerminated")
    local allBindingsUnbound = Test.spy("allBindingsUnbound")
    
    -- Counters for tracking events
    local addedCount = 0
    local boundCount = 0
    local unboundCount = 0
    
    -- Set up hierarchical event listeners
    breakpointManager:onBreakpoint(function(breakpoint)
      addedCount = addedCount + 1
      print("✓ Breakpoint", addedCount, "added:", breakpoint.id)
      
      if addedCount == 3 then
        breakpointsAdded.trigger()
      end
      
      breakpoint:onBinding(function(binding)
        boundCount = boundCount + 1
        print("✓ Binding", boundCount, "created for breakpoint:", breakpoint.id, "in session:", binding.session.id)
        
        if boundCount == 3 then
          bindingsCreated.trigger()
        end
        
        -- Track unbinding events
        binding:onUnbound(function()
          unboundCount = unboundCount + 1
          print("✓ Binding", unboundCount, "unbound for breakpoint:", breakpoint.id)
          
          if unboundCount == 3 then
            allBindingsUnbound.trigger()
          end
        end)
      end)
    end)
    
    -- Create multiple breakpoints at different lines
    local locations = {
      Location.SourceFile:new({
        path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
        line = 3,
        column = 0,
        key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:0"
      }),
      Location.SourceFile:new({
        path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
        line = 4,
        column = 0,
        key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:4:0"
      }),
      Location.SourceFile:new({
        path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
        line = 5,
        column = 0,
        key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:5:0"
      })
    }
    
    print("Creating 3 breakpoints...")
    local breakpoints = {}
    for i, location in ipairs(locations) do
      print("Setting breakpoint", i, "at line", location.line)
      breakpoints[i] = breakpointManager:addBreakpoint(location)
      
      -- Verify immediate creation
      assert(breakpoints[i] ~= nil, "Breakpoint " .. i .. " should be created immediately")
      assert(breakpoints[i].id == location.key, "Breakpoint " .. i .. " should have location-based ID")
      
      -- Verify no bindings yet
      local initialBindings = breakpoints[i]:getBindings():count()
      assert(initialBindings == 0, "Breakpoint " .. i .. " should have no bindings before session")
    end
    
    -- Wait for all breakpoints to be added
    breakpointsAdded.wait()
    print("✓ All 3 breakpoints added")
    
    -- Verify manager state
    local totalBreakpoints = breakpointManager.breakpoints:count()
    local totalBindings = breakpointManager.bindings:count()
    assert(totalBreakpoints == 3, "Manager should have 3 breakpoints")
    assert(totalBindings == 0, "Manager should have 0 bindings before session")
    print("✓ Manager state verified: 3 breakpoints, 0 bindings")
    
    -- Set up session tracking
    local sessionRef = nil
    api:onSession(function(session)
      print("✓ Session created:", session.id)
      sessionRef = session
      
      session:onTerminated(function()
        print("✓ Session terminated:", session.id)
        sessionTerminated.trigger()
      end)
    end)
    
    -- Start debug session
    print("Starting debug session...")
    start("loop.js")
    
    -- Wait for all bindings to be created
    bindingsCreated.wait()
    print("✓ All 3 bindings created")
    
    -- Verify all breakpoints now have bindings
    for i, breakpoint in ipairs(breakpoints) do
      local bindingCount = breakpoint:getBindings():count()
      assert(bindingCount == 1, "Breakpoint " .. i .. " should have 1 binding")
      
      local binding = breakpoint:getBindings():first()
      assert(binding ~= nil, "Binding " .. i .. " should exist")
      assert(binding.verified == true, "Binding " .. i .. " should be verified")
      assert(binding.id ~= nil, "Binding " .. i .. " should have DAP ID")
      print("✓ Breakpoint", i, "has verified binding with DAP ID:", binding.id)
    end
    
    -- Verify manager state after binding
    local totalBreakpointsAfterBinding = breakpointManager.breakpoints:count()
    local totalBindingsAfterBinding = breakpointManager.bindings:count()
    assert(totalBreakpointsAfterBinding == 3, "Manager should still have 3 breakpoints")
    assert(totalBindingsAfterBinding == 3, "Manager should now have 3 bindings")
    print("✓ Manager state after binding: 3 breakpoints, 3 bindings")
    
    -- Test session termination cleanup
    print("=== Testing Session Termination Cleanup ===")
    
    assert(sessionRef ~= nil, "Session reference should exist")
    
    -- Disconnect the session to trigger cleanup
    print("Disconnecting session...")
    sessionRef.ref.calls:disconnect({
      terminateDebuggee = true
    })
    
    -- Wait for session termination
    sessionTerminated.wait()
    print("✓ Session termination confirmed")
    
    -- Wait for all bindings to be unbound
    allBindingsUnbound.wait()
    print("✓ All bindings unbound")
    
    -- Verify cleanup: breakpoints should remain, bindings should be gone
    local breakpointsAfterTermination = breakpointManager.breakpoints:count()
    local bindingsAfterTermination = breakpointManager.bindings:count()
    
    assert(breakpointsAfterTermination == 3, "Breakpoints should persist after session termination")
    assert(bindingsAfterTermination == 0, "All bindings should be removed after session termination")
    print("✓ Session termination cleanup verified: 3 breakpoints, 0 bindings")
    
    -- Verify each breakpoint no longer has bindings
    for i, breakpoint in ipairs(breakpoints) do
      local bindingCount = breakpoint:getBindings():count()
      assert(bindingCount == 0, "Breakpoint " .. i .. " should have no bindings after session termination")
    end
    
    print("✓ Individual breakpoint cleanup verified")
    print("✓ Multiple breakpoints and session termination test completed successfully!")
  end)
end)