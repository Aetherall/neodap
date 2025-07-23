-- Test if breadcrumb navigation works
vim.cmd("edit lua/testing/fixtures/variables/deep_nested.js")

-- Setup neodap
local neodap = require('neodap')
local manager, api = neodap.setup()
local variables = api:getPluginInstance(require('neodap.plugins.Variables'))

print("Variables plugin:", variables ~= nil)
print("Breadcrumb exists:", variables.breadcrumb ~= nil)

-- Test breadcrumb text generation
if variables.breadcrumb then
  print("Current path:", vim.inspect(variables.breadcrumb.current_path))
  print("Breadcrumb text:", variables.breadcrumb:createBreadcrumbText())
  
  -- Test path modification
  variables.breadcrumb.current_path = {"Local"}
  print("After Local:", variables.breadcrumb:createBreadcrumbText())
  
  variables.breadcrumb.current_path = {"Local", "complexObject"}
  print("After complexObject:", variables.breadcrumb:createBreadcrumbText())
end