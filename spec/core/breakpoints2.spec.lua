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

    -- Global breakpoint listener
    api:onBreakpoint(function(breakpoint)
      breakpointCreated.trigger()
      breakpoint:onBound(function(binding)
        breakpointBound.trigger()
        binding:onHit(breakpointHitViaBinding.trigger)
      end)
    end)

    api:onSession(function(session)
      session:onBreakpointHit(breakpointHitViaSession.trigger)
      session:onBreakpointBound(function(binding)
        binding:onHit(breakpointHitViaSessionBound.trigger)
      end)
      session:onInitialized(function()
        sessionInitialized.trigger()
        session:onSourceLoaded(function(source)
          if source:isFile() and source:filename() ~= "loop.js" then return end
          source:setBreakpoints({
            { line = 3 }, -- console.log("ALoop iteration: ", i++);
            { line = 4 }, -- console.log("BLoop iteration: ", i++);
          })
        end)
      end)
    end)

    start("loop.js")

    sessionInitialized.wait();
    breakpointCreated.wait();
    breakpointBound.wait();
    breakpointHitViaBinding.wait();
    breakpointHitViaSession.wait();
    breakpointHitViaSessionBound.wait();
  end)
end)
