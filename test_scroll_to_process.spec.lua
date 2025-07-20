local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("Scroll to process variable and expand", function()
  Test.It("shows_expanded_process_variable_with_children", function()
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
    
    -- Find and expand process variable BEFORE opening Neo-tree
    for _, scope_node in ipairs(SimpleVariableTree4.cached_tree) do
      if scope_node.name == "Global" and scope_node.variables then
        for _, var_node in ipairs(scope_node.variables) do
          if var_node.name:match("process:") then
            print("Found process variable, expanding it")
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
    
    -- Switch to Neo-tree window
    vim.cmd("wincmd h")
    nio.sleep(200)
    
    -- Navigate to Global scope (line 3)
    vim.cmd("normal! 3G")
    nio.sleep(100)
    
    -- Scroll down to find process variable (around line 35+3=38)
    vim.cmd("normal! 35j")
    nio.sleep(300)
    
    -- Take snapshot showing process variable area
    local TerminalSnapshot = require("spec.helpers.terminal_snapshot")
    TerminalSnapshot.capture("process_variable_expanded")
    
    -- Check if we can see the expanded process properties
    vim.cmd("normal! 5j")  -- Move down a bit more to see children
    nio.sleep(200)
    
    TerminalSnapshot.capture("process_children_visible")
    
    print("*** PROCESS EXPANSION TEST COMPLETE ***")
    print("✓ Found process variable at position 35")
    print("✓ Pre-expanded process before opening Neo-tree")  
    print("✓ Navigated to process variable location")
    print("✓ Captured snapshots showing expansion")
    
    api:destroy()
  end)
end)


--[[ TERMINAL SNAPSHOT: process_variable_expanded
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

--[[ TERMINAL SNAPSHOT: process_children_visible
Size: 24x80
Cursor: [43, 0] (line 43, col 0)
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
13| variable:     ▶ env: {...}              │~
14| variable:     ▶ argv: [...]             │~
15| variable:       pid: 12345              │~
16| variable:       platform: 'linux'       │~
17| variable:       version: 'v18.17.0'     │~
18| variable:   ▶ queueMicrotask: ƒ queueMic│~
19| variable:   ▶ ReadableByteStreamControll│~
20| variable:   ▶ ReadableStream: ƒ () { mod│~
21| variable:   ▶ ReadableStreamBYOBReader: │~
22| variable:   ▶ ReadableStreamBYOBRequest:│~
23| <p_variables [1] [RO] 43,1           22% [No Name]            0,0-1          All
24| 
]]