local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare")

Test.Describe("breakpoints", function()
  Test.It("should hit", function()
    local api, start = prepare()

    -- Futures to track test completion
    local sessionInitialized = Test.spy("sessionInitialized")
    local breakpointCreated = Test.spy("breakpointCreated")
    local breakpointBound = Test.spy("breakpointBound")
    local breakpointHitViaBinding = Test.spy("breakpointHitViaBinding")
    local breakpointHitViaSession = Test.spy("breakpointHitViaSession")
    local breakpointHitViaSessionBound = Test.spy("breakpointHitViaSessionBound")
    local line3Hit = Test.spy("line3Hit")
    local line4Hit = Test.spy("line4Hit")

    -- Global breakpoint listener
    api:onBreakpoint(function(breakpoint)
      breakpointCreated.trigger()
      breakpoint:onBound(function(binding)
        breakpointBound.trigger()
        binding:onHit(breakpointHitViaBinding.trigger)
      end)
    end)

    api:onSession(function(session)

      session:onBindingHit(breakpointHitViaSession.trigger)
      session:onBinding(function(binding)
        binding:onHit(breakpointHitViaSessionBound.trigger)
      end)
      session:onInitialized(function()
        if session.id == 1 then return end
        sessionInitialized.trigger()
      end)
      session:onSourceLoaded(function(source)
        local filesource = source:asFile()
        if not filesource or filesource:filename() ~= "loop.js" then return end
        local line3 = source:addBreakpoint({ line = 3 })
        local line4 = source:addBreakpoint({ line = 4 })

        line3:onHit(function(hit)
          line3Hit.trigger()
          hit.thread:continue()
        end)

        line4:onHit(function(hit)
          line4Hit.trigger()
        end)
      end)
    end)

    start("loop.js")

    sessionInitialized.wait();
    breakpointCreated.wait();
    breakpointBound.wait();
    breakpointHitViaSessionBound.wait();
    breakpointHitViaSession.wait();
    breakpointHitViaBinding.wait();
    line3Hit.wait();
    line4Hit.wait();
  end)

  Test.It('should hit across sessions', function()
    local api, start = prepare()

    -- Futures to track test completion
    local breakpointBound1 = Test.spy("breakpointBound1")
    local breakpointBound2 = Test.spy("breakpointBound2")

    local breakpointHit1 = Test.spy("breakpointHit1")
    local breakpointHit2 = Test.spy("breakpointHit2")

    local session1Spy = Test.spy("session1")
    local session2Spy = Test.spy("session2")

    api:onSession(function(session)
      session:onSourceLoaded(function(source)
        if not source:isFile() or source:filename() ~= "loop.js" then return end

        if session1Spy.is_set() then
          session2Spy.trigger(session)
        else
          session1Spy.trigger(session)
        end
      end)
    end)

    start("loop.js")
    start("loop.js")

    ---@type api.Session
    local session1 = session1Spy.wait()
    ---@type api.Session
    local session2 = session2Spy.wait()

    session1:onBinding(breakpointBound1.trigger)
    session1:onBindingHit(breakpointHit1.trigger)

    session2:onBinding(breakpointBound2.trigger)
    session2:onBindingHit(breakpointHit2.trigger)


    local sourceInSession1 = session1:findSource(function(source)
      local filesource = source:asFile()
      if filesource and filesource:filename() == "loop.js" then
        return filesource
      end
    end)

    print("Source in session 1:", sourceInSession1:filename() .. "\n")

    sourceInSession1:addBreakpoint({ line = 3 })
    breakpointBound1.wait()
    breakpointBound2.wait()
  end)
end)
