local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("Neo-tree Registration Test", function()
  Test.It("verifies_source_registration_without_ui", function()
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
    
    print("=== NEO-TREE SOURCE REGISTRATION TEST ===")
    
    -- Test 1: Setup Neo-tree (without opening UI)
    local setup_success = pcall(function()
      require('neo-tree').setup({
        sources = {
          "filesystem",
          "neodap.plugins.SimpleVariableTree4",
        },
      })
    end)
    
    print("✓ Neo-tree setup success:", setup_success)
    nio.sleep(500)
    
    -- Test 2: Check if source is registered
    local manager_available = false
    local source_registered = false
    
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok and manager then
      manager_available = true
      print("✓ Neo-tree manager available")
      
      -- Check if our source is in the sources list
      local sources = manager.get_sources and manager.get_sources() or {}
      print("Available sources:", vim.inspect(sources))
      
      -- Try to get state for our source
      local state_ok, state = pcall(manager.get_state, "neodap_variables")
      if state_ok and state then
        source_registered = true
        print("✓ Source state accessible")
      else
        print("❌ Source state not accessible:", state)
      end
    else
      print("❌ Neo-tree manager not available:", manager)
    end
    
    -- Test 3: Check if get_items function works
    local get_items_works = false
    if SimpleVariableTree4.get_items then
      local test_callback_called = false
      
      SimpleVariableTree4.get_items(nil, nil, function(items)
        test_callback_called = true
        print("✓ get_items callback called with", #items, "items")
        if #items > 0 then
          print("  First item:", items[1].name)
        end
      end)
      
      nio.sleep(200)
      
      if test_callback_called then
        get_items_works = true
        print("✓ get_items function works")
      else
        print("❌ get_items callback not called")
      end
    else
      print("❌ get_items function not found")
    end
    
    print("\\n*** REGISTRATION TEST RESULTS ***")
    print("Neo-tree setup:", setup_success and "✓" or "❌")
    print("Manager available:", manager_available and "✓" or "❌")
    print("Source registered:", source_registered and "✓" or "❌")
    print("get_items works:", get_items_works and "✓" or "❌")
    
    if setup_success and manager_available and get_items_works then
      print("🎉 Core functionality working - UI issues may be separate")
    else
      print("⚠️  Core registration issues need fixing")
    end
    
    api:destroy()
  end)
end)