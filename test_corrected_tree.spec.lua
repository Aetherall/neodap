local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("Test Corrected Tree Implementation", function()
  Test.It("tests_corrected_navigate_pattern", function()
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
    
    print("=== TESTING CORRECTED TREE IMPLEMENTATION ===")
    
    -- Configure Neo-tree
    require('neo-tree').setup({
      sources = { "neodap.plugins.SimpleVariableTree4" },
      default_source = "neodap_variables"
    })
    nio.sleep(500)
    
    print("\n1. Opening Neo-tree...")
    vim.cmd("Neotree float neodap_variables")
    nio.sleep(2000)
    
    -- Check Neo-tree buffer content
    local neotree_buf = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
      if ft == 'neo-tree' then
        neotree_buf = buf
        break
      end
    end
    
    if neotree_buf then
      print("✓ Neo-tree buffer found")
      local lines = vim.api.nvim_buf_get_lines(neotree_buf, 0, -1, false)
      print("Buffer has", #lines, "lines")
      
      print("First 10 lines of Neo-tree buffer:")
      for i = 1, math.min(10, #lines) do
        local line = lines[i] or ""
        print(string.format("  %d: '%s'", i, line))
      end
      
      -- Check for proper tree formatting
      local has_icons = false
      for _, line in ipairs(lines) do
        if line:match("▶") or line:match("▼") or line:match("󰉋") then
          has_icons = true
          break
        end
      end
      print("Has tree icons:", has_icons)
    else
      print("❌ No Neo-tree buffer found")
    end
    
    -- Take snapshot
    Test.TerminalSnapshot("corrected_tree_implementation")
    
    api:destroy()
  end)
end)

--[[ TERMINAL SNAPSHOT: corrected_tree_implementation
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