-- Multi-session breakpoint persistence and concurrency tests
local prepare = require("spec.helpers.prepare")
local nio = require("nio")

describe("Multi-session Breakpoint Tests", function()
  describe("Cross-session breakpoint persistence", function()
    it("should persist breakpoints across multiple sessions", function()
      local api, start = prepare()

      print("\n\tTest: Cross-session breakpoint persistence\t")
      
      local session1Initialized = nio.control.future()
      local session2Initialized = nio.control.future()
      
      -- Track sessions as they're created
      local sessionCount = 0
      api:onSession(function(session)
        sessionCount = sessionCount + 1
        if sessionCount == 1 then
          session1 = session
          session:onInitialized(session1Initialized.set, { once = true })
        elseif sessionCount == 2 then
          session2 = session
          session:onInitialized(session2Initialized.set, { once = true })
        end
      end)
      
      -- Start two sessions with the same file
      start("simple-debug.js")
      start("simple-debug.js")
      
      assert(vim.wait(10000, session1Initialized.is_set), "Session 1 should be initialized")
      assert(vim.wait(10000, session2Initialized.is_set), "Session 2 should be initialized")
      
      -- Get the same source file from both sessions
      local source1 = session1:getSourceFor({
        path = vim.fn.resolve("spec/fixtures/simple-debug.js")
      })
      local source2 = session2:getSourceFor({
        path = vim.fn.resolve("spec/fixtures/simple-debug.js")
      })
      
      assert(source1, "Source 1 should be found")
      assert(source2, "Source 2 should be found")
      
      -- Initially both sources should have no breakpoints
      assert(#source1:listBreakpoints() == 0, "Source 1 should start with no breakpoints")
      assert(#source2:listBreakpoints() == 0, "Source 2 should start with no breakpoints")
      
      -- Set breakpoints using the source interface (this should now go through BreakpointManager)
      source1:setBreakpoints({{line = 3}}) -- Simplified breakpoint format
      
      -- Session 1 should see the breakpoint
      local session1Breakpoints = source1:listBreakpoints()
      assert(#session1Breakpoints == 1)
      local session1Breakpoint = session1Breakpoints[1]
      assert(session1Breakpoint)
      assert(session1Breakpoint.line == 3)
      
      -- Session 2 should also see the same breakpoint (cross-session persistence)
      local session2Breakpoints = source2:listBreakpoints()  
      assert(#session2Breakpoints == 1)
      local session2Breakpoint = session2Breakpoints[1]
      assert(session2Breakpoint)
      assert(session2Breakpoint.line == 3)

      -- Both should reference the same underlying breakpoint
      assert(session1Breakpoint.id == session2Breakpoint.id)
    end)
  end)

  describe("Concurrent session breakpoint binding", function()
    it("should bind both sessions to the same breakpoint", function()
      print("\n\tTest: Concurrent session breakpoint binding\t")
      local api, start = prepare()
      
      local session1Initialized = nio.control.future()
      local session2Initialized = nio.control.future()
      
      -- Track sessions as they're created
      local sessionCount = 0
      api:onSession(function(session)
        sessionCount = sessionCount + 1
        if sessionCount == 1 then
          session1 = session
          session:onInitialized(session1Initialized.set, { once = true })
        elseif sessionCount == 2 then
          session2 = session
          session:onInitialized(session2Initialized.set, { once = true })
        end
      end)
      
      -- Start two sessions with the same file
      start("simple-debug.js")
      start("simple-debug.js")
      
      assert(vim.wait(10000, session1Initialized.is_set), "Session 1 should be initialized")
      assert(vim.wait(10000, session2Initialized.is_set), "Session 2 should be initialized")
      
      local source1 = session1:getSourceFor({
        path = vim.fn.resolve("spec/fixtures/simple-debug.js")
      })
      local source2 = session2:getSourceFor({
        path = vim.fn.resolve("spec/fixtures/simple-debug.js")
      })

      assert(source1)
      assert(source2)
      
      -- Set breakpoint in session 1
      source1:setBreakpoints({{line = 3}})
      
      -- Get the breakpoint from both sessions
      local session1Breakpoints = source1:listBreakpoints()
      local session2Breakpoints = source2:listBreakpoints()
      
      assert(#session1Breakpoints == 1, "Session 1 should have 1 breakpoint")
      assert(#session2Breakpoints == 1, "Session 2 should have 1 breakpoint")
      
      local bp1 = assert(session1Breakpoints[1])
      local bp2 = assert(session2Breakpoints[1])
      
      -- Should be the same breakpoint object
      assert(bp1.id == bp2.id, "Both sessions should reference the same breakpoint")
      
      -- Check that both sessions have bindings to this breakpoint
      local binding1 = bp1:binding(session1)
      local binding2 = bp2:binding(session2)
      
      assert(binding1, "Session 1 should have a binding to the breakpoint")
      assert(binding2, "Session 2 should have a binding to the breakpoint")
      
      -- Both bindings should reference the correct sessions
      assert(session1.ref.id == binding1.session.ref.id, "Binding 1 should reference session 1")
      assert(session2.ref.id == binding2.session.ref.id, "Binding 2 should reference session 2")
    end)
  end)

  describe("Concurrent breakpoint hits", function()
    it("should properly sync breakpoints across sessions and verify hits", function()
      print("\n\tTest: Cross-session breakpoint sync and hits\t")
      print("DEBUG: Test using loop.js fixture for continuous execution")

      local api, start = prepare()

      local sessionsWithLoopJs = {}
      local session1BreakpointHit = nio.control.future()
      local session2BreakpointHit = nio.control.future()
      local readyToTest = nio.control.future()
      
      -- Track sessions that load loop.js and set up breakpoint handlers
      api:onSession(function(session)
        print("DEBUG: New session created with ID: " .. tostring(session.ref.id) .. ", parent: " .. tostring(session.ref.parent and session.ref.parent.id or "none"))
        
        -- Set up thread handler immediately for all sessions
        session:onThread(function(thread)
          print("DEBUG: Setting up onPaused handler for thread in session " .. tostring(session.ref.id) .. " (thread ID: " .. tostring(thread.id) .. ")")
          thread:onStopped(function(body)
            if body.reason == "breakpoint" then
              print("DEBUG: Session " .. tostring(session.ref.id) .. " hit breakpoint")
              
              -- Find this session in our loop.js sessions list
              local sessionIndex = nil
              for i, s in ipairs(sessionsWithLoopJs) do
                if s.ref.id == session.ref.id then
                  sessionIndex = i
                  break
                end
              end
              
              if sessionIndex == 1 then
                print("DEBUG: This is the first loop.js session")
                if not session1BreakpointHit.is_set() then
                  session1BreakpointHit.set(true)
                end
              elseif sessionIndex == 2 then
                print("DEBUG: This is the second loop.js session")
                if not session2BreakpointHit.is_set() then
                  session2BreakpointHit.set(true)
                end
              else
                print("DEBUG: WARNING: Breakpoint hit in session not in our loop.js list: " .. tostring(session.ref.id))
              end
              
              -- Continue execution after verification
              nio.run(function()
                print("DEBUG: Continuing session " .. tostring(session.ref.id) .. " after breakpoint hit")
                thread:continue()
              end)
            end
          end)
        end)
        
        -- Wait for source to be loaded
        session:onSourceLoaded(function(source)
          if source:isFile() and source:filename() == "loop.js" then
            print("DEBUG: Session " .. tostring(session.ref.id) .. " loaded loop.js source")
            table.insert(sessionsWithLoopJs, session)
            print("DEBUG: Now have " .. #sessionsWithLoopJs .. " sessions with loop.js")
            
            -- Signal ready when we have 2 sessions with loop.js
            if #sessionsWithLoopJs == 2 then
              print("DEBUG: We now have 2 sessions with loop.js - ready to test!")
              readyToTest.set(true)
            end
          end
        end)
      end)
      
      -- Start two sessions with loop.js to ensure continuous execution
      print("DEBUG: Starting session 1 with loop.js")
      start("loop.js")
      print("DEBUG: Starting session 2 with loop.js")
      start("loop.js")
      
      -- Wait for 2 sessions to load the loop.js source
      print("DEBUG: Waiting for 2 sessions to load loop.js source...")
      assert(vim.wait(15000, readyToTest.is_set), "Should have 2 sessions with loop.js source loaded")
      
      -- Now we can work with the sessions that loaded loop.js
      local session1 = sessionsWithLoopJs[1]
      local session2 = sessionsWithLoopJs[2]
      
      assert(session1, "First session should be available")
      assert(session2, "Second session should be available")
      
      print("DEBUG: Using session " .. tostring(session1.ref.id) .. " as session1")
      print("DEBUG: Using session " .. tostring(session2.ref.id) .. " as session2")
      
      local source1 = session1:getSourceFor({
        path = vim.fn.resolve("spec/fixtures/loop.js")
      })
      local source2 = session2:getSourceFor({
        path = vim.fn.resolve("spec/fixtures/loop.js")
      })
      
      assert(source1, "Source 1 should be found")
      assert(source2, "Source 2 should be found")
      
      -- Create breakpoints in session 1 and verify they sync to session 2
      -- Set breakpoints on lines 3 and 5 which are console.log lines in the loop
      source1:setBreakpoints({{line = 3}, {line = 5}})
      
      -- Verify both sessions see the breakpoints
      local breakpoints1 = source1:listBreakpoints()
      local breakpoints2 = source2:listBreakpoints()
      
      assert(#breakpoints1 == 2, "Session 1 should have 2 breakpoints")
      assert(#breakpoints2 == 2, "Session 2 should have 2 breakpoints")
      
      -- Verify they're the same breakpoints by checking IDs
      local ids1 = {}
      local ids2 = {}
      
      print("DEBUG: Listing session 1 breakpoints:")
      for i, bp in ipairs(breakpoints1) do
        print(string.format("DEBUG:   BP %d: ID=%s, line=%s", i, bp.id, bp.line))
        table.insert(ids1, bp.id)
      end
      
      print("DEBUG: Listing session 2 breakpoints:")
      for i, bp in ipairs(breakpoints2) do
        print(string.format("DEBUG:   BP %d: ID=%s, line=%s", i, bp.id, bp.line))
        table.insert(ids2, bp.id)
      end
      
      table.sort(ids1)
      table.sort(ids2)
      
      for i = 1, #ids1 do
        assert(ids1[i] == ids2[i], "Breakpoint IDs should match across sessions")
      end
      
      -- Wait for at least one session to hit breakpoints (due to loop.js's continuous execution)
      print("Waiting for breakpoints to be hit...")
      
      -- Wait for either session to hit a breakpoint first
      local either_session_hit = vim.wait(15000, function()
        return session1BreakpointHit.is_set() or session2BreakpointHit.is_set()
      end, 100)
      
      assert(either_session_hit, "At least one session should hit a breakpoint")
      
      if session1BreakpointHit.is_set() then
        print("Session 1 successfully hit a breakpoint!")
      end
      if session2BreakpointHit.is_set() then
        print("Session 2 successfully hit a breakpoint!")
      end
      
      print("Breakpoint hit detection across sessions works correctly!")
      
      -- Now remove breakpoints from session 2 and check if session 1 gets updated
      print("Now removing all breakpoints through session 2")
      source2:setBreakpoints({})
      
      -- Give a small delay for breakpoint changes to propagate using vim.wait
      vim.wait(100, function() return false end) -- Simple synchronous delay
      
      -- Both sessions should report no breakpoints
      local remainingBreakpoints1 = source1:listBreakpoints()
      local remainingBreakpoints2 = source2:listBreakpoints()
      assert(#remainingBreakpoints1 == 0, "Session 1 should have no breakpoints after removal")
      assert(#remainingBreakpoints2 == 0, "Session 2 should have no breakpoints after removal")
      
      print("\tBreakpoint sync and hit detection across sessions works correctly!")
    end)
  end)

  describe("Dynamic breakpoint management", function()
    it("should propagate breakpoint changes across sessions", function()
      print("\n\tTest: Dynamic breakpoint management\t")

      local api, start = prepare()

      local session1Initialized = nio.control.future()
      local session2Initialized = nio.control.future()
      
      -- Track sessions as they're created
      local sessionCount = 0
      api:onSession(function(session)
        sessionCount = sessionCount + 1
        if sessionCount == 1 then
          session1 = session
          session:onInitialized(session1Initialized.set, { once = true })
        elseif sessionCount == 2 then
          session2 = session
          session:onInitialized(session2Initialized.set, { once = true })
        end
      end)
      
      -- Start two sessions with the same file
      start("simple-debug.js")
      start("simple-debug.js")
      
      assert(vim.wait(10000, session1Initialized.is_set), "Session 1 should be initialized")
      assert(vim.wait(10000, session2Initialized.is_set), "Session 2 should be initialized")
      
      local source1 = session1:getSourceFor({
        path = vim.fn.resolve("spec/fixtures/simple-debug.js")
      })
      local source2 = session2:getSourceFor({
        path = vim.fn.resolve("spec/fixtures/simple-debug.js")
      })

      assert(source1)
      assert(source2)
      
      -- Initially no breakpoints
      assert(#source1:listBreakpoints() == 0, "Should start with no breakpoints")
      assert(#source2:listBreakpoints() == 0, "Should start with no breakpoints")
      
      -- Add a breakpoint through session 1
      source1:setBreakpoints({{line = 3}})
      
      -- Both sessions should see it
      assert(#source1:listBreakpoints() == 1, "Session 1 should have 1 breakpoint")
      assert(#source2:listBreakpoints() == 1, "Session 2 should have 1 breakpoint")
      
      -- Add another breakpoint through session 2
      source2:setBreakpoints({{line = 3}, {line = 5}})
      
      -- Both sessions should see both breakpoints
      local bp1_final = source1:listBreakpoints()
      local bp2_final = source2:listBreakpoints()
      
      assert(#bp1_final == 2, "Session 1 should have 2 breakpoints")
      assert(#bp2_final == 2, "Session 2 should have 2 breakpoints")
      
      -- Verify the breakpoints are on the expected lines
      local lines1 = vim.tbl_map(function(bp) return bp.line end, bp1_final)
      local lines2 = vim.tbl_map(function(bp) return bp.line end, bp2_final)
      
      table.sort(lines1)
      table.sort(lines2)
      
      assert(vim.deep_equal(lines1, {3, 5}), "Session 1 should have breakpoints on lines 3 and 5")
      assert(vim.deep_equal(lines2, {3, 5}), "Session 2 should have breakpoints on lines 3 and 5")
      
      -- Clear all breakpoints through session 1
      source1:setBreakpoints({})
      
      -- Both sessions should see no breakpoints
      assert(#source1:listBreakpoints() == 0, "Session 1 should have no breakpoints after clear")
      assert(#source2:listBreakpoints() == 0, "Session 2 should have no breakpoints after clear")
    end)
  end)
end)
