local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("Debug get_items Calls", function()
  Test.It("tracks_when_get_items_is_called", function()
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
    
    print("=== DEBUGGING GET_ITEMS CALLS ===")
    
    -- Track get_items calls
    local get_items_calls = {}
    local original_get_items = SimpleVariableTree4.get_items
    
    SimpleVariableTree4.get_items = function(state, parent_id, callback)
      local call_info = {
        timestamp = os.clock(),
        parent_id = parent_id,
        state = state and "present" or "nil"
      }
      table.insert(get_items_calls, call_info)
      print(string.format("🔍 get_items called #%d: parent_id='%s', state=%s", 
        #get_items_calls, tostring(parent_id), call_info.state))
      
      return original_get_items(state, parent_id, callback)
    end
    
    -- Configure Neo-tree
    require('neo-tree').setup({
      sources = { "neodap.plugins.SimpleVariableTree4" },
      default_source = "neodap_variables"
    })
    nio.sleep(500)
    
    print("\\n1. Opening Neo-tree...")
    vim.cmd("Neotree float neodap_variables")
    nio.sleep(2000)
    
    print("get_items calls after opening:", #get_items_calls)
    
    -- Force multiple refresh attempts
    print("\\n2. Trying various refresh methods...")
    
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok and manager then
      print("Attempting manager.refresh...")
      local refresh_ok, refresh_err = pcall(manager.refresh, "neodap_variables")
      print("Refresh result:", refresh_ok, refresh_err)
      nio.sleep(500)
      print("get_items calls after refresh:", #get_items_calls)
      
      -- Try to get the state and force an update
      local state = manager.get_state("neodap_variables")
      if state then
        print("\\nState found, trying to force tree update...")
        
        -- Try direct renderer call
        local renderer = require("neo-tree.ui.renderer")
        if renderer.redraw then
          print("Calling renderer.redraw...")
          local redraw_ok, redraw_err = pcall(renderer.redraw, state)
          print("Redraw result:", redraw_ok, redraw_err)
          nio.sleep(500)
          print("get_items calls after redraw:", #get_items_calls)
        end
        
        -- Try to force tree creation
        if renderer.draw then
          print("Calling renderer.draw...")
          local draw_ok, draw_err = pcall(renderer.draw, state)
          print("Draw result:", draw_ok, draw_err)
          nio.sleep(500)
          print("get_items calls after draw:", #get_items_calls)
        end
      end
    end
    
    -- Try closing and reopening
    print("\\n3. Closing and reopening...")
    vim.cmd("Neotree close")
    nio.sleep(500)
    vim.cmd("Neotree float neodap_variables")
    nio.sleep(2000)
    print("get_items calls after reopen:", #get_items_calls)
    
    -- Manual call to verify it works
    print("\\n4. Manual get_items call...")
    SimpleVariableTree4.get_items(nil, nil, function(items)
      print("Manual call returned", #items, "items")
    end)
    nio.sleep(200)
    
    print("\\n*** GET_ITEMS CALL ANALYSIS ***")
    print("Total get_items calls:", #get_items_calls)
    
    if #get_items_calls == 0 then
      print("❌ get_items NEVER called by Neo-tree!")
      print("   This means Neo-tree is not requesting data from our source")
    else
      print("✓ get_items called", #get_items_calls, "times")
      for i, call in ipairs(get_items_calls) do
        print(string.format("  Call %d: parent_id='%s', state=%s", 
          i, tostring(call.parent_id), call.state))
      end
    end
    
    -- Restore original function
    SimpleVariableTree4.get_items = original_get_items
    
    api:destroy()
  end)
end)