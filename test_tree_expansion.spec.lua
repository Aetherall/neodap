local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("Test Tree Expansion", function()
  Test.It("tests_scope_expansion_functionality", function()
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
    
    print("=== TESTING TREE EXPANSION ===")
    
    -- Configure Neo-tree
    require('neo-tree').setup({
      sources = { "neodap.plugins.SimpleVariableTree4" },
      default_source = "neodap_variables"
    })
    nio.sleep(500)
    
    print("\n1. Opening Neo-tree...")
    vim.cmd("Neotree float neodap_variables")
    nio.sleep(1000)
    
    -- Find Neo-tree window
    local neotree_win = nil
    local neotree_buf = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
      if ft == 'neo-tree' then
        neotree_win = win
        neotree_buf = buf
        break
      end
    end
    
    if neotree_win and neotree_buf then
      print("✓ Neo-tree window found")
      
      -- Get initial content
      local initial_lines = vim.api.nvim_buf_get_lines(neotree_buf, 0, -1, false)
      print("Initial content:", #initial_lines, "lines")
      for i, line in ipairs(initial_lines) do
        print(string.format("  %d: '%s'", i, line))
      end
      
      -- Try to expand the first scope (Local)
      print("\n2. Attempting to expand Local scope...")
      
      -- Set cursor to first line and simulate expansion
      vim.api.nvim_win_set_cursor(neotree_win, { 1, 0 })
      nio.sleep(100)
      
      -- Try to trigger toggle_node command
      local ok, err = pcall(function()
        vim.api.nvim_set_current_win(neotree_win)
        vim.cmd("normal! o")  -- Should trigger toggle_node mapping
      end)
      
      print("Expansion command result:", ok, err or "success")
      nio.sleep(1000)
      
      -- Check if content changed
      local expanded_lines = vim.api.nvim_buf_get_lines(neotree_buf, 0, -1, false)
      print("\nAfter expansion attempt:", #expanded_lines, "lines")
      for i, line in ipairs(expanded_lines) do
        print(string.format("  %d: '%s'", i, line))
      end
      
      if #expanded_lines > #initial_lines then
        print("✓ Expansion worked! Content increased from", #initial_lines, "to", #expanded_lines, "lines")
      else
        print("❌ No expansion detected")
      end
    else
      print("❌ Neo-tree window not found")
    end
    
    -- Take snapshot
    Test.TerminalSnapshot("tree_expansion_test")
    
    api:destroy()
  end)
end)

--[[ TERMINAL SNAPSHOT: tree_expansion_test
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {▕ Neo-tree Neodap_variables              ▏
 3|  console.log("ALoop▕  Local                                ▏
 4|  console.log("BLoop▕  Closure                              ▏
 5|  console.log("CLoop▕  Global                               ▏
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
24|                                                               1,1           All
]]