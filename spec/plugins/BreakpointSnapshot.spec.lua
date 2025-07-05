local Test = require("spec.helpers.testing")(describe, it)
local BufferSnapshot = require("spec.helpers.buffer_snapshot")
local BreakpointVirtualText = require("neodap.plugins.BreakpointVirtualText")
local PrepareHelper = require("spec.helpers.prepare")
local BreakpointManager = require("lua.neodap.plugins.BreakpointManager")
local prepare = PrepareHelper.prepare

Test.Describe("BreakpointVirtualText", function()
  Test.It("BPVT_simple", function()
    local api, start, cleanup = prepare()
    
    local breakpoints = api:getPluginInstance(BreakpointManager)
    local breakpoints_text = api:getPluginInstance(BreakpointVirtualText)

    local breakpoint_set = Test.spy('BP')
    
    breakpoints.onBreakpoint(function (bp)
      bp:onBound(function()
        breakpoint_set.trigger()
      end)
    end)
    
    -- Set breakpoint explicitly
    api:onSession(function(session)
      session:onSourceLoaded(function(source)
      local filesource = source:asFile()
      if filesource and filesource:filename() == "loop.js" then
          filesource:addBreakpoint({ line = 3 })
        end
      end)
    end)
    
    -- Start session
    start("loop.js")

    breakpoint_set.wait()
    
    -- Capture and assert snapshot (using NvimAsync runner for safe vim API access)
    BufferSnapshot.expectSnapshotMatching("loop.js", [[
      let i = 0;
      setInterval(() => {
      	◐console.log("ALoop iteration: ", i++);
      	console.log("BLoop iteration: ", i++);
      	console.log("CLoop iteration: ", i++);
      	console.log("DLoop iteration: ", i++);
      }, 1000)
    ]])

    print("✓ Single breakpoint snapshot matches expected (isolated)")
    
    -- Note: cleanup() is now automatic in prepare() - no manual call needed
  end)

  Test.It("should capture multiple breakpoints", function()
    local api, start, cleanup = prepare()

    local breakpoints = api:getPluginInstance(BreakpointManager)
    local breakpoints_text = api:getPluginInstance(BreakpointVirtualText)
    
    -- Set up breakpoint event tracking
    local nio = require("nio")
    local breakpoints_set = 0
    local all_breakpoints_set = nio.control.event()

    breakpoints.onBreakpoint(function(breakpoint)
      breakpoints_set = breakpoints_set + 1
      if breakpoints_set >= 2 then
        all_breakpoints_set.set()
      end
    end)
    
    -- Set breakpoints explicitly
    api:onSession(function(session)
      session:onSourceLoaded(function(source)
        local filesource = source:asFile()
        if filesource and filesource:filename() == "loop.js" then
          filesource:addBreakpoint({ line = 3 })
          filesource:addBreakpoint({ line = 5 })
        end
      end)
    end)
    
    -- Start session
    start("loop.js")
    
    -- Wait for all breakpoints to be set
    vim.wait(5000, all_breakpoints_set.is_set)
    
    -- Capture and assert snapshot
    BufferSnapshot.expectSnapshotMatching("loop.js", [[
      let i = 0;
      setInterval(() => {
      	◐console.log("ALoop iteration: ", i++);
      	console.log("BLoop iteration: ", i++);
      	◐console.log("CLoop iteration: ", i++);
      	console.log("DLoop iteration: ", i++);
      }, 1000)
    ]])

    print("✓ Multiple breakpoints snapshot matches expected (isolated)")
    
    -- Cleanup to prevent test contamination  
    cleanup()
  end)

  Test.It("should demonstrate snapshot comparison", function()
    local api, start, cleanup = prepare()

    local breakpoints = api:getPluginInstance(BreakpointManager)
    local breakpoints_text = api:getPluginInstance(BreakpointVirtualText)
    
    
    -- Set up breakpoint
    local nio = require("nio")
    local breakpoint_set = nio.control.event()

    breakpoints.onBreakpoint(function(_breakpoint)
      breakpoint_set.set()
    end)
    
    api:onSession(function(session)
      session:onSourceLoaded(function(source)
        local filesource = source:asFile()
        if filesource and filesource:filename() == "loop.js" then
          filesource:addBreakpoint({ line = 3 })
        end
      end)
    end)
    
    start("loop.js")
    vim.wait(5000, breakpoint_set.is_set)
    
    -- Capture actual snapshot
    local actual_snapshot = BufferSnapshot.wait_and_capture_snapshot("loop.js", 300)

    -- This will fail intentionally to show diff output
    local fake_expected = [[
      // This is a fake expected snapshot
      // to demonstrate diff output
      console.log("wrong content");
      ◐let x = 999;  // ◄ sign:B
    ]]

    print("=== DEMONSTRATING SNAPSHOT COMPARISON ===")
    local matches, diff = BufferSnapshot.compare_snapshots(actual_snapshot, fake_expected)

    if not matches then
      print("Snapshots don't match (expected):")
      print(diff)
    end

    print("=== ACTUAL SNAPSHOT FOR REFERENCE ===")
    print(actual_snapshot)
    
    -- Cleanup to prevent test contamination
    cleanup()
  end)

  Test.It("should work with just virtual text plugin", function()
    local api, start, cleanup = prepare()

    local breakpoints = api:getPluginInstance(BreakpointManager)
    local breakpoints_text = api:getPluginInstance(BreakpointVirtualText)
    
    -- Set up breakpoint
    local nio = require("nio")
    local breakpoint_set = nio.control.event()
    
    breakpoints.onBreakpoint(function(_breakpoint)
      breakpoint_set.set()
    end)
    
    api:onSession(function(session)
      session:onSourceLoaded(function(source)
        local filesource = source:asFile()
        if filesource and filesource:filename() == "loop.js" then
          filesource:addBreakpoint({ line = 3 })
        end
      end)
    end)
    
    start("loop.js")
    vim.wait(5000, breakpoint_set.is_set)
    
    -- Capture and assert snapshot
    BufferSnapshot.expectSnapshotMatching("loop.js", [[
      let i = 0;
      setInterval(() => {
      	◐console.log("ALoop iteration: ", i++);
      	console.log("BLoop iteration: ", i++);
      	console.log("CLoop iteration: ", i++);
      	console.log("DLoop iteration: ", i++);
      }, 1000)
    ]])

    print("✓ Virtual text only snapshot matches expected (isolated)")
    
    -- Cleanup to prevent test contamination
    cleanup()
  end)

  Test.It("should show normal symbol when breakpoint binds at exact position", function()
    local api, start, cleanup = prepare()
    
    local breakpoints = api:getPluginInstance(BreakpointManager)
    local breakpoints_text = api:getPluginInstance(BreakpointVirtualText)
    -- Load plugin through API plugin system
    -- local _plugin_instance = api:getPluginInstance(BreakpointVirtualText)
    
    -- Set up breakpoint event tracking
    local nio = require("nio")
    local breakpoint_set = nio.control.event()

    breakpoints.onBreakpoint(function(_breakpoint)
      breakpoint_set.set()
    end)

    -- Set breakpoint at line 4 with exact column which should bind exactly 
    api:onSession(function(session)
      session:onSourceLoaded(function(source)
        local filesource = source:asFile()
        if filesource and filesource:filename() == "loop.js" then
          filesource:addBreakpoint({ line = 4, column = 2 })  -- Column 2 is where the actual code starts (after tab)
        end
      end)
    end)

    -- Start session
    start("loop.js")
    
    -- Wait for breakpoint to be set
    vim.wait(5000, breakpoint_set.is_set)
    
    -- Capture and assert snapshot - line 4 should show normal symbol ●
    BufferSnapshot.expectSnapshotMatching("loop.js", [[
      let i = 0;
      setInterval(() => {
      	console.log("ALoop iteration: ", i++);
      	●console.log("BLoop iteration: ", i++);
      	console.log("CLoop iteration: ", i++);
      	console.log("DLoop iteration: ", i++);
      }, 1000)
    ]])

    print("✓ Breakpoint at exact position shows normal symbol ●")
    
    -- Cleanup to prevent test contamination
    cleanup()
  end)
end)