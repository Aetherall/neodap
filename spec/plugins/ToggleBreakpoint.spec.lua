local Test = require("spec.helpers.testing")(describe, it)
local P = require("spec.helpers.prepare")
local prepare = P.prepare
local BreakpointManagerPlugin = require("neodap.plugins.BreakpointManager")
local ToggleBreakpoint = require("neodap.plugins.ToggleBreakpoint")
local Location = require("neodap.api.Breakpoint.Location")
local nio = require("nio")

Test.Describe("ToggleBreakpoint plugin", function()
  Test.It("should prevent duplicate breakpoints when DAP adjusts position", function()
    local api, start = prepare()
    
    -- Initialize the breakpoint manager and toggle plugins
    local breakpointManagerApi = api:getPluginInstance(BreakpointManagerPlugin)
    local togglePlugin = ToggleBreakpoint.plugin(api)
    
    local sessionInitialized = Test.spy("sessionInitialized")
    local sourceLoaded = Test.spy("sourceLoaded")
    local firstBreakpointAdded = Test.spy("firstBreakpointAdded")
    
    -- Track breakpoint additions
    breakpointManagerApi.onBreakpoint(function(breakpoint)
      print("✓ Breakpoint added:", breakpoint.id)
      firstBreakpointAdded.trigger()
    end)
    
    -- Set up session event tracking
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
    
    -- Start session first to test smart placement with active session
    start("loop.js")
    sessionInitialized.wait()
    sourceLoaded.wait()
    nio.sleep(200)
    
    -- Create first breakpoint at column 2 using toggle
    local location1 = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 2,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:2"
    })
    
    print("Creating first breakpoint at column 2...")
    local breakpoint1 = togglePlugin:toggle(location1)
    assert(breakpoint1 ~= nil, "First breakpoint should be created")
    
    firstBreakpointAdded.wait()
    print("✓ First breakpoint created")
    
    -- Wait for binding to be created
    nio.sleep(300)
    
    -- Now try to create second breakpoint at column 0 (should detect existing at column 2)
    local location2 = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 0,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:0"
    })
    
    print("Attempting to create second breakpoint at column 0...")
    local breakpoint2 = togglePlugin:toggle(location2)
    
    -- Smart placement should either prevent duplicate or toggle off the existing breakpoint
    if breakpoint2 == nil then
      print("✓ Smart placement correctly handled duplicate - either prevented or toggled off existing")
      -- Check if the existing breakpoint was toggled off (this is actually correct toggle behavior)
      local totalBreakpoints = breakpointManagerApi.getBreakpoints():count()
      if totalBreakpoints == 0 then
        print("✓ Toggle correctly removed existing breakpoint when user clicked at equivalent location")
      else
        print("✓ Smart placement prevented duplicate breakpoint creation")
        assert(totalBreakpoints == 1, "Should still have only 1 breakpoint, found: " .. totalBreakpoints)
      end
    elseif breakpoint1 and breakpoint2 and breakpoint2.id == breakpoint1.id then
      print("✓ Smart placement returned existing breakpoint instead of creating duplicate")
      local totalBreakpoints = breakpointManagerApi.getBreakpoints():count()
      assert(totalBreakpoints == 1, "Should still have only 1 breakpoint, found: " .. totalBreakpoints)
    else
      local id = breakpoint2 and breakpoint2.id or "nil"
      error("Smart placement failed: unexpected result - breakpoint2 id: " .. id)
    end
    
    print("✓ Smart breakpoint placement test passed")
  end)

  Test.It("should toggle existing breakpoint at adjusted location", function()
    local api, start = prepare()
    
    -- Initialize the breakpoint manager and toggle plugins
    local breakpointManagerApi = api:getPluginInstance(BreakpointManagerPlugin)
    local togglePlugin = ToggleBreakpoint.plugin(api)
    
    local sessionInitialized = Test.spy("sessionInitialized")
    local sourceLoaded = Test.spy("sourceLoaded")
    
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
    nio.sleep(200)
    
    -- Create breakpoint at column 5 (middle of statement)
    local location = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 5,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:5"
    })
    
    print("Toggling breakpoint at column 5...")
    local breakpoint = togglePlugin:toggle(location)
    assert(breakpoint ~= nil, "Breakpoint should be created")
    print("✓ Breakpoint created with id:", breakpoint.id)
    
    nio.sleep(200)
    
    -- Toggle again at column 0 - should remove the existing breakpoint
    local location2 = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 0,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:0"
    })
    
    print("Toggling again at column 0...")
    local result = togglePlugin:toggle(location2)
    assert(result == nil, "Toggle should remove existing breakpoint")
    
    -- Verify breakpoint was removed
    assert(breakpointManagerApi.getBreakpoints():count() == 0, "Breakpoint should be removed")
    print("✓ Breakpoint successfully toggled off")
  end)

  Test.It("should adjust location when no session active", function()
    local api, _start = prepare()
    
    -- Initialize the breakpoint manager and toggle plugins
    local breakpointManagerApi = api:getPluginInstance(BreakpointManagerPlugin)
    local togglePlugin = ToggleBreakpoint.plugin(api)
    
    -- Create breakpoint without any active session
    local location = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 5,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:5"
    })
    
    print("Adjusting location without active session...")
    local adjusted = togglePlugin:adjustLocation(location)
    
    assert(adjusted ~= nil, "Adjusted location should be returned")
    assert(adjusted.column == 0, "Should fallback to column 0, got: " .. adjusted.column)
    print("✓ Location adjusted to column 0")
  end)

  Test.It("should clear breakpoint at exact and adjusted locations", function()
    local api, _start = prepare()
    
    -- Initialize the breakpoint manager and toggle plugins
    local breakpointManagerApi = api:getPluginInstance(BreakpointManagerPlugin)
    local togglePlugin = ToggleBreakpoint.plugin(api)
    
    -- Create a breakpoint at column 0
    local location = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 0,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:0"
    })
    
    local breakpoint = breakpointManagerApi.setBreakpoint(location)
    assert(breakpoint ~= nil, "Breakpoint should be created")
    
    -- Try to clear at column 5 (should find the breakpoint at column 0)
    local clearLocation = Location.SourceFile:new({
      path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
      line = 3,
      column = 5,
      key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:3:5"
    })
    
    print("Clearing breakpoint from column 5...")
    local cleared = togglePlugin:clear(clearLocation)
    assert(cleared == true, "Should clear breakpoint at adjusted location")
    assert(breakpointManagerApi.getBreakpoints():count() == 0, "Breakpoint should be removed")
    print("✓ Breakpoint cleared successfully")
  end)

  Test.It("should clear all breakpoints", function()
    local api, _start = prepare()
    
    -- Initialize the breakpoint manager and toggle plugins
    local breakpointManagerApi = api:getPluginInstance(BreakpointManagerPlugin)
    local togglePlugin = ToggleBreakpoint.plugin(api)
    
    -- Create multiple breakpoints
    for i = 1, 5 do
      local location = Location.SourceFile:new({
        path = vim.fn.getcwd() .. "/spec/fixtures/loop.js",
        line = i + 2,
        column = 0,
        key = vim.fn.getcwd() .. "/spec/fixtures/loop.js:" .. (i + 2) .. ":0"
      })
      breakpointManagerApi.setBreakpoint(location)
    end
    
    assert(breakpointManagerApi.getBreakpoints():count() == 5, "Should have 5 breakpoints")
    
    print("Clearing all breakpoints...")
    togglePlugin:clearAll()
    
    assert(breakpointManagerApi.getBreakpoints():count() == 0, "All breakpoints should be removed")
    print("✓ All breakpoints cleared successfully")
  end)
end)