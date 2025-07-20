local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("Debug Tree Rendering", function()
  Test.It("investigates_why_tree_content_not_displaying", function()
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
    
    print("=== DEBUGGING TREE RENDERING ===")
    
    -- Configure Neo-tree
    require('neo-tree').setup({
      sources = { "neodap.plugins.SimpleVariableTree4" },
      default_source = "neodap_variables"
    })
    nio.sleep(500)
    
    -- Test 1: Verify get_items returns proper data
    print("\n1. Testing get_items data format...")
    SimpleVariableTree4.get_items(nil, nil, function(items)
      print("get_items returned", #items, "items")
      for i, item in ipairs(items) do
        print(string.format("  Item %d:", i))
        print("    id:", item.id)
        print("    name:", item.name) 
        print("    type:", item.type)
        print("    has_children:", item.has_children)
        print("    extra:", vim.inspect(item.extra or {}))
      end
    end)
    nio.sleep(300)
    
    -- Test 2: Open Neo-tree and check what gets rendered
    print("\n2. Opening Neo-tree...")
    vim.cmd("Neotree float neodap_variables")
    nio.sleep(2000)
    
    -- Find Neo-tree window and inspect its buffer
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
    
    if neotree_buf then
      print("✓ Neo-tree buffer found")
      local lines = vim.api.nvim_buf_get_lines(neotree_buf, 0, -1, false)
      print("Buffer has", #lines, "lines")
      
      print("First 20 lines of Neo-tree buffer:")
      for i = 1, math.min(20, #lines) do
        local line = lines[i] or ""
        if line ~= "" then
          print(string.format("  %d: '%s'", i, line))
        else
          print(string.format("  %d: (empty)", i))
        end
      end
      
      -- Check buffer options
      print("\nBuffer options:")
      print("  filetype:", vim.api.nvim_buf_get_option(neotree_buf, 'filetype'))
      print("  modifiable:", vim.api.nvim_buf_get_option(neotree_buf, 'modifiable'))
      print("  readonly:", vim.api.nvim_buf_get_option(neotree_buf, 'readonly'))
    else
      print("❌ No Neo-tree buffer found")
    end
    
    -- Test 3: Check Neo-tree state
    print("\n3. Checking Neo-tree state...")
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok and manager then
      local state = manager.get_state("neodap_variables")
      if state then
        print("✓ Neo-tree state exists")
        print("  source_name:", state.source_name)
        print("  winid:", state.winid)
        print("  bufnr:", state.bufnr)
        
        if state.tree then
          print("  tree exists: true")
          local root = state.tree:get_nodes()
          if root then
            print("  root nodes:", #root)
            for i, node in ipairs(root) do
              if i <= 5 then  -- Show first 5
                print(string.format("    Node %d: id='%s', name='%s', type='%s'", 
                  i, node:get_id(), node.name, node.type))
              end
            end
          else
            print("  root is nil")
          end
        else
          print("  tree is nil")
        end
      else
        print("❌ No Neo-tree state found")
      end
    end
    
    -- Test 4: Check if navigate was called with data
    print("\n4. Testing navigate function behavior...")
    local original_navigate = SimpleVariableTree4.navigate
    local navigate_called = false
    local navigate_items = nil
    
    SimpleVariableTree4.navigate = function(state, path, callback)
      navigate_called = true
      print("navigate() called with path:", path)
      local result = original_navigate(state, path, callback)
      navigate_items = result
      print("navigate() returned", result and #result or 0, "items")
      return result
    end
    
    -- Force a refresh to trigger navigate
    if ok and manager then
      manager.refresh("neodap_variables")
      nio.sleep(1000)
    end
    
    print("Navigate called:", navigate_called)
    if navigate_items then
      print("Navigate returned", #navigate_items, "items")
      for i, item in ipairs(navigate_items) do
        print(string.format("  Nav item %d: id='%s', name='%s', type='%s'", 
          i, item.id, item.name, item.type))
      end
    end
    
    -- Restore original function
    SimpleVariableTree4.navigate = original_navigate
    
    -- Take final snapshot
    Test.TerminalSnapshot("tree_rendering_debug")
    
    print("\n*** TREE RENDERING DEBUG RESULTS ***")
    print("get_items working:", "✓")
    print("Neo-tree window opens:", neotree_win and "✓" or "❌")
    print("Neo-tree buffer found:", neotree_buf and "✓" or "❌")
    print("Navigate function called:", navigate_called and "✓" or "❌")
    
    api:destroy()
  end)
end)


--[[ TERMINAL SNAPSHOT: tree_rendering_debug
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