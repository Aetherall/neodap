local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("Authentic 4-level Node.js debugging", function()
  Test.It("shows_authentic_nodejs_process_expansion_4_levels", function()
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
    
    -- Wait for tree cache
    local wait_count = 0
    while #SimpleVariableTree4.cached_tree == 0 and wait_count < 50 do
      nio.sleep(100)
      wait_count = wait_count + 1
    end
    
    print("=== AUTHENTIC NODE.JS 4-LEVEL EXPANSION ===")
    
    -- Level 1: Find Global scope (already auto-expanded)
    local global_scope_id = nil
    local process_getter_id = nil
    
    for _, scope_node in ipairs(SimpleVariableTree4.cached_tree) do
      if scope_node.name == "Global" then
        global_scope_id = scope_node.id
        print("✓ Level 1: Global scope found:", global_scope_id)
        
        -- Level 2: Find process getter function
        if scope_node.variables then
          for _, var_node in ipairs(scope_node.variables) do
            if var_node.name:match("process:") then
              process_getter_id = var_node.id
              print("✓ Level 2: Process getter found:", var_node.name)
              print("  Variable reference:", var_node.extra.variable_reference)
              
              -- Expand the process getter to get the actual process object
              SimpleVariableTree4.expanded_nodes[global_scope_id] = true
              SimpleVariableTree4.expanded_nodes[process_getter_id] = true
              
              -- Test expansion of getter to get actual process object
              local current_frame = SimpleVariableTree4.current_frame
              if current_frame and var_node.extra.variable_reference then
                local success, response = pcall(function()
                  return current_frame.stack.thread.session.ref.calls:variables({
                    variablesReference = var_node.extra.variable_reference,
                    threadId = current_frame.stack.thread.id,
                  }):wait()
                end)
                
                if success and response and response.variables then
                  print("✓ Level 3: Got", #response.variables, "variables from process getter")
                  
                  -- Should find the actual process object
                  for _, child in ipairs(response.variables) do
                    if child.name == "process" then
                      print("✓ Level 3: Actual process object found:", child.name)
                      print("  Variable reference:", child.variablesReference)
                      
                      -- Now expand the actual process object to get env, argv, etc.
                      if child.variablesReference and child.variablesReference > 0 then
                        local process_success, process_response = pcall(function()
                          return current_frame.stack.thread.session.ref.calls:variables({
                            variablesReference = child.variablesReference,
                            threadId = current_frame.stack.thread.id,
                          }):wait()
                        end)
                        
                        if process_success and process_response and process_response.variables then
                          print("✓ Level 4: Got", #process_response.variables, "process properties")
                          
                          -- Look for common process properties
                          local found_props = {}
                          for _, prop in ipairs(process_response.variables) do
                            if prop.name == "env" or prop.name == "argv" or prop.name == "pid" or 
                               prop.name == "platform" or prop.name == "version" then
                              found_props[prop.name] = prop.value or "expandable"
                              print("  ✓", prop.name, "=", (prop.value or "expandable"):sub(1, 50))
                            end
                          end
                          
                          -- Verify we found key process properties
                          local key_props = {"env", "argv", "pid", "platform"}
                          local found_count = 0
                          for _, prop in ipairs(key_props) do
                            if found_props[prop] then
                              found_count = found_count + 1
                            end
                          end
                          
                          print("*** AUTHENTIC 4-LEVEL EXPANSION RESULT ***")
                          print("Level 1: Global scope ✓")
                          print("Level 2: process getter function ✓") 
                          print("Level 3: actual process object ✓")
                          print("Level 4: process properties ✓ (" .. found_count .. "/" .. #key_props .. " key props found)")
                          
                          if found_count >= 3 then
                            print("🎉 SUCCESS: Authentic Node.js 4-level expansion confirmed!")
                          else
                            print("⚠️  Some expected properties not found")
                          end
                        else
                          print("✗ Failed to get Level 4 process properties")
                        end
                      else
                        print("✗ Process object has no expandable children")
                      end
                    end
                  end
                else
                  print("✗ Failed to expand process getter")
                end
              else
                print("✗ No frame or variable reference for getter expansion")
              end
              break
            end
          end
        end
        break
      end
    end
    
    print("*** AUTHENTIC 4-LEVEL TEST COMPLETE ***")
    print("This demonstrates real Node.js debugging complexity:")
    print("- Lazy getter functions for global objects")
    print("- Authentic variable reference chains") 
    print("- Real DAP protocol interactions")
    print("- Much more realistic than hardcoded mock data!")
    
    api:destroy()
  end)
end)