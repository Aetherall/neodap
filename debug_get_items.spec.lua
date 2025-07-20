local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("Debug get_items function", function()
  Test.It("tests_get_items_directly", function()
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
    
    print("=== TESTING GET_ITEMS DIRECTLY ===")
    
    -- Test get_items function directly
    print("Testing get_items with no parent_id (should return scopes)")
    
    local results = {}
    
    -- Call get_items with nil parent_id
    SimpleVariableTree4.get_items(nil, nil, function(nodes)
      results.scopes = nodes
      print("Got", #nodes, "scope nodes:")
      for i, node in ipairs(nodes) do
        print("  ", i, ":", node.name, "- id:", node.id, "- has_children:", node.has_children)
      end
    end)
    
    nio.sleep(200)
    
    -- Test expanding Global scope
    if results.scopes and #results.scopes > 0 then
      for _, scope_node in ipairs(results.scopes) do
        if scope_node.name == "Global" then
          print("\nTesting get_items with Global scope (should return variables)")
          
          SimpleVariableTree4.get_items(nil, scope_node.id, function(nodes)
            results.variables = nodes
            print("Got", #nodes, "variable nodes:")
            for i, node in ipairs(nodes) do
              print("  ", i, ":", node.name, "- id:", node.id, "- has_children:", node.has_children)
              
              -- Test expanding process variable if found
              if node.name:match("process:") and i <= 5 then  -- Only test first few
                print("\nTesting get_items with process variable (should return properties)")
                
                SimpleVariableTree4.get_items(nil, node.id, function(child_nodes)
                  results.process_props = child_nodes
                  print("Got", #child_nodes, "process property nodes:")
                  for j, child in ipairs(child_nodes) do
                    if j <= 5 then  -- Only show first 5
                      print("    ", j, ":", child.name, "- id:", child.id, "- has_children:", child.has_children)
                    end
                  end
                end)
                break
              end
            end
          end)
          break
        end
      end
    end
    
    nio.sleep(500)
    
    print("\n*** GET_ITEMS TEST RESULTS ***")
    print("Scopes found:", results.scopes and #results.scopes or 0)
    print("Variables found:", results.variables and #results.variables or 0)
    print("Process properties found:", results.process_props and #results.process_props or 0)
    
    if results.process_props and #results.process_props > 0 then
      print("🎉 SUCCESS: get_items can load 3+ levels!")
      print("✓ Level 1: Scopes (" .. (#results.scopes or 0) .. " items)")
      print("✓ Level 2: Variables (" .. (#results.variables or 0) .. " items)")
      print("✓ Level 3: Properties (" .. (#results.process_props or 0) .. " items)")
    else
      print("⚠️  get_items works but process expansion may need debugging")
    end
    
    api:destroy()
  end)
end)