local Test = require("spec.helpers.testing")(describe, it)
local P = require("spec.helpers.prepare")
local prepare = P.prepare
local NewBreakpointManager = require("neodap.api.Breakpoint.BreakpointManager")
local Location = require("neodap.api.Breakpoint.Location")
local nio = require("nio")

Test.Describe("breakpoint range toggle", function()
  Test.It("should toggle breakpoint at position between original and adjusted", function()
    local api, start = prepare()
    
    -- Create new breakpoint manager
    local breakpointManager = NewBreakpointManager.create(api)
    
    local breakpointAdded = Test.spy("breakpointAdded")
    local bindingBound = Test.spy("bindingBound")
    local sessionInitialized = Test.spy("sessionInitialized")
    local sourceLoaded = Test.spy("sourceLoaded")
    
    breakpointManager:onBreakpoint(function(breakpoint)
      print("✓ Breakpoint added:", breakpoint.id)
      breakpointAdded.trigger()
      
      breakpoint:onBinding(function(binding)
        print("✓ Binding created - requested:", binding.line, binding.column, "actual:", binding.actualLine, binding.actualColumn)
        bindingBound.trigger()
      end)
    end)
    
    -- Create breakpoint at column 0 (will be moved to column 2 by DAP)
    local originalLocation = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 0,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:0"
    })
    
    print("Creating breakpoint at:", originalLocation.key)
    local breakpoint = breakpointManager:addBreakpoint(originalLocation)
    breakpointAdded.wait()
    
    -- Start session
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
    
    print("Starting session...")
    start("loop.js")
    
    sessionInitialized.wait()
    sourceLoaded.wait()
    bindingBound.wait()
    nio.sleep(200)
    
    -- Verify breakpoint was adjusted
    local binding = breakpoint:getBindings():first()
    assert(binding ~= nil, "Binding should exist")
    print("Breakpoint adjusted from column", binding.column, "to column", binding.actualColumn)
    
    -- Test toggle at position between original (0) and adjusted (2) - try column 1
    local middleLocation = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js", 
      line = 3,
      column = 1,  -- Between 0 and 2
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:1"
    })
    
    print("=== Testing Toggle at Middle Position ===")
    print("Toggling at:", middleLocation.key)
    
    -- Count breakpoints before
    local beforeCount = breakpointManager.breakpoints:count()
    print("Breakpoints before toggle:", beforeCount)
    
    -- Perform toggle
    local result = breakpointManager:toggleBreakpoint(middleLocation)
    
    -- Count breakpoints after
    local afterCount = breakpointManager.breakpoints:count()
    print("Breakpoints after toggle:", afterCount)
    print("Toggle result:", result and "new breakpoint created" or "existing breakpoint removed")
    
    -- Should have removed the existing breakpoint
    assert(result == nil, "Toggle should return nil when removing existing breakpoint")
    assert(afterCount == 0, "Should have 0 breakpoints after toggle removes existing one")
    
    print("✓ Successfully toggled breakpoint at middle position!")
  end)
end)
