local Test = require("spec.helpers.testing")(describe, it)
local P = require("spec.helpers.prepare")
local prepare = P.prepare
local NewBreakpointManager = require("neodap.api.Breakpoint.BreakpointManager")
local Location = require("neodap.api.Breakpoint.Location")
local nio = require("nio")

Test.Describe("breakpoint multiline range matching", function()
  Test.It("should match breakpoint when adjusted to next line", function()
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
    
    -- Create breakpoint at line 3, column 0 (will be moved to line 4, column 2 by DAP)
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
    
    start("loop.js")
    sessionInitialized.wait()
    sourceLoaded.wait()
    bindingBound.wait()
    
    -- Simulate DAP adjusting the breakpoint to next line
    local binding = breakpoint:getBindings():first()
    if binding then
      binding.actualLine = 4
      binding.actualColumn = 2
    end
    
    print("Breakpoint adjusted from line 3 column 0 to line 4 column 2")
    
    -- Test range matching at various positions between original and adjusted
    local testPositions = {
      {line = 3, column = 0, desc = "original position"},
      {line = 3, column = 5, desc = "same line, later column"},
      {line = 3, column = 10, desc = "same line, end of line"},
      {line = 4, column = 0, desc = "next line, start"},
      {line = 4, column = 1, desc = "next line, before adjusted"},
      {line = 4, column = 2, desc = "adjusted position"},
    }
    
    for _, pos in ipairs(testPositions) do
      local testLocation = Location.SourceFile:new({
        path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
        line = pos.line,
        column = pos.column,
        key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:" .. pos.line .. ":" .. pos.column
      })
      
      print("Testing position", pos.desc, "(" .. pos.line .. ":" .. pos.column .. ")")
      local breakpoints = breakpointManager.breakpoints:atLocation(testLocation)
      assert(breakpoints:count() == 1, "Should find breakpoint at " .. pos.desc)
      print("✓ Found breakpoint at", pos.desc)
    end
    
    -- Test positions that should NOT match (outside the range)
    local outsidePositions = {
      {line = 2, column = 0, desc = "line before original"},
      {line = 5, column = 0, desc = "line after adjusted"},
      {line = 4, column = 3, desc = "next line, after adjusted column"},
    }
    
    for _, pos in ipairs(outsidePositions) do
      local testLocation = Location.SourceFile:new({
        path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
        line = pos.line,
        column = pos.column,
        key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:" .. pos.line .. ":" .. pos.column
      })
      
      print("Testing position outside range", pos.desc, "(" .. pos.line .. ":" .. pos.column .. ")")
      local breakpoints = breakpointManager.breakpoints:atLocation(testLocation)
      assert(breakpoints:count() == 0, "Should NOT find breakpoint at " .. pos.desc)
      print("✓ Correctly excluded position at", pos.desc)
    end
    
    print("✓ Multiline range matching test completed successfully!")
  end)
  
  Test.It("should handle reverse adjustment from later line to earlier line", function()
    local api, start = prepare()
    
    -- Create new breakpoint manager
    local breakpointManager = NewBreakpointManager.create(api)
    
    local breakpointAdded = Test.spy("breakpointAdded")
    local bindingBound = Test.spy("bindingBound")
    local sessionInitialized = Test.spy("sessionInitialized")
    local sourceLoaded = Test.spy("sourceLoaded")
    
    breakpointManager:onBreakpoint(function(breakpoint)
      breakpointAdded.trigger()
      breakpoint:onBinding(function(binding)
        bindingBound.trigger()
      end)
    end)
    
    -- Create breakpoint at line 5, column 10 (will be moved to line 3, column 2 by DAP)
    local originalLocation = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 5,
      column = 10,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:5:10"
    })
    
    local breakpoint = breakpointManager:addBreakpoint(originalLocation)
    breakpointAdded.wait()
    
    -- Start session
    api:onSession(function(session)
      session:onInitialized(sessionInitialized.trigger)
      session:onSourceLoaded(function(source)
        local fileSource = source:asFile()
        if fileSource and fileSource:filename() == "loop.js" then
          sourceLoaded.trigger()
        end
      end)
    end)
    
    start("loop.js")
    sessionInitialized.wait()
    sourceLoaded.wait()
    bindingBound.wait()
    
    -- Simulate DAP adjusting the breakpoint to earlier line
    local binding = breakpoint:getBindings():first()
    if binding then
      binding.actualLine = 3
      binding.actualColumn = 2
    end
    
    print("Breakpoint adjusted backwards from line 5 column 10 to line 3 column 2")
    
    -- Test that positions between the adjusted and original are matched
    local testPositions = {
      {line = 3, column = 2, desc = "adjusted position"},
      {line = 3, column = 5, desc = "adjusted line, later column"},
      {line = 4, column = 0, desc = "middle line, any column"},
      {line = 4, column = 15, desc = "middle line, late column"},
      {line = 5, column = 0, desc = "original line, early column"},
      {line = 5, column = 10, desc = "original position"},
    }
    
    for _, pos in ipairs(testPositions) do
      local testLocation = Location.SourceFile:new({
        path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
        line = pos.line,
        column = pos.column,
        key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:" .. pos.line .. ":" .. pos.column
      })
      
      local breakpoints = breakpointManager.breakpoints:atLocation(testLocation)
      assert(breakpoints:count() == 1, "Should find breakpoint at " .. pos.desc)
      print("✓ Found breakpoint at", pos.desc)
    end
    
    print("✓ Reverse multiline range matching test completed successfully!")
  end)
end)
