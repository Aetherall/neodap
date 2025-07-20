local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree3 = require("neodap.plugins.SimpleVariableTree3")

Test.Describe("Compare Working Source", function()
  Test.It("tests_how_simplevariabletree3_works", function()
    local api, start = prepare()
    api:getPluginInstance(SimpleVariableTree3)
    
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
    
    print("=== TESTING WORKING SIMPLEVARIABLETREE3 ===")
    
    -- Configure Neo-tree with SimpleVariableTree3
    require('neo-tree').setup({
      sources = { "neodap.plugins.SimpleVariableTree3" },
      default_source = "NeodapVariables"  -- Note: different name than SimpleVariableTree4
    })
    nio.sleep(500)
    
    print("\\n1. Opening SimpleVariableTree3...")
    vim.cmd("Neotree float NeodapVariables")
    nio.sleep(2000)
    
    -- Check what SimpleVariableTree3 buffer looks like
    local tree3_buffer_content = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
      if ft == 'neo-tree' then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        tree3_buffer_content = lines
        print("SimpleVariableTree3 content:")
        for i, line in ipairs(lines) do
          if i <= 15 then
            print(string.format("  %d: '%s'", i, line))
          end
        end
        break
      end
    end
    
    -- Take snapshot of working SimpleVariableTree3
    Test.TerminalSnapshot("working_simplevariabletree3")
    
    -- Check if SimpleVariableTree3 has get_items
    print("\\n2. Checking SimpleVariableTree3 interface...")
    print("Has navigate function:", type(SimpleVariableTree3.navigate))
    print("Has get_items function:", type(SimpleVariableTree3.get_items))
    
    -- Check the source registration pattern
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok and manager then
      local sources = manager.get_sources and manager.get_sources() or {}
      print("Registered sources:", vim.inspect(sources))
      
      local state = manager.get_state("NeodapVariables")
      if state then
        print("SimpleVariableTree3 state found")
        print("  source_name:", state.source_name)
        if state.tree then
          local nodes = state.tree:get_nodes()
          print("  tree nodes:", nodes and #nodes or 0)
        end
      end
    end
    
    print("\\n*** WORKING SOURCE ANALYSIS ***")
    print("SimpleVariableTree3 buffer lines:", #tree3_buffer_content)
    if #tree3_buffer_content > 0 then
      print("First line looks like:", "'" .. tree3_buffer_content[1] .. "'")
      -- Check if it has proper tree formatting
      local has_icons = false
      for _, line in ipairs(tree3_buffer_content) do
        if line:match("▶") or line:match("▼") or line:match("󰉋") then
          has_icons = true
          break
        end
      end
      print("Has tree icons:", has_icons)
    end
    
    api:destroy()
  end)
end)

--[[ TERMINAL SNAPSHOT: working_simplevariabletree3
Size: 24x80
Cursor: [1, 0] (line 1, col 0)
Mode: n

 1| let i = 0;
 2| setInterval(() => {▕ Neo-tree NeodapVariables               ▏
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