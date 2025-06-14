local prepare = require("spec.helpers.prepare")
local nio = require("nio")

describe("breakpoints", function()
  it("should_hit_a_breakpoint", function()
    print("\n\tTest: Breakpoint hit detection\t")
    local api, start = prepare()

    -- Futures to track test completion
    local sessionInitialized = nio.control.future()
    local breakpointCreated = nio.control.future()
    local breakpointBound = nio.control.future()
    local breakpointHitViaBinding = nio.control.future()
    local breakpointHitViaSession = nio.control.future()
    local breakpointHitViaSessionBound = nio.control.future()

    -- Global breakpoint listener
    api:onBreakpoint(function(breakpoint)
      print("DEBUG: Breakpoint created with ID: " .. tostring(breakpoint.id))
      if not breakpointCreated.is_set() then
        breakpointCreated.set(true)
      end

      breakpoint:onBound(function(binding)
        print("DEBUG: Global breakpoint bound to session: " .. tostring(binding.session.ref.id))
        if not breakpointBound.is_set() then
          breakpointBound.set(true)
        end

        binding:onHit(function(hit)
          print("DEBUG: Global breakpoint hit via binding at: " .. hit.source.path .. ":" .. hit.line)
          assert(hit, "Hit event should not be nil")
          assert(hit.source, "Hit should have source")
          assert(hit.source.path, "Hit source should have path")
          assert(hit.line, "Hit should have line number")
          if not breakpointHitViaBinding.is_set() then
            breakpointHitViaBinding.set(true)
          end
        end)
      end)
    end)

    api:onSession(function(session)
      if session.ref.id == 1 then return end

      -- Session-level breakpoint hit listener
      session:onBreakpointHit(function(binding, hit)
        print("DEBUG: Session breakpoint hit at: " .. hit.source.path .. ":" .. hit.line)
        assert(binding, "Binding should not be nil")
        assert(hit, "Hit event should not be nil")
        assert(hit.source, "Hit should have source")
        assert(hit.source.path, "Hit source should have path")
        assert(hit.line, "Hit should have line number")
        if not breakpointHitViaSession.is_set() then
          breakpointHitViaSession.set(true)
        end
      end)

      -- Session-level breakpoint bound listener
      session:onBreakpointBound(function(binding)
        print("DEBUG: Session breakpoint bound")
        assert(binding, "Binding should not be nil")

        binding:onHit(function(hit)
          print("DEBUG: Breakpoint hit via session bound at: " .. hit.source.path .. ":" .. hit.line)
          assert(hit, "Hit event should not be nil")
          assert(hit.source, "Hit should have source")
          assert(hit.source.path, "Hit source should have path")
          assert(hit.line, "Hit should have line number")
          if not breakpointHitViaSessionBound.is_set() then
            breakpointHitViaSessionBound.set(true)
          end
        end)
      end)

      -- Wait for session to be initialized, then set breakpoints
      session:onInitialized(function()
        print("DEBUG: Session initialized, setting breakpoints")
        sessionInitialized.set(true)

        -- Set breakpoints on the loop file
        session.ref.calls:setBreakpoints({
          source = {
            path = vim.fn.fnamemodify("spec/fixtures/loop.js", ":p")
          },
          breakpoints = {
            { line = 3 }, -- console.log("ALoop iteration: ", i++);
            { line = 4 }  -- console.log("BLoop iteration: ", i++);
          }
        }):wait()
        print("DEBUG: Breakpoints set successfully")
      end, { once = true })
    end)

    start("loop.js")

    -- Wait for all events to complete with timeouts
    assert(vim.wait(10000, sessionInitialized.is_set), "Session should be initialized")
    assert(vim.wait(10000, breakpointCreated.is_set), "Breakpoint should be created")
    assert(vim.wait(10000, breakpointBound.is_set), "Breakpoint should be bound")

    -- Wait for breakpoint hits (the loop runs every 1000ms, so give it enough time)
    assert(vim.wait(15000, breakpointHitViaBinding.is_set), "Breakpoint should be hit via binding listener")
    assert(vim.wait(5000, breakpointHitViaSession.is_set), "Breakpoint should be hit via session listener")
    assert(vim.wait(5000, breakpointHitViaSessionBound.is_set), "Breakpoint should be hit via session bound listener")

    print("DEBUG: All breakpoint events completed successfully")
  end)

  it("should_create_and_bind_breakpoints", function()
    print("\n\tTest: Breakpoint creation and binding\t")
    local api, start = prepare()

    local sessionInitialized = nio.control.future()
    local breakpointCreated = nio.control.future()
    local breakpointBound = nio.control.future()
    local sourceLoaded = nio.control.future()

    -- Track breakpoint creation
    api:onBreakpoint(function(breakpoint)
      print("DEBUG: Global breakpoint created with ID: " .. tostring(breakpoint.id))
      assert(breakpoint, "Breakpoint should not be nil")
      assert(breakpoint.id, "Breakpoint should have an ID")
      if not breakpointCreated.is_set() then
        breakpointCreated.set(true)
      end

      breakpoint:onBound(function(binding)
        print("DEBUG: Breakpoint bound to session")
        assert(binding, "Binding should not be nil")
        assert(binding.session, "Binding should have a session")
        if not breakpointBound.is_set() then
          breakpointBound.set(true)
        end
      end)
    end)

    api:onSession(function(session)
      if session.ref.id == 1 then return end

      session:onSourceLoaded(function(source)
        if source:isFile() and source:filename() == "loop.js" then
          print("DEBUG: Source loaded: " .. source:filename())
          if not sourceLoaded.is_set() then
            sourceLoaded.set(true)
          end
        end
      end)

      session:onInitialized(function()
        print("DEBUG: Session initialized")
        sessionInitialized.set(true)
      end, { once = true })
    end)

    start("loop.js")

    -- Wait for initialization and source loading
    assert(vim.wait(10000, sessionInitialized.is_set), "Session should be initialized")
    assert(vim.wait(10000, sourceLoaded.is_set), "Source should be loaded")

    -- Now set breakpoints via the API
    local session = nil
    for s in api:eachSession() do
      if s.ref.id ~= 1 then
        session = s
        break
      end
    end

    assert(session, "Should have a valid session")

    local source = session:getSourceFor({
      path = vim.fn.resolve("spec/fixtures/loop.js")
    })

    assert(source, "Should be able to get source")

    -- Set breakpoints through the source interface
    source:setBreakpoints({ { line = 3 }, { line = 4 } })

    -- Wait for breakpoint events
    assert(vim.wait(10000, breakpointCreated.is_set), "Breakpoint should be created")
    assert(vim.wait(10000, breakpointBound.is_set), "Breakpoint should be bound")

    print("DEBUG: Breakpoint creation and binding test completed successfully")
  end)

  it("should_handle_multiple_sessions", function()
    print("\n\tTest: Multiple session breakpoint handling\t")
    local api, start = prepare()

    local session1Initialized = nio.control.future()
    local session2Initialized = nio.control.future()
    local breakpointSharedAcrossSessions = nio.control.future()
    local sessionCount = 0

    api:onBreakpoint(function(breakpoint)
      print("DEBUG: Breakpoint created for multiple sessions")
    end)

    api:onSession(function(session)
      -- Skip the mock/parent session with ID 1
      if session.ref.id == 1 then return end

      sessionCount = sessionCount + 1
      print("DEBUG: Session " .. sessionCount .. " created with ID: " .. tostring(session.ref.id))

      if sessionCount == 1 then
        session:onInitialized(function()
          session1Initialized.set(true)
        end, { once = true })
      elseif sessionCount == 2 then
        session:onInitialized(function()
          session2Initialized.set(true)
        end, { once = true })
      end
    end)

    -- Start two sessions
    start("loop.js")
    start("loop.js")

    -- Wait for both sessions to initialize
    assert(vim.wait(10000, session1Initialized.is_set), "Session 1 should be initialized")
    assert(vim.wait(10000, session2Initialized.is_set), "Session 2 should be initialized")

    -- Get both sessions
    local sessions = {}
    for session in api:eachSession() do
      if session.ref.id ~= 1 then
        table.insert(sessions, session)
      end
    end

    assert(#sessions >= 2, "Should have at least 2 sessions, got " .. #sessions)

    -- Set breakpoints on the first session and verify they're shared
    local source1 = sessions[1]:getSourceFor({
      path = vim.fn.resolve("spec/fixtures/loop.js")
    })
    local source2 = sessions[2]:getSourceFor({
      path = vim.fn.resolve("spec/fixtures/loop.js")
    })

    assert(source1, "Source 1 should be available")
    assert(source2, "Source 2 should be available")

    -- Set breakpoints on first session
    source1:setBreakpoints({ { line = 3 } })

    -- Verify both sessions see the breakpoint
    local bp1 = source1:listBreakpoints()
    local bp2 = source2:listBreakpoints()

    assert(#bp1 > 0, "Session 1 should have breakpoints")
    assert(#bp2 > 0, "Session 2 should have breakpoints")
    assert(bp1[1].id == bp2[1].id, "Both sessions should share the same breakpoint")

    breakpointSharedAcrossSessions.set(true)

    assert(vim.wait(5000, breakpointSharedAcrossSessions.is_set), "Breakpoints should be shared across sessions")

    print("DEBUG: Multiple session breakpoint test completed successfully")
  end)
end)
