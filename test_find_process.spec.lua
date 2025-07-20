local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("Find process variable position", function()
  Test.It("locates_process_variable_in_tree", function()
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
    
    -- Find process and expand it
    for _, scope_node in ipairs(SimpleVariableTree4.cached_tree) do
      if scope_node.name == "Global" and scope_node.variables then
        for i, var_node in ipairs(scope_node.variables) do
          print(i .. ":", var_node.name)
          if var_node.name:match("process:") then
            print("*** FOUND PROCESS AT POSITION", i, "***")
            print("Process ID:", var_node.id)
            print("Process variable_reference:", var_node.extra.variable_reference)
            
            -- Set expansion
            SimpleVariableTree4.expanded_nodes[scope_node.id] = true
            SimpleVariableTree4.expanded_nodes[var_node.id] = true
            
            print("Set expansion for:", var_node.id)
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
    
    -- Open and navigate to around line where process should be
    vim.cmd("Neotree left neodap_variables")
    nio.sleep(1000)
    
    vim.cmd("wincmd h")  -- Switch to Neo-tree
    nio.sleep(200)
    
    -- Try to navigate to the process variable area
    -- Since Global is line 3, and process might be later, let's search
    vim.api.nvim_feedkeys("/process\r", "n", false)
    nio.sleep(300)
    
    -- Take snapshot around the process variable
    local TerminalSnapshot = require("spec.helpers.terminal_snapshot")
    TerminalSnapshot.capture("process_variable_location")
    
    api:destroy()
  end)
end)

--[[ TERMINAL SNAPSHOT: process_variable_location
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| scope: ▶ Local                          │
 2| scope: ▶ Closure                        │~
 3| scope: ▼ Global                         │~
 4| variable:   ▶ AbortController: ƒ () { mo│~
 5| variable:   ▶ AbortSignal: ƒ () { mod ??│~
 6| variable:   ▶ atob: ƒ () { mod ??= requi│~
 7| variable:   ▶ Blob: ƒ () { mod ??= requi│~
 8| variable:   ▶ BroadcastChannel: ƒ () { m│~
 9| variable:   ▶ btoa: ƒ () { mod ??= requi│~
10| variable:   ▶ Buffer: ƒ get() { return _│~
11| variable:   ▶ ByteLengthQueuingStrategy:│~
12| variable:   ▶ clearImmediate: ƒ clearImm│~
13| variable:   ▶ clearInterval: ƒ clearInte│~
14| variable:   ▶ clearTimeout: ƒ clearTimeo│~
15| variable:   ▶ CompressionStream: ƒ () { │~
16| variable:   ▶ CountQueuingStrategy: ƒ ()│~
17| variable:   ▶ crypto: ƒ () { if (check !│~
18| variable:   ▶ Crypto: ƒ () { mod ??= req│~
19| variable:   ▶ CryptoKey: ƒ () { mod ??= │~
20| variable:   ▶ DecompressionStream: ƒ () │~
21| variable:   ▶ DOMException: () => { cons│~
22| variable:   ▶ fetch: ƒ fetch(input, init│~
23| <p_variables [1] [RO] 1,1            Top [No Name]            0,0-1          All
24| 
]]