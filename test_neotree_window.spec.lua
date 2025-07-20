local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("Neo-tree Window Diagnostic", function()
  Test.It("diagnoses_neotree_window_opening", function()
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
    
    -- Open test file
    vim.cmd("edit spec/fixtures/workspaces/single-node-project/loop.js")
    nio.sleep(100)
    
    start("loop.js")
    stopped.wait()
    nio.sleep(500)
    
    print("=== NEO-TREE WINDOW DIAGNOSTIC ===")
    
    -- Configure Neo-tree
    require('neo-tree').setup({
      sources = { "neodap.plugins.SimpleVariableTree4" },
      default_source = "neodap_variables"
    })
    nio.sleep(500)
    
    -- Check windows before opening Neo-tree
    print("\\nWindows before Neo-tree command:")
    for i, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
      local name = vim.api.nvim_buf_get_name(buf)
      print(string.format("  Window %d: ft=%s, buf=%d, name=%s", i, ft, buf, vim.fn.fnamemodify(name, ":t")))
    end
    
    -- Try to open Neo-tree
    print("\\nCalling: Neotree float neodap_variables")
    local cmd_success = pcall(vim.cmd, "Neotree float neodap_variables")
    print("Command success:", cmd_success)
    
    -- Wait for window to appear
    nio.sleep(2000)
    
    -- Check windows after opening Neo-tree
    print("\\nWindows after Neo-tree command:")
    local neotree_found = false
    for i, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
      local name = vim.api.nvim_buf_get_name(buf)
      print(string.format("  Window %d: ft=%s, buf=%d, name=%s", i, ft, buf, vim.fn.fnamemodify(name, ":t")))
      
      if ft == 'neo-tree' then
        neotree_found = true
        print("    -> NEO-TREE WINDOW FOUND!")
        
        -- Check buffer contents
        local lines = vim.api.nvim_buf_get_lines(buf, 0, 10, false)
        print("    -> First 10 lines:")
        for j, line in ipairs(lines) do
          print(string.format("       %d: %s", j, line))
        end
      end
    end
    
    -- Take snapshot to see what's visible
    print("\\nTaking snapshot...")
    Test.TerminalSnapshot("diagnostic_snapshot")
    
    -- Check Neo-tree state
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok and manager and manager.get_state then
      local state = manager.get_state("neodap_variables")
      if state then
        print("\\nNeo-tree state found:")
        print("  Source name:", state.source_name)
        print("  Window exists:", state.winid ~= nil)
        if state.tree then
          print("  Tree exists: true")
          local root = state.tree:get_nodes()
          print("  Root nodes:", root and #root or 0)
        end
      else
        print("\\nNo Neo-tree state for 'neodap_variables'")
      end
    end
    
    -- Try alternative command
    if not neotree_found then
      print("\\nTrying alternative: Neotree neodap_variables")
      pcall(vim.cmd, "Neotree neodap_variables")
      nio.sleep(1000)
      
      for i, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
        if ft == 'neo-tree' then
          print("  -> Neo-tree window found with alternative command!")
          break
        end
      end
    end
    
    print("\\n*** DIAGNOSTIC RESULTS ***")
    print("Neo-tree window found:", neotree_found)
    
    api:destroy()
  end)
end)


--[[ TERMINAL SNAPSHOT: diagnostic_snapshot
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {▕ Neo-tree Neodap_variables              ▏
 3|  console.log("ALoop▕                                        ▏
 4|  console.log("BLoop▕                                        ▏
 5|  console.log("CLoop▕                                        ▏
 6|  console.log("DLoop▕                                        ▏
 7| }, 1000)           ▕                                        ▏
 8| ~                  ▕                                        ▏
 9| ~                  ▕                                        ▏
10| ~                  ▕                                        ▏
11| ~                  ▕                                        ▏
12| ~                  ▕                                        ▏
13| ~                  ▕                                        ▏
14| ~                  ▕                                        ▏
15| ~                  ▕                                        ▏
16| ~                  ▕                                        ▏
17| ~                  ▕                                        ▏
18| ~                  ▕                                        ▏
19| ~                  ▕                                        ▏
20| ~                  ▕                                        ▏
21| ~                  ▕                                        ▏
22| ~                   ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
23| spec/fixtures/workspaces/single-node-project/loop.js          1,1            All
24|                                                               0,0-1         All
]]