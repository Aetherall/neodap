local Test = require("spec.helpers.testing")(describe, it)
local P = require("spec.helpers.prepare")
local prepare = P.prepare
local NewBreakpointManager = require("neodap.api.NewBreakpoint.BreakpointManager")
local Location = require("neodap.api.NewBreakpoint.Location")

Test.Describe("new breakpoint manager - basic functionality", function()
  Test.It("should set breakpoint and hit correctly with lazy binding", function()
    local api, start = prepare()
    
    -- Create new breakpoint manager
    local breakpointManager = NewBreakpointManager.create(api)
    
    -- Test spies to track events
    local breakpointAdded = Test.spy("breakpointAdded")
    local bindingBound = Test.spy("bindingBound")
    local breakpointHit = Test.spy("breakpointHit")
    local sessionInitialized = Test.spy("sessionInitialized")
    local sourceLoaded = Test.spy("sourceLoaded")
    
    -- Track that we're using hierarchical API correctly
    local hierarchicalHitEvent = Test.spy("hierarchicalHitEvent")
    
    -- Set up hierarchical event listeners
    breakpointManager:onBreakpoint(function(breakpoint)
      print("✓ Breakpoint added via hierarchical API:", breakpoint.id)
      breakpointAdded.trigger()
      
      -- Register for bindings through hierarchical API
      breakpoint:onBinding(function(binding)
        print("✓ Binding created via hierarchical API - Session:", binding.session.id)
        bindingBound.trigger()
        
        -- Register for hits through hierarchical API
        binding:onHit(function(hit)
          print("✓ Hit detected via hierarchical API - Thread:", hit.thread.id)
          hierarchicalHitEvent.trigger()
        end)
      end)
      
      -- Also register for hits at breakpoint level
      breakpoint:onHit(function(hit)
        print("✓ Hit detected at breakpoint level - Binding:", hit.binding.id)
        breakpointHit.trigger()
      end)
    end)
    
    -- Create breakpoint before session starts (tests lazy binding)
    local location = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 0,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:0"
    })
    
    print("Setting breakpoint at:", location.path, "line", location.line)
    local breakpoint = breakpointManager:addBreakpoint(location)
    
    -- Verify breakpoint exists immediately (user intent)
    assert(breakpoint ~= nil, "Breakpoint should be created immediately")
    assert(breakpoint.id == location.key, "Breakpoint should have location-based ID")
    
    -- Verify no bindings exist yet (lazy creation)
    local initialBindings = breakpoint:getBindings():count()
    assert(initialBindings == 0, "No bindings should exist before session starts")
    print("✓ Confirmed lazy binding - no bindings before session")
    
    -- Wait for breakpoint added event
    breakpointAdded.wait()
    print("✓ BreakpointAdded event received")
    
    -- Set up session event tracking through proper API hook
    api:onSession(function(session)
      print("✓ Session created via API hook:", session.id)
      
      session:onInitialized(function()
        print("✓ Session initialized:", session.id)
        sessionInitialized.trigger()
      end)
      
      session:onSourceLoaded(function(source)
        local fileSource = source:asFile()
        if fileSource and fileSource:filename() == "loop.js" then
          print("✓ Target source loaded:", fileSource:identifier())
          sourceLoaded.trigger()
        end
      end)
    end)
    
    -- Start debug session (will trigger api:onSession hook)
    print("Starting debug session...")
    start("loop.js")
    
    -- Wait for session initialization
    sessionInitialized.wait()
    print("✓ Session initialization confirmed")
    
    -- Wait for source to load
    sourceLoaded.wait()
    print("✓ Source loading confirmed")
    
    -- Wait for binding to be created (lazy binding)
    bindingBound.wait()
    print("✓ Binding created via lazy binding")
    
    -- Verify binding now exists
    local boundBindings = breakpoint:getBindings():count()
    assert(boundBindings == 1, "One binding should exist after source loads")
    
    local binding = breakpoint:getBindings():first()
    assert(binding ~= nil, "Binding should exist")
    assert(binding.verified == true, "Binding should always be verified in lazy approach")
    assert(binding.id ~= nil, "Binding should have DAP ID")
    print("✓ Verified lazy binding properties:")
    print("  - Verified:", binding.verified)
    print("  - DAP ID:", binding.id)
    print("  - Actual line:", binding.actualLine)
    
    -- Wait for breakpoint to hit
    print("Waiting for breakpoint hit...")
    breakpointHit.wait()
    print("✓ Breakpoint hit confirmed")
    
    -- Wait for hierarchical hit event
    hierarchicalHitEvent.wait()
    print("✓ Hierarchical hit event confirmed")
    
    -- Test breakpoint removal
    print("Testing breakpoint removal...")
    local breakpointRemoved = Test.spy("breakpointRemoved")
    local bindingUnbound = Test.spy("bindingUnbound")
    
    -- Register for removal events
    breakpoint:onRemoved(function()
      print("✓ Breakpoint removal event from breakpoint itself")
      breakpointRemoved.trigger()
    end)
    
    -- Get the binding through the hierarchical API for cleanup testing
    local bindingForCleanup = breakpoint:getBindings():first()
    assert(bindingForCleanup ~= nil, "Binding should exist for cleanup test")
    bindingForCleanup:onUnbound(function()
      print("✓ Binding unbound event from binding itself")
      bindingUnbound.trigger()
    end)
    
    -- Remove breakpoint
    breakpointManager:removeBreakpoint(breakpoint)
    
    -- Wait for proper cleanup
    bindingUnbound.wait()
    breakpointRemoved.wait()
    
    print("✓ Cleanup events confirmed")
    
    -- Verify cleanup
    local finalBindings = breakpointManager.bindings:count()
    local finalBreakpoints = breakpointManager.breakpoints:count()
    assert(finalBindings == 0, "All bindings should be removed")
    assert(finalBreakpoints == 0, "All breakpoints should be removed")
    
    print("✓ Complete cleanup verified")
    print("✓ Test completed successfully - lazy binding architecture works!")
  end)
end)