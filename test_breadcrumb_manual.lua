-- Manual test for breadcrumb navigation

-- First create a simple fixture file
vim.cmd("e /tmp/test_breadcrumb.js")
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "let test_result = {",
  "    local_var: {",
  "        nested: {",
  "            deep: \"value\"",
  "        }",
  "    },",
  "    array_var: [1, 2, 3]",
  "};",
  "debugger;"
})
vim.cmd("w")

-- Load neodap
local neodap = require('neodap')
local manager, api = neodap.setup()
local variables_plugin = api:getPluginInstance(require('neodap.plugins.Variables'))

-- Create a debug session (simulation)
print("=== MANUAL BREADCRUMB TEST ===")
print("1. Variables plugin loaded:", variables_plugin ~= nil)
print("2. Breadcrumb mode:", variables_plugin.breadcrumb_mode)

-- Test basic breadcrumb structure
if variables_plugin.breadcrumb then
    print("3. Breadcrumb exists:", true)
    print("4. Current path:", vim.inspect(variables_plugin.breadcrumb.current_path))
    
    -- Test breadcrumb text creation
    local text = variables_plugin.breadcrumb:createBreadcrumbText()
    print("5. Initial breadcrumb text:", text)
    
    -- Simulate navigation
    print("\n=== SIMULATING NAVIGATION ===")
    variables_plugin.breadcrumb.current_path = {"Local"}
    local text2 = variables_plugin.breadcrumb:createBreadcrumbText()
    print("6. After Local navigation:", text2)
    
    variables_plugin.breadcrumb.current_path = {"Local", "complexObject"}
    local text3 = variables_plugin.breadcrumb:createBreadcrumbText()
    print("7. After complexObject navigation:", text3)
    
    -- Test navigation functions
    print("\n=== TESTING NAVIGATION FUNCTIONS ===")
    variables_plugin.breadcrumb.current_path = {}
    variables_plugin.breadcrumb:navigateDown("Local")
    print("8. After navigateDown('Local'):", vim.inspect(variables_plugin.breadcrumb.current_path))
    
    variables_plugin.breadcrumb:navigateDown("complexObject")
    print("9. After navigateDown('complexObject'):", vim.inspect(variables_plugin.breadcrumb.current_path))
    
    variables_plugin.breadcrumb:navigateUp()
    print("10. After navigateUp():", vim.inspect(variables_plugin.breadcrumb.current_path))
    
else
    print("3. ERROR: Breadcrumb does not exist")
end

print("\n=== TEST COMPLETE ===")