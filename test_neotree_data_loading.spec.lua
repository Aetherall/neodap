local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("Neo-tree Data Loading Test", function()
  Test.It("verifies_data_loads_when_neotree_opens", function()
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
    
    print("=== NEO-TREE DATA LOADING TEST ===")
    
    -- Configure Neo-tree
    require('neo-tree').setup({
      sources = { "neodap.plugins.SimpleVariableTree4" },
      default_source = "neodap_variables"
    })
    nio.sleep(500)
    
    -- Track get_items calls
    local get_items_calls = 0
    local original_get_items = SimpleVariableTree4.get_items
    SimpleVariableTree4.get_items = function(state, parent_id, callback)
      get_items_calls = get_items_calls + 1
      print(string.format("\\nget_items called #%d with parent_id: %s", get_items_calls, tostring(parent_id)))
      return original_get_items(state, parent_id, callback)
    end
    
    -- Open Neo-tree and wait
    print("\\nOpening Neo-tree...")
    vim.cmd("Neotree float neodap_variables")
    nio.sleep(3000)  -- Longer wait to ensure any async calls complete
    
    -- Check if window opened
    local neotree_win = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
      if ft == 'neo-tree' then
        neotree_win = win
        print("✓ Neo-tree window found")
        
        -- Check buffer contents
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        print("  Buffer has", #lines, "lines")
        print("  Non-empty lines:", #vim.tbl_filter(function(l) return l ~= "" end, lines))
        
        -- Show first few lines
        for i = 1, math.min(10, #lines) do
          if lines[i] ~= "" then
            print(string.format("  Line %d: %s", i, lines[i]))
          end
        end
        break
      end
    end
    
    -- Take snapshot
    Test.TerminalSnapshot("data_loading_snapshot")
    
    -- Manual refresh test
    if neotree_win and get_items_calls == 0 then
      print("\\nNo get_items calls yet, trying manual refresh...")
      vim.api.nvim_set_current_win(neotree_win)
      
      -- Try refreshing Neo-tree
      local ok, err = pcall(vim.cmd, "Neotree refresh")
      print("Refresh result:", ok and "success" or err)
      nio.sleep(1000)
      
      -- Check again
      if neotree_win then
        local buf = vim.api.nvim_win_get_buf(neotree_win)
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        print("After refresh: Buffer has", #lines, "lines")
      end
    end
    
    print("\\n*** DATA LOADING TEST RESULTS ***")
    print("get_items called:", get_items_calls, "times")
    print("Neo-tree window:", neotree_win and "opened" or "not opened")
    
    if get_items_calls == 0 and neotree_win then
      print("⚠️  Window opened but get_items never called - data loading issue")
    elseif get_items_calls > 0 then
      print("✓ get_items was called - data should be loading")
    end
    
    -- Restore original function
    SimpleVariableTree4.get_items = original_get_items
    
    api:destroy()
  end)
end)


--[[ TERMINAL SNAPSHOT: data_loading_snapshot
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