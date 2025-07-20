local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("Pre-simplification baseline snapshot", function()
  Test.It("captures_working_state_before_architectural_changes", function()
    local api, start = prepare()
    api:getPluginInstance(SimpleVariableTree4)
    
    local stopped = Test.spy("stopped")
    
    api:onSession(function(session)
      if session.ref.id == 1 then return end
      
      session:onThread(function(thread)
        thread:onStopped(function(event)
          stopped.trigger()
        end)
        thread:pause()
      end)
    end)
    
    start("loop.js")
    stopped.wait()
    nio.sleep(500)
    
    -- Wait for tree cache
    local wait_count = 0
    while #SimpleVariableTree4.cached_tree == 0 and wait_count < 50 do
      nio.sleep(100)
      wait_count = wait_count + 1
    end
    
    -- Pre-expand process variable (current working pattern)
    for _, scope_node in ipairs(SimpleVariableTree4.cached_tree) do
      if scope_node.name == "Global" and scope_node.variables then
        for _, var_node in ipairs(scope_node.variables) do
          if var_node.name:match("process:") then
            SimpleVariableTree4.expanded_nodes[scope_node.id] = true
            SimpleVariableTree4.expanded_nodes[var_node.id] = true
            break
          end
        end
        break
      end
    end
    
    -- Configure Neo-tree
    require('neo-tree').setup({
      sources = {
        "filesystem",
        "neodap.plugins.SimpleVariableTree4",
      },
    })
    
    -- Open Neo-tree
    vim.cmd("Neotree left neodap_variables")
    nio.sleep(1000)
    
    -- Navigate to process variable area
    vim.cmd("wincmd h")
    nio.sleep(200)
    vim.cmd("normal! 3G")
    nio.sleep(100)
    vim.cmd("normal! 35j")  
    nio.sleep(300)
    
    -- Capture baseline snapshot
    local TerminalSnapshot = require("spec.helpers.terminal_snapshot")
    TerminalSnapshot.capture("baseline_before_simplification")
    
    print("*** BASELINE SNAPSHOT CAPTURED ***")
    print("This snapshot represents the working state before architectural simplification")
    print("Will be used to verify functionality is preserved after changes")
    
    api:destroy()
  end)
end)

--[[ TERMINAL SNAPSHOT: baseline_before_simplification
Size: 24x80
Cursor: [38, 0] (line 38, col 0)
Mode: n

 1| variable:   ▶ MessageChannel: ƒ () { mod│
 2| variable:   ▶ MessageEvent: ƒ () { mod ?│~
 3| variable:   ▶ MessagePort: ƒ () { mod ??│~
 4| variable:   ▶ performance: ƒ () { if (ch│~
 5| variable:   ▶ Performance: ƒ () { mod ??│~
 6| variable:   ▶ PerformanceEntry: ƒ () { m│~
 7| variable:   ▶ PerformanceMark: ƒ () { mo│~
 8| variable:   ▶ PerformanceMeasure: ƒ () {│~
 9| variable:   ▶ PerformanceObserver: ƒ () │~
10| variable:   ▶ PerformanceObserverEntryLi│~
11| variable:   ▶ PerformanceResourceTiming:│~
12| variable:   ▼ process: ƒ get() { return │~
13| variable:   ▶ queueMicrotask: ƒ queueMic│~
14| variable:   ▶ ReadableByteStreamControll│~
15| variable:   ▶ ReadableStream: ƒ () { mod│~
16| variable:   ▶ ReadableStreamBYOBReader: │~
17| variable:   ▶ ReadableStreamBYOBRequest:│~
18| variable:   ▶ ReadableStreamDefaultContr│~
19| variable:   ▶ ReadableStreamDefaultReade│~
20| variable:   ▶ Request: ƒ () { mod ??= re│~
21| variable:   ▶ Response: ƒ () { mod ??= r│~
22| variable:   ▶ setImmediate: ƒ setImmedia│~
23| <p_variables [1] [RO] 38,1           23% [No Name]            0,0-1          All
24| 
]]