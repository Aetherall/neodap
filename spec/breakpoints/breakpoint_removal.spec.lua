local Test = require("spec.helpers.testing")(describe, it)
local P = require("spec.helpers.prepare")
local prepare = P.prepare
local NewBreakpointManager = require("neodap.plugins.BreakpointApi.BreakpointManager")
local Location = require("neodap.api.Location")
local SourceIdentifier = require("neodap.api.Location.SourceIdentifier")

Test.Describe("new breakpoint manager - removal events", function()
  Test.It("should properly trigger Unbound and Removed hooks when breakpoint is deleted", function()
    local api, start = prepare()
    
    -- Create new breakpoint manager
    local breakpointManager = NewBreakpointManager.create(api)
    
    -- Test spies to track events
    local breakpointAdded = Test.spy("breakpointAdded")
    local bindingBound = Test.spy("bindingBound")
    local bindingUnbound = Test.spy("bindingUnbound")
    local breakpointRemoved = Test.spy("breakpointRemoved")
    local sessionInitialized = Test.spy("sessionInitialized")
    local sourceLoaded = Test.spy("sourceLoaded")
    
    -- Set up hierarchical event listeners for creation
    breakpointManager:onBreakpoint(function(breakpoint)
      print("✓ Breakpoint added:", breakpoint.id)
      breakpointAdded.trigger()
      
      -- Register for bindings
      breakpoint:onBinding(function(binding)
        print("✓ Binding created for session:", binding.session.id)
        bindingBound.trigger()
      end)
    end)
    
    -- Create breakpoint before session starts
    local location = Location.create({
      sourceId = SourceIdentifier.fromPath(vim.fn.getcwd() .. "/spec/fixtures/loop.js"),
      line = 3,
      column = 0
    })
    
    print("Setting breakpoint at:", location.path, "line", location.line)
    local breakpoint = breakpointManager:addBreakpoint(location)
    
    -- Verify breakpoint exists immediately
    assert(breakpoint ~= nil, "Breakpoint should be created immediately")
    assert(breakpoint.id == location.key, "Breakpoint should have location-based ID")
    
    -- Verify no bindings exist yet (lazy creation)
    local initialBindings = breakpoint:getBindings():count()
    assert(initialBindings == 0, "No bindings should exist before session starts")
    print("✓ Confirmed lazy binding - no bindings before session")
    
    -- Wait for breakpoint added event
    breakpointAdded.wait()
    print("✓ BreakpointAdded event received")
    
    -- Set up session event tracking
    api:onSession(function(session)
      print("✓ Session created:", session.id)
      
      session:onInitialized(function()
        print("✓ Session initialized:", session.id)
        sessionInitialized.trigger()
      end)
      
      session:onSourceLoaded(function(source)
        if source:isFile() and source:filename() == "loop.js" then
          print("✓ Target source loaded:", source:toString())
          sourceLoaded.trigger()
        end
      end)
    end)
    
    -- Start debug session
    print("Starting debug session...")
    start("loop.js")
    
    -- Wait for session initialization
    sessionInitialized.wait()
    print("✓ Session initialization confirmed")
    
    -- Wait for source to load
    sourceLoaded.wait()
    print("✓ Source loading confirmed")
    
    -- Wait for binding to be created
    bindingBound.wait()
    print("✓ Binding created via lazy binding")
    
    -- Verify binding now exists
    local boundBindings = breakpoint:getBindings():count()
    assert(boundBindings == 1, "One binding should exist after source loads")
    
    local binding = breakpoint:getBindings():first()
    assert(binding ~= nil, "Binding should exist")
    assert(binding.verified == true, "Binding should always be verified in lazy approach")
    assert(binding.id ~= nil, "Binding should have DAP ID")
    print("✓ Verified binding properties:")
    print("  - Verified:", binding.verified)
    print("  - DAP ID:", binding.id)
    print("  - Actual line:", binding.actualLine)
    
    -- NOW TEST THE REMOVAL FLOW
    print("=== Testing Removal Event Flow ===")
    
    -- Set up removal event listeners BEFORE removing
    binding:onDispose(function()
      print("✓ Binding Unbound event from binding itself")
      bindingUnbound.trigger()
    end)
    
    breakpoint:onDispose(function()
      print("✓ Breakpoint Removed event from breakpoint itself")
      breakpointRemoved.trigger()
    end)
    
    -- Capture counts before removal for verification
    local bindingsBeforeRemoval = breakpointManager.bindings:count()
    local breakpointsBeforeRemoval = breakpointManager.breakpoints:count()
    
    print("Before removal - Bindings:", bindingsBeforeRemoval, "Breakpoints:", breakpointsBeforeRemoval)
    assert(bindingsBeforeRemoval == 1, "Should have 1 binding before removal")
    assert(breakpointsBeforeRemoval == 1, "Should have 1 breakpoint before removal")
    
    -- Remove the breakpoint
    print("Removing breakpoint...")
    breakpointManager:removeBreakpoint(breakpoint)
    
    -- Wait for events in the expected order
    print("Waiting for Unbound event...")
    bindingUnbound.wait()
    print("✓ Binding Unbound event confirmed")
    
    print("Waiting for Removed event...")
    breakpointRemoved.wait()
    print("✓ Breakpoint Removed event confirmed")
    
    -- Verify complete cleanup
    local bindingsAfterRemoval = breakpointManager.bindings:count()
    local breakpointsAfterRemoval = breakpointManager.breakpoints:count()
    
    print("After removal - Bindings:", bindingsAfterRemoval, "Breakpoints:", breakpointsAfterRemoval)
    assert(bindingsAfterRemoval == 0, "All bindings should be removed")
    assert(breakpointsAfterRemoval == 0, "All breakpoints should be removed")
    
    -- Verify the specific binding and breakpoint are no longer accessible
    local bindingsForBreakpoint = breakpoint:getBindings():count()
    assert(bindingsForBreakpoint == 0, "Breakpoint should have no bindings after removal")
    
    print("✓ Complete cleanup verified")
    print("✓ Removal event flow test completed successfully!")
  end)
end)