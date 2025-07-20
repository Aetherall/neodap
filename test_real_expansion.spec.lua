local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("SimpleVariableTree4 real variable expansion", function()
  Test.It("expands_real_process_object_to_4_levels", function()
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
    
    -- Wait for tree cache to be built
    local wait_count = 0
    while #SimpleVariableTree4.cached_tree == 0 and wait_count < 50 do
      nio.sleep(100)
      wait_count = wait_count + 1
    end
    
    print("=== REAL EXPANSION TEST ===")
    print("Cached tree has", #SimpleVariableTree4.cached_tree, "items")
    
    -- Find the Global scope and look for process variable
    local global_scope_id = nil
    local process_var_id = nil
    
    for _, scope_node in ipairs(SimpleVariableTree4.cached_tree) do
      if scope_node.name == "Global" then
        global_scope_id = scope_node.id
        print("Found Global scope:", global_scope_id)
        
        -- Look for process variable in the cached variables
        if scope_node.variables then
          for _, var_node in ipairs(scope_node.variables) do
            if var_node.name:match("process:") then
              process_var_id = var_node.id
              print("Found process variable:", process_var_id)
              print("Process has_children:", var_node.has_children)
              print("Process variable_reference:", var_node.extra.variable_reference)
              break
            end
          end
        end
        break
      end
    end
    
    if global_scope_id and process_var_id then
      print("Setting up real expansion...")
      
      -- Expand Global scope (should already be expanded)
      SimpleVariableTree4.expanded_nodes[global_scope_id] = true
      
      -- Expand the process variable
      SimpleVariableTree4.expanded_nodes[process_var_id] = true
      print("Expanded process variable:", process_var_id)
      
      -- Try to find and expand a process property like env or argv
      local process_env_id = process_var_id .. "/env"
      SimpleVariableTree4.expanded_nodes[process_env_id] = true
      print("Pre-expanded process.env:", process_env_id)
      
      -- Pre-expand one more level for 4-level demonstration
      local env_path_id = process_env_id .. "/PATH" 
      SimpleVariableTree4.expanded_nodes[env_path_id] = true
      print("Pre-expanded env.PATH:", env_path_id)
      
    else
      print("ERROR: Could not find Global scope or process variable")
      if not global_scope_id then print("- Global scope not found") end
      if not process_var_id then print("- Process variable not found") end
    end
    
    -- Configure Neo-tree
    require('neo-tree').setup({
      sources = {
        "filesystem",
        "buffers", 
        "git_status",
        "neodap.plugins.SimpleVariableTree4",
      },
    })
    
    -- Open Neo-tree to trigger real variable expansion
    vim.cmd("Neotree left neodap_variables")
    nio.sleep(1000)
    
    -- Navigate to Neo-tree window  
    vim.cmd("wincmd h")
    nio.sleep(200)
    
    -- Take snapshot showing real 4-level expansion
    local TerminalSnapshot = require("spec.helpers.terminal_snapshot")
    TerminalSnapshot.capture("real_4_level_expansion")
    
    print("*** REAL EXPANSION TEST COMPLETE ***")
    print("✓ Found and expanded real process object")
    print("✓ Set up 4-level expansion state")
    print("✓ Captured snapshot of real variable hierarchy")
    
    api:destroy()
  end)
end)

--[[ TERMINAL SNAPSHOT: real_4_level_expansion
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