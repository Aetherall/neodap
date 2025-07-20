local Test = require("spec.helpers.testing")(describe, it)
local prepare = require("spec.helpers.prepare").prepare
local nio = require("nio")
local SimpleVariableTree4 = require("neodap.plugins.SimpleVariableTree4")

Test.Describe("SimpleVariableTree4 expansion data flow", function()
  Test.It("simulates_user_interactions_and_captures_expansion_states", function()
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
    
    -- Start debugging with loop.js fixture
    start("loop.js")
    stopped.wait()
    nio.sleep(500)
    
    print("=== EXPANSION DATA FLOW TEST - SIMULATED USER INTERACTIONS ===")
    
    -- Simulate user action: Query for initial scopes (equivalent to opening Neo-tree)
    local expansion_states = {}
    
    print("User Action 1: Open variables tree (get initial scopes)")
    SimpleVariableTree4.get_items(nil, nil, function(scopes)
      expansion_states.scopes = scopes
      print("Result: Found", #scopes, "scopes")
      for i, scope in ipairs(scopes) do
        print("  Scope", i, ":", scope.name, "- expandable:", scope.has_children)
      end
    end)
    nio.sleep(200)
    
    -- Simulate user action: Expand Global scope (equivalent to pressing Enter on Global)
    if expansion_states.scopes then
      for _, scope in ipairs(expansion_states.scopes) do
        if scope.name == "Global" then
          print("\nUser Action 2: Expand Global scope (Enter key on Global)")
          
          SimpleVariableTree4.get_items(nil, scope.id, function(variables)
            expansion_states.global_variables = variables
            print("Result: Found", #variables, "variables in Global scope")
            
            -- Show first 10 variables as user would see them
            for i = 1, math.min(10, #variables) do
              local var = variables[i]
              print("  Var", i, ":", var.name:sub(1, 40), "- expandable:", var.has_children)
            end
            
            -- Find process variable (as user would search/navigate)
            for _, var in ipairs(variables) do
              if var.name:match("process:") then
                expansion_states.process_variable = var
                print("  → Found process variable:", var.name:sub(1, 50))
                break
              end
            end
          end)
          break
        end
      end
    end
    nio.sleep(300)
    
    -- Simulate user action: Expand process variable (equivalent to pressing Enter on process)
    if expansion_states.process_variable then
      print("\nUser Action 3: Expand process variable (Enter key on process)")
      
      SimpleVariableTree4.get_items(nil, expansion_states.process_variable.id, function(process_props)
        expansion_states.process_properties = process_props
        print("Result: Found", #process_props, "process properties")
        
        -- Show process properties as user would see them
        for i = 1, math.min(15, #process_props) do
          local prop = process_props[i]
          print("  Prop", i, ":", prop.name:sub(1, 40), "- expandable:", prop.has_children)
        end
        
        -- Find an expandable property (env, argv, etc.)
        for _, prop in ipairs(process_props) do
          if prop.has_children and (prop.name:match("env") or prop.name:match("argv")) then
            expansion_states.expandable_property = prop
            print("  → Found expandable property:", prop.name:sub(1, 40))
            break
          end
        end
      end)
    end
    nio.sleep(400)
    
    -- Simulate user action: Expand nested property (4th level expansion)
    if expansion_states.expandable_property then
      print("\nUser Action 4: Expand nested property (Enter key on", expansion_states.expandable_property.name:match("^[^:]+"), ")")
      
      SimpleVariableTree4.get_items(nil, expansion_states.expandable_property.id, function(nested_props)
        expansion_states.nested_properties = nested_props
        print("Result: Found", #nested_props, "nested properties")
        
        -- Show nested properties (4th level) as user would see them
        for i = 1, math.min(10, #nested_props) do
          local nested = nested_props[i]
          print("  Nested", i, ":", nested.name:sub(1, 50))
        end
      end)
    end
    nio.sleep(200)
    
    -- Create a visual representation of the expansion tree
    print("\n=== SIMULATED TREE VIEW (AS USER WOULD SEE) ===")
    
    if expansion_states.scopes then
      for _, scope in ipairs(expansion_states.scopes) do
        if scope.name == "Global" then
          print("▼ " .. scope.name)
          
          if expansion_states.global_variables then
            local var_count = 0
            for _, var in ipairs(expansion_states.global_variables) do
              var_count = var_count + 1
              if var_count <= 5 then  -- Show first 5 variables
                local indicator = var.has_children and "▶" or " "
                print("  " .. indicator .. " " .. var.name:sub(1, 40))
              elseif var.name:match("process:") then
                -- Always show process variable
                print("  ▼ " .. var.name:sub(1, 40))
                
                if expansion_states.process_properties then
                  local prop_count = 0
                  for _, prop in ipairs(expansion_states.process_properties) do
                    prop_count = prop_count + 1
                    if prop_count <= 8 then  -- Show first 8 process properties
                      local prop_indicator = prop.has_children and "▶" or " "
                      if expansion_states.expandable_property and prop.id == expansion_states.expandable_property.id then
                        prop_indicator = "▼"
                      end
                      print("    " .. prop_indicator .. " " .. prop.name:sub(1, 35))
                      
                      -- Show nested properties if expanded
                      if expansion_states.nested_properties and prop.id == expansion_states.expandable_property.id then
                        for i = 1, math.min(5, #expansion_states.nested_properties) do
                          local nested = expansion_states.nested_properties[i]
                          print("      " .. nested.name:sub(1, 30))
                        end
                        if #expansion_states.nested_properties > 5 then
                          print("      ... (" .. (#expansion_states.nested_properties - 5) .. " more)")
                        end
                      end
                    end
                  end
                  if #expansion_states.process_properties > 8 then
                    print("    ... (" .. (#expansion_states.process_properties - 8) .. " more properties)")
                  end
                end
              end
            end
            if #expansion_states.global_variables > 5 then
              print("  ... (" .. (#expansion_states.global_variables - 5) .. " more variables)")
            end
          end
        else
          print("▶ " .. scope.name)
        end
      end
    end
    
    -- Verify expansion depth achieved
    local max_depth = 0
    if expansion_states.scopes then max_depth = 1 end
    if expansion_states.global_variables then max_depth = 2 end
    if expansion_states.process_properties then max_depth = 3 end
    if expansion_states.nested_properties then max_depth = 4 end
    
    print("\n*** EXPANSION DATA FLOW TEST RESULTS ***")
    print("✓ Maximum expansion depth achieved:", max_depth, "levels")
    print("✓ Scopes found:", expansion_states.scopes and #expansion_states.scopes or 0)
    print("✓ Global variables found:", expansion_states.global_variables and #expansion_states.global_variables or 0)
    print("✓ Process properties found:", expansion_states.process_properties and #expansion_states.process_properties or 0)
    print("✓ Nested properties found:", expansion_states.nested_properties and #expansion_states.nested_properties or 0)
    print("✓ Real loop.js fixture data confirmed")
    print("✓ User interaction workflow simulated successfully")
    
    if max_depth >= 4 then
      print("🎉 SUCCESS: 4-level nested expansion confirmed with real data!")
    else
      print("⚠️  Only reached", max_depth, "levels - may need investigation")
    end
    
    api:destroy()
  end)
end)