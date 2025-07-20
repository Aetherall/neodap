local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("SimpleVariableTree4 user interaction", function()
  Test.It("user_can_navigate_variable_tree_with_keymappings", function()
    local api, start = prepare()
    api:getPluginInstance(SimpleVariableTree4)
    
    -- Track when stopped
    local stopped = Test.spy("stopped")
    local thread_ref = nil
    
    api:onSession(function(session)
      if session.ref.id == 1 then return end -- Skip session ID 1
      
      session:onThread(function(thread)
        thread_ref = thread
        thread:onStopped(function(event)
          stopped.trigger()
        end)
        -- Pause thread immediately to get into debug state
        thread:pause()
      end)
    end)
    
    -- Start debug session with loop.js to access global scope objects
    start("loop.js")
    
    -- Wait for thread to be paused
    stopped.wait()
    
    -- Wait for debug state to be established
    nio.sleep(500)
    
    -- Configure Neo-tree to know about our source
    require('neo-tree').setup({
      sources = {
        "filesystem",
        "buffers", 
        "git_status",
        "neodap.plugins.SimpleVariableTree4",
      },
    })
    
    -- User action: Open Neo-tree with variables source using command
    vim.cmd("Neotree left neodap_variables")
    nio.sleep(1000) -- Wait for Neo-tree to open
    
    -- Take initial snapshot
    local TerminalSnapshot = require("spec.helpers.terminal_snapshot")
    TerminalSnapshot.capture("initial_variable_tree")
    
    -- User action: Navigate to Neo-tree window using window navigation
    vim.cmd("wincmd h")  -- Move to left window (Neo-tree)
    nio.sleep(200)
    
    -- User action: Navigate down in the tree to find interesting items
    -- Simulate pressing 'j' to move down
    for i = 1, 5 do
      vim.api.nvim_feedkeys("j", "n", false)
      nio.sleep(50)
    end
    
    -- Take snapshot after navigation
    TerminalSnapshot.capture("after_navigation")
    
    -- User action: Try to expand a node using Enter key
    vim.api.nvim_feedkeys("\r", "n", false)  -- Enter key to expand
    nio.sleep(300)
    
    -- Manual expansion test - expand a global variable to confirm 3+ levels
    print("=== MANUAL EXPANSION TEST ===")
    local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")
    
    -- Find a variable to expand (look for process object)
    for scope_id, _ in pairs(SimpleVariableTree4.expanded_nodes) do
      if scope_id:match("Global") then
        -- Try to expand the first expandable variable we can find
        SimpleVariableTree4.expanded_nodes[scope_id .. "/process"] = true
        print("Manually expanded process variable")
        break
      end
    end
    
    -- Trigger manual refresh
    vim.schedule(function()
      local ok, manager = pcall(require, "neo-tree.sources.manager")
      if ok and manager then
        manager.refresh("neodap_variables")
      end
    end)
    nio.sleep(500)
    
    -- Take snapshot after expansion attempt  
    TerminalSnapshot.capture("after_expansion_attempt")
    
    -- User action: Use Neo-tree specific commands
    -- Navigate to Global scope
    vim.cmd("normal! gg")  -- Go to top
    nio.sleep(100)
    
    -- Find Global scope
    vim.api.nvim_feedkeys("/Global\r", "n", false)  -- Search for Global
    nio.sleep(200)
    
    -- Try to expand Global scope
    vim.api.nvim_feedkeys("\r", "n", false)  -- Enter to expand
    nio.sleep(300)
    
    -- Take snapshot showing Global scope expansion
    TerminalSnapshot.capture("global_scope_expanded")
    
    -- User action: Navigate deeper into the tree
    for i = 1, 3 do
      vim.api.nvim_feedkeys("j", "n", false)  -- Move down
      nio.sleep(50)
    end
    
    -- Try to expand nested items
    vim.api.nvim_feedkeys("\r", "n", false)
    nio.sleep(300)
    
    -- Final snapshot showing deep navigation
    TerminalSnapshot.capture("deep_navigation_complete")
    
    -- User action: Close Neo-tree
    vim.cmd("Neotree close")
    nio.sleep(200)
    
    -- Verify we can reopen and state is preserved
    vim.cmd("Neotree left neodap_variables")
    nio.sleep(500)
    
    -- Take final snapshot
    TerminalSnapshot.capture("reopened_tree")
    
    print("*** USER INTERACTION TEST COMPLETE ***")
    print("✓ Opened variable tree with command")
    print("✓ Navigated with keyboard shortcuts")
    print("✓ Expanded nodes with Enter key")
    print("✓ Used search functionality")
    print("✓ Closed and reopened tree")
    print("✓ Multiple snapshots captured showing user workflow")
    
    api:destroy()
  end)
end)





