local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("Debug real expansion", function()
  Test.It("debugs_real_variable_expansion_logic", function()
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
    
    print("=== DEBUGGING REAL EXPANSION ===")
    
    -- Find process variable and check its expansion state
    for _, scope_node in ipairs(SimpleVariableTree4.cached_tree) do
      if scope_node.name == "Global" and scope_node.variables then
        print("Global scope has", #scope_node.variables, "variables")
        
        for i, var_node in ipairs(scope_node.variables) do
          if var_node.name:match("process:") then
            print("*** FOUND PROCESS VARIABLE ***")
            print("Position:", i)
            print("ID:", var_node.id)
            print("Name:", var_node.name)
            print("Has children:", var_node.has_children)
            print("Variable reference:", var_node.extra.variable_reference)
            
            -- Test direct DAP call to get process children
            print("\n*** TESTING DIRECT DAP CALL ***")
            local current_frame = SimpleVariableTree4.current_frame
            if current_frame and var_node.extra.variable_reference then
              local success, response = pcall(function()
                return current_frame.stack.thread.session.ref.calls:variables({
                  variablesReference = var_node.extra.variable_reference,
                  threadId = current_frame.stack.thread.id,
                }):wait()
              end)
              
              if success and response and response.variables then
                print("✓ Successfully got", #response.variables, "child variables:")
                for j, child in ipairs(response.variables) do
                  print("  ", j, ":", child.name, "=", (child.value or ""):sub(1, 50))
                  if child.variablesReference and child.variablesReference > 0 then
                    print("    -> Has", child.variablesReference, "references (expandable)")
                  end
                end
              else
                print("✗ Failed to get child variables")
                print("Success:", success)
                print("Response:", response)
              end
            else
              print("✗ No current frame or variable reference")
              print("Current frame:", current_frame ~= nil)
              print("Variable reference:", var_node.extra.variable_reference)
            end
            
            -- Now test the expansion logic
            print("\n*** TESTING EXPANSION LOGIC ***")
            SimpleVariableTree4.expanded_nodes[scope_node.id] = true
            SimpleVariableTree4.expanded_nodes[var_node.id] = true
            print("Set expansion state for scope and process variable")
            
            -- Manually trigger tree building to see the expansion
            print("Expanded nodes state:")
            for id, is_expanded in pairs(SimpleVariableTree4.expanded_nodes) do
              print("  ", id, "->", is_expanded)
            end
            
            break
          end
        end
        break
      end
    end
    
    print("*** DEBUG TEST COMPLETE ***")
    
    api:destroy()
  end)
end)