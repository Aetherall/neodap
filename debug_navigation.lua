-- Quick debug for breadcrumb navigation
local neodap = require('neodap')
local manager, api = neodap.setup()

-- Load Variables plugin
local variables_plugin = api:getPluginInstance(require('neodap.plugins.Variables'))

print("Variables plugin loaded:", variables_plugin ~= nil)
print("Breadcrumb mode:", variables_plugin.breadcrumb_mode)

-- Try accessing breadcrumb
if variables_plugin.breadcrumb then
  print("Breadcrumb exists:", true)
  print("Current path:", vim.inspect(variables_plugin.breadcrumb.current_path))
else
  print("Breadcrumb does not exist")
end