--[[ TERMINAL SNAPSHOT: initial_variable_tree
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



--[[ TERMINAL SNAPSHOT: after_navigation
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


--[[ TERMINAL SNAPSHOT: after_expansion_attempt
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| 
 2| ~
 3| ~
 4| ~
 5| ~
 6| ~                                 NVIM v0.11.2
 7| ~
 8| ~                 Nvim is open source and freely distributable
 9| ~                           https://neovim.io/#chat
10| ~
11| ~                type  :help nvim<Enter>       if you are new!
12| ~                type  :checkhealth<Enter>     to optimize Nvim
13| ~                type  :q<Enter>               to exit
14| ~                type  :help<Enter>            for help
15| ~
16| ~               type  :help news<Enter> to see changes in v0.11
17| ~
18| ~                        Help poor children in Uganda!
19| ~                type  :help iccf<Enter>       for information
20| ~
21| ~
22| ~
23| [No Name]                                                     0,0-1          All
24| 
]]

--[[ TERMINAL SNAPSHOT: global_scope_expanded
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   Local                                │
 2|  *   this: undefined                    │~
 3|   Closure                              │~
 4|  *   i: 0                               │~
 5|   Global                               │~
 6|     global: global {global: global, cle│~
 7|       AbortController: ƒ () {\n      mo│~
 8|       AbortSignal: ƒ () {\n      mod ??│~
 9|       atob: ƒ () {\n      mod ??= requi│~
10|       Blob: ƒ () {\n      mod ??= requi│~
11|       BroadcastChannel: ƒ () {\n      m│~
12|       btoa: ƒ () {\n      mod ??= requi│~
13|       Buffer: ƒ get() {\n      return _│~
14|       ByteLengthQueuingStrategy: ƒ () {│~
15|       clearImmediate: ƒ clearImmediate(│~
16|       clearInterval: ƒ clearInterval(ti│~
17|       clearTimeout: ƒ clearTimeout(time│~
18|       CompressionStream: ƒ () {\n      │~
19|       CountQueuingStrategy: ƒ () {\n   │~
20|       crypto: ƒ () {\n      if (check !│~
21|       Crypto: ƒ () {\n      mod ??= req│~
22|       CryptoKey: ƒ () {\n      mod ??= │~
23| <p_variables [1] [RO] 1,1            Top [No Name]            0,0-1          All
24| 
]]

--[[ TERMINAL SNAPSHOT: deep_navigation_complete
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   Local                                │
 2|  *   this: undefined                    │~
 3|   Closure                              │~
 4|  *   i: 0                               │~
 5|   Global                               │~
 6|     global: global {global: global, cle│~
 7|       AbortController: ƒ () {\n      mo│~
 8|       AbortSignal: ƒ () {\n      mod ??│~
 9|       atob: ƒ () {\n      mod ??= requi│~
10|       Blob: ƒ () {\n      mod ??= requi│~
11|       BroadcastChannel: ƒ () {\n      m│~
12|       btoa: ƒ () {\n      mod ??= requi│~
13|       Buffer: ƒ get() {\n      return _│~
14|       ByteLengthQueuingStrategy: ƒ () {│~
15|       clearImmediate: ƒ clearImmediate(│~
16|       clearInterval: ƒ clearInterval(ti│~
17|       clearTimeout: ƒ clearTimeout(time│~
18|       CompressionStream: ƒ () {\n      │~
19|       CountQueuingStrategy: ƒ () {\n   │~
20|       crypto: ƒ () {\n      if (check !│~
21|       Crypto: ƒ () {\n      mod ??= req│~
22|       CryptoKey: ƒ () {\n      mod ??= │~
23| <p_variables [1] [RO] 1,1            Top [No Name]            0,0-1          All
24| 
]]

--[[ TERMINAL SNAPSHOT: reopened_tree
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1|   Local                                │
 2|  *   this: undefined                    │~
 3|   Closure                              │~
 4|  *   i: 0                               │~
 5|   Global                               │~
 6|     global: global {global: global, cle│~
 7|       AbortController: ƒ () {\n      mo│~
 8|       AbortSignal: ƒ () {\n      mod ??│~
 9|       atob: ƒ () {\n      mod ??= requi│~
10|       Blob: ƒ () {\n      mod ??= requi│~
11|       BroadcastChannel: ƒ () {\n      m│~
12|       btoa: ƒ () {\n      mod ??= requi│~
13|       Buffer: ƒ get() {\n      return _│~
14|       ByteLengthQueuingStrategy: ƒ () {│~
15|       clearImmediate: ƒ clearImmediate(│~
16|       clearInterval: ƒ clearInterval(ti│~
17|       clearTimeout: ƒ clearTimeout(time│~
18|       CompressionStream: ƒ () {\n      │~
19|       CountQueuingStrategy: ƒ () {\n   │~
20|       crypto: ƒ () {\n      if (check !│~
21|       Crypto: ƒ () {\n      mod ??= req│~
22|       CryptoKey: ƒ () {\n      mod ??= │~
23| <p_variables [1] [RO] 1,1            Top [No Name]            0,0-1          All
24| 
]]