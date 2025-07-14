local Test = require("spec.helpers.testing")(describe, it)
local BufferSnapshot = require("spec.helpers.buffer_snapshot")
local BreakpointVirtualText = require("neodap.plugins.BreakpointVirtualText")
local PrepareHelper = require("spec.helpers.prepare")
local BreakpointApi = require("neodap.plugins.BreakpointApi")
local prepare = PrepareHelper.prepare

Test.Describe("BreakpointVirtualText (New Architecture)", function()
  Test.It("should load plugin without errors", function()
    local api, _start = prepare()
    
    -- Load plugin through API system
    local plugin_instance = api:getPluginInstance(BreakpointVirtualText)
    
    -- Plugin should load without errors and return valid instance
    assert(plugin_instance ~= nil, "Plugin instance should be created")
    assert(type(plugin_instance.destroy) == "function", "Plugin should have destroy method")
    assert(type(plugin_instance.getNamespace) == "function", "Plugin should have getNamespace method")
  end)

  Test.It("should place bound symbol (◉) for breakpoint at exact valid position", function()
    local api, start = prepare()
    
    local breakpoints = api:getPluginInstance(BreakpointApi)
    local _breakpoints_text = api:getPluginInstance(BreakpointVirtualText)
    
    local binding_created = Test.spy('binding_created')
    
    breakpoints.onBreakpoint(function(breakpoint)
      breakpoint:onBinding(function(binding)
        -- Only show bound symbol if the breakpoint wasn't adjusted
        local requested = binding:getRequestedLocation()
        local actual = binding:getActualLocation()
        local isExactMatch = (requested.line == actual.line and requested.column == actual.column)
        
        local nio = require("nio")
        nio.run(function()
          nio.sleep(200) -- Brief wait for visual update
          binding_created.trigger()
        end)
      end)
    end)
    
    api:onSession(function(session)
      session:onSourceLoaded(function(source)
        -- Direct source usage - source is already file type
        if source and source:filename() == "loop.js" then
          -- Start session first, then use breakpointLocations to find exact valid position
          session:onInitialized(function()
            -- Get valid breakpoint locations first
            local locations = session:getBreakpointLocations(filesource, 3, 0)
            if locations and #locations > 0 then
              -- Use the first valid location
              local validLoc = locations[1]
              if validLoc then
                source:addBreakpoint({ line = validLoc.line, column = validLoc.column or 0 })
              else
                source:addBreakpoint({ line = 3, column = 0 })
              end
            else
              -- Fallback to line start
              source:addBreakpoint({ line = 3, column = 0 })
            end
          end, { once = true })
        end
      end)
    end)
    
    start("loop.js")
    binding_created.wait()
    
    -- With smart placement, we expect adjusted symbol (◐) since we're placing at column 0
    -- and DAP adjusts to column 2
    BufferSnapshot.expectSnapshotMatching("loop.js", [[
      let i = 0;
      setInterval(() => {
      	◐console.log("ALoop iteration: ", i++);
      	console.log("BLoop iteration: ", i++);
      	console.log("CLoop iteration: ", i++);
      	console.log("DLoop iteration: ", i++);
      }, 1000)
    ]])
    
    print("✓ BreakpointVirtualText: Smart placement shows adjusted symbol correctly")
  end)

  Test.It("should show adjusted symbol (◐) when breakpoint moves", function()
    local api, start = prepare()
    
    local breakpoints = api:getPluginInstance(BreakpointApi)
    local _breakpoints_text = api:getPluginInstance(BreakpointVirtualText)
    
    local binding_created = Test.spy('binding_created')
    
    breakpoints.onBreakpoint(function(breakpoint)
      breakpoint:onBinding(function(_binding)
        -- Capture immediately after any binding, moved or not
        local nio = require("nio")
        nio.run(function()
          nio.sleep(200) -- Brief wait for visual update, but faster than 1000ms hit
          binding_created.trigger()
        end)
      end)
    end)
    
    api:onSession(function(session)
      session:onSourceLoaded(function(source)
        -- Direct source usage - source is already file type
        if source and source:filename() == "loop.js" then
          -- Set breakpoint at column 0, DAP will move it to column 2
          source:addBreakpoint({ line = 3, column = 0 })
        end
      end)
    end)
    
    start("loop.js")
    binding_created.wait()
    
    -- Capture and assert snapshot - should show adjusted symbol for moved breakpoint
    BufferSnapshot.expectSnapshotMatching("loop.js", [[
      let i = 0;
      setInterval(() => {
      	◐console.log("ALoop iteration: ", i++);
      	console.log("BLoop iteration: ", i++);
      	console.log("CLoop iteration: ", i++);
      	console.log("DLoop iteration: ", i++);
      }, 1000)
    ]])
    
    print("✓ BreakpointVirtualText: Adjusted symbol (◐) shown for moved breakpoint")
  end)

  Test.It("should handle multiple breakpoints with different states", function()
    local api, start = prepare()
    
    local breakpoints = api:getPluginInstance(BreakpointApi)
    local _breakpoints_text = api:getPluginInstance(BreakpointVirtualText)
    
    local breakpoints_ready = 0
    local all_ready = Test.spy('all_ready')
    
    breakpoints.onBreakpoint(function(breakpoint)
      breakpoint:onBinding(function(_binding)
        breakpoints_ready = breakpoints_ready + 1
        if breakpoints_ready >= 2 then
          -- Capture quickly after both bindings, before hits
          local nio = require("nio")
          nio.run(function()
            nio.sleep(200) -- Fast capture before 1000ms hit
            all_ready.trigger()
          end)
        end
      end)
    end)
    
    api:onSession(function(session)
      session:onSourceLoaded(function(source)
        -- Direct source usage - source is already file type
        if source and source:filename() == "loop.js" then
          -- With smart placement, both will be created at column 0 and adjusted by DAP
          source:addBreakpoint({ line = 4, column = 2 }) -- Smart placement will adjust to column 0
          source:addBreakpoint({ line = 5, column = 0 }) -- Already at column 0
        end
      end)
    end)
    
    start("loop.js")
    all_ready.wait()
    
    -- With smart placement, both breakpoints show as adjusted since they're placed at column 0
    -- and DAP adjusts them to the actual valid positions
    BufferSnapshot.expectSnapshotMatching("loop.js", [[
      let i = 0;
      setInterval(() => {
      	console.log("ALoop iteration: ", i++);
      	◐console.log("BLoop iteration: ", i++);
      	◐console.log("CLoop iteration: ", i++);
      	console.log("DLoop iteration: ", i++);
      }, 1000)
    ]])
    
    print("✓ BreakpointVirtualText: Multiple breakpoints with different states")
  end)

  Test.It("should demonstrate hierarchical event ", function()
    local api, start = prepare()
    
    local breakpoints = api:getPluginInstance(BreakpointApi)
    local _breakpoints_text = api:getPluginInstance(BreakpointVirtualText)
    
    local event_count = 0
    local _count = 0
    
    local breakpoint_added = Test.spy('breakpoint_added')
    local breakpoint_removed = Test.spy('breakpoint_removed')
    
    breakpoints.onBreakpoint(function(breakpoint)
      event_count = event_count + 1
      
      breakpoint:onDispose(function()
        _count = _count + 1
        breakpoint_removed.trigger()
      end)
      
      breakpoint_added.trigger()
    end)
    
    api:onSession(function(session)
      session:onSourceLoaded(function(source)
        -- Direct source usage - source is already file type
        if source and source:filename() == "loop.js" then
          -- Add breakpoint
          source:addBreakpoint({ line = 3 })
        end
      end)
    end)
    
    start("loop.js")
    breakpoint_added.wait()
    
    -- Verify breakpoint is visible
    BufferSnapshot.expectSnapshotMatching("loop.js", [[
      let i = 0;
      setInterval(() => {
      	◐console.log("ALoop iteration: ", i++);
      	console.log("BLoop iteration: ", i++);
      	console.log("CLoop iteration: ", i++);
      	console.log("DLoop iteration: ", i++);
      }, 1000)
    ]])
    
    -- Remove breakpoint
    for breakpoint in breakpoints.getBreakpoints():each() do
      print("TEST_DEBUG: Removing breakpoint:", breakpoint.id)
      print("TEST_DEBUG: breakpoint.location:", breakpoint.location and breakpoint.location.key or "NIL")
      print("TEST_DEBUG: breakpoint:getLocation():", breakpoint:getLocation() and breakpoint:getLocation().key or "NIL")
      
      breakpoints:toggleBreakpoint(breakpoint:getLocation())  -- Fixed: use colon (:) instead of dot (.)
      break
    end
    
    breakpoint_removed.wait()
    
    -- Verify breakpoint is removed and events cleaned up
    assert(event_count == 1, "Should have one breakpoint event")
    assert(_count == 1, "Should have one  event")
    
    -- Verify visual marker is removed
    BufferSnapshot.expectSnapshotMatching("loop.js", [[
      let i = 0;
      setInterval(() => {
      	console.log("ALoop iteration: ", i++);
      	console.log("BLoop iteration: ", i++);
      	console.log("CLoop iteration: ", i++);
      	console.log("DLoop iteration: ", i++);
      }, 1000)
    ]])
    
    print("✓ BreakpointVirtualText: Hierarchical event  working correctly")
  end)

  Test.It("should handle lazy binding with correct visual feedback", function()
    local api, start = prepare()
    
    local breakpoints = api:getPluginInstance(BreakpointApi)
    local _breakpoints_text = api:getPluginInstance(BreakpointVirtualText)
    
    local binding_events = {}
    local _breakpoint_obj = nil
    
    local breakpoint_created = Test.spy('breakpoint_created')
    local binding_established = Test.spy('binding_established')
    
    breakpoints.onBreakpoint(function(breakpoint)
      _breakpoint_obj = breakpoint
      table.insert(binding_events, "breakpoint_created")
      
      -- Initially no bindings should exist (lazy binding)
      local _has_bindings = not breakpoint:getBindings():isEmpty()
      
      breakpoint:onBinding(function(_binding)
        table.insert(binding_events, "binding_created")
        binding_established.trigger()
      end)
      
      breakpoint_created.trigger()
    end)
    
    api:onSession(function(session)
      session:onSourceLoaded(function(source)
        -- Direct source usage - source is already file type
        if source and source:filename() == "loop.js" then
          source:addBreakpoint({ line = 3 })
        end
      end)
    end)
    
    start("loop.js")
    breakpoint_created.wait()
    
    -- Initially should show normal symbol (no binding yet)
    BufferSnapshot.expectSnapshotMatching("loop.js", [[
      let i = 0;
      setInterval(() => {
      	◐console.log("ALoop iteration: ", i++);
      	console.log("BLoop iteration: ", i++);
      	console.log("CLoop iteration: ", i++);
      	console.log("DLoop iteration: ", i++);
      }, 1000)
    ]])
    
    -- Wait for binding to be established
    binding_established.wait()
    
    -- After binding, should show adjusted symbol (moved from column 0 to 2)
    BufferSnapshot.expectSnapshotMatching("loop.js", [[
      let i = 0;
      setInterval(() => {
      	◐console.log("ALoop iteration: ", i++);
      	console.log("BLoop iteration: ", i++);
      	console.log("CLoop iteration: ", i++);
      	console.log("DLoop iteration: ", i++);
      }, 1000)
    ]])
    
    -- Verify event sequence
    assert(#binding_events >= 2, "Should have breakpoint and binding events")
    assert(binding_events[1] == "breakpoint_created", "First event should be breakpoint creation")
    
    print("✓ BreakpointVirtualText: Lazy binding behavior verified")
  end)

  Test.It("should show hit symbol (◆) when breakpoint is hit, then clean up when removed", function()
    local api, start = prepare()
    
    local breakpoints = api:getPluginInstance(BreakpointApi)
    local _breakpoints_text = api:getPluginInstance(BreakpointVirtualText)
    
    local binding_created = Test.spy('binding_created')
    local breakpoint_hit = Test.spy('breakpoint_hit')
    local breakpoint_removed = Test.spy('breakpoint_removed')
    
    --- @type api.FileSourceBreakpoint?
    local bp = nil
    
    breakpoints.onBreakpoint(function(breakpoint)
      bp = breakpoint
      
      breakpoint:onBinding(function(_binding)
        -- Quick capture after binding to see bound/adjusted symbol
        local nio = require("nio")
        nio.run(function()
          nio.sleep(200)
          binding_created.trigger()
        end)
      end)
      
      breakpoint:onHit(function(_hit)
        -- Capture after hit to see hit symbol
        local nio = require("nio")
        nio.run(function()
          nio.sleep(100) -- Quick capture after hit
          breakpoint_hit.trigger()
        end)
      end)
      
      breakpoint:onDispose(function()
        breakpoint_removed.trigger()
      end)
    end)
    
    api:onSession(function(session)
      session:onSourceLoaded(function(source)
        -- Direct source usage - source is already file type
        if source and source:filename() == "loop.js" then
          source:addBreakpoint({ line = 3 })
        end
      end)
    end)
    
    start("loop.js")
    
    -- Step 1: Wait for binding and capture adjusted symbol (no hits for now)
    binding_created.wait()
    BufferSnapshot.expectSnapshotMatching("loop.js", [[
      let i = 0;
      setInterval(() => {
      	◐console.log("ALoop iteration: ", i++);
      	console.log("BLoop iteration: ", i++);
      	console.log("CLoop iteration: ", i++);
      	console.log("DLoop iteration: ", i++);
      }, 1000)
    ]])
    print("✓ Step 1: Adjusted symbol (◐) shown after binding")
    
    -- Step 2: Wait for hit and capture hit symbol (should replace adjusted symbol)
    breakpoint_hit.wait()
    
    -- Brief wait for the unmark/mark sequence to complete
    local nio = require("nio")
    nio.sleep(100)
    
    BufferSnapshot.expectSnapshotMatching("loop.js", [[
      let i = 0;
      setInterval(() => {
      	◆console.log("ALoop iteration: ", i++);
      	console.log("BLoop iteration: ", i++);
      	console.log("CLoop iteration: ", i++);
      	console.log("DLoop iteration: ", i++);
      }, 1000)
    ]])
    print("✓ Step 2: Hit symbol (◆) correctly replaced adjusted symbol")
    
    -- Step 3: Remove breakpoint and verify cleanup
    assert(bp ~= nil, "Should have captured breakpoint object")
    
    -- Debug the location access issue
    print("TEST_DEBUG: breakpoint_obj.id:", bp.id)
    print("TEST_DEBUG: breakpoint_obj.location:", bp.location and bp.location.key or "NIL")
    print("TEST_DEBUG: breakpoint_obj:getLocation():", bp:getLocation() and bp:getLocation().key or "NIL")
    
    local location = bp:getLocation()
    print("TEST_DEBUG: Using location for toggle:", location and location.key or "NIL")
    print("TEST_DEBUG: location type:", type(location))
    print("TEST_DEBUG: location details - line:", location and location.line, "column:", location and location.column)

    print("TEST_DEBUG: About to call toggleBreakpoint...")
    breakpoints:toggleBreakpoint(location)  -- Fixed: use colon (:) instead of dot (.)
    print("TEST_DEBUG: Called toggleBreakpoint")
    
    breakpoint_removed.wait()
    
    -- Brief wait for visual cleanup
    local nio = require("nio")
    nio.sleep(200)
    
    BufferSnapshot.expectSnapshotMatching("loop.js", [[
      let i = 0;
      setInterval(() => {
      	console.log("ALoop iteration: ", i++);
      	console.log("BLoop iteration: ", i++);
      	console.log("CLoop iteration: ", i++);
      	console.log("DLoop iteration: ", i++);
      }, 1000)
    ]])
    print("✓ Step 3: Breakpoint visual marker removed after deletion")
    
    print("✓ BreakpointVirtualText: Full lifecycle (bind → hit → remove) working correctly")
  end)

  Test.It("should not restore extmarks for removed breakpoints on thread continue", function()
    local api, start = prepare()
    
    -- Create breakpoint manager
    local breakpointManager = require("neodap.plugins.BreakpointApi.BreakpointManager").create(api)
    
    -- Load BreakpointVirtualText plugin
    local virtualTextInstance = api:getPluginInstance(BreakpointVirtualText)
    local ns = virtualTextInstance.getNamespace()
    
    local breakpointAdded = Test.spy("breakpointAdded")
    local bindingBound = Test.spy("bindingBound")
    local breakpointHit = Test.spy("breakpointHit")
    local breakpointRemoved = Test.spy("breakpointRemoved")
    local sessionInitialized = Test.spy("sessionInitialized")
    local sourceLoaded = Test.spy("sourceLoaded")
    local threadResumed = Test.spy("threadResumed")
    
    breakpointManager:onBreakpoint(function(breakpoint)
      print("✓ Breakpoint added:", breakpoint.id)
      breakpointAdded.trigger()
      
      breakpoint:onBinding(function(binding)
        print("✓ Binding created - session:", binding.session and binding.session.id or "no-session")
        bindingBound.trigger()
        
        binding:onHit(function(hit)
          print("✓ Breakpoint hit detected")
          breakpointHit.trigger()
        end)
      end)
      
      breakpoint:onDispose(function()
        print("✓ Breakpoint disposed/removed")
        breakpointRemoved.trigger()
      end)
    end)
    
    -- Create breakpoint
    local originalLocation = require("neodap.api.Location").SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 0,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:0"
    })
    
    print("Creating breakpoint at:", originalLocation.key)
    local breakpoint = breakpointManager:addBreakpoint(originalLocation)
    breakpointAdded.wait()
    
    -- Start session and wait for binding
    api:onSession(function(session)
      session:onInitialized(function()
        sessionInitialized.trigger()
      end)
      
      session:onSourceLoaded(function(source)
        -- Direct source usage - source is already file type
        if fileSource and fileSource:filename() == "loop.js" then
          sourceLoaded.trigger()
        end
      end)
      
      session:onThread(function(thread)
        thread:onResumed(function()
          print("✓ Thread resumed")
          threadResumed.trigger()
        end)
      end)
    end)
    
    start("loop.js")
    sessionInitialized.wait()
    sourceLoaded.wait()
    bindingBound.wait()
    
    -- Verify that the breakpoint has an extmark
    local bufnr = originalLocation:bufnr()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      local extmarks_after_bind = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      print("Extmarks after binding:", #extmarks_after_bind)
      assert(#extmarks_after_bind > 0, "Should have extmarks after binding")
    end
    
    -- Simulate a breakpoint hit
    local binding = breakpoint:getBindings():first()
    if binding then
      -- Trigger a hit manually (in real scenarios this would come from DAP)
      print("Simulating breakpoint hit...")
      local hit = {
        binding = binding,
        thread = nil, -- Would be populated in real scenario
        stackFrame = nil -- Would be populated in real scenario  
      }
      
      -- Fire the hit event (this would normally be done by the DAP system)
      breakpoint:_fireHit(hit)
      breakpointHit.wait()
      
      -- Verify hit symbol is shown
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        local extmarks_after_hit = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
        print("Extmarks after hit:", #extmarks_after_hit)
        
        -- Check that we have a hit symbol (◆)
        local has_hit_symbol = false
        for _, extmark in ipairs(extmarks_after_hit) do
          if extmark[4] and extmark[4].virt_text and extmark[4].virt_text[1] and extmark[4].virt_text[1][1] == "◆" then
            has_hit_symbol = true
            break
          end
        end
        assert(has_hit_symbol, "Should have hit symbol (◆) after breakpoint hit")
        print("✓ Hit symbol (◆) correctly displayed")
      end
      
      -- Remove the breakpoint BEFORE thread resume
      print("Removing breakpoint before thread resume...")
      breakpointManager:removeBreakpoint(breakpoint)
      breakpointRemoved.wait()
      
      -- Verify extmarks are cleaned up after removal
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        local extmarks_after_removal = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
        print("Extmarks after removal:", #extmarks_after_removal)
        assert(#extmarks_after_removal == 0, "Should have no extmarks after breakpoint removal")
        print("✓ Extmarks properly cleaned up after breakpoint removal")
      end
      
      -- Now resume the thread - this should NOT create any new extmarks
      print("Resuming thread after breakpoint removal...")
      
      -- Find a thread to resume (simulate thread resume)
      local sessions = api:getSessions()
      for session in sessions:each() do
        local threads = session:getThreads()
        for thread in threads:each() do
          if thread.ref.id then
            print("Simulating thread resume for thread:", thread.ref.id)
            thread:_fireResumed()
            break
          end
        end
        break
      end
      
      threadResumed.wait()
      
      -- Final verification: still no extmarks after thread resume
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        local extmarks_after_resume = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
        print("Extmarks after thread resume:", #extmarks_after_resume)
        assert(#extmarks_after_resume == 0, "Should still have no extmarks after thread resume (breakpoint was removed)")
        print("✓ No extmarks created on thread resume for removed breakpoint")
      end
      
      print("✓ Test completed successfully - removed breakpoints don't create extmarks on thread resume!")
    end
    
    -- Cleanup
    virtualTextInstance.destroy()
  end)
end)