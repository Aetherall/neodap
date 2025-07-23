-- Simple test to verify breadcrumb navigation works
print("=== Testing Breadcrumb Navigation ===")

-- Load neodap and create instance
local neodap = require('neodap')
local manager, api = neodap.setup()
local variables = api:getPluginInstance(require('neodap.plugins.Variables'))

print("✓ Variables plugin loaded:", variables ~= nil)
print("✓ Breadcrumb exists:", variables.breadcrumb ~= nil)

if variables.breadcrumb then
  -- Test breadcrumb text generation
  print("\n--- Breadcrumb Text Tests ---")
  
  -- Test at root
  variables.breadcrumb.current_path = {}
  local text1 = variables.breadcrumb:createBreadcrumbText()
  print("Root:", text1)
  assert(text1 == "📍 Variables", "Root breadcrumb should be 'Variables'")
  
  -- Test with Local path
  variables.breadcrumb.current_path = {"Local"}
  local text2 = variables.breadcrumb:createBreadcrumbText()
  print("Local:", text2)
  assert(text2 == "📍 Variables > Local", "Local breadcrumb incorrect")
  
  -- Test with deeper path
  variables.breadcrumb.current_path = {"Local", "complexObject", "level1"}
  local text3 = variables.breadcrumb:createBreadcrumbText()
  print("Deep:", text3)
  assert(text3 == "📍 Variables > Local > complexObject > level1", "Deep breadcrumb incorrect")
  
  print("\n--- Navigation Command Tests ---")
  
  -- Test navigateDown
  variables.breadcrumb.current_path = {}
  variables.breadcrumb.navigation_history = {}
  variables.breadcrumb:navigateDown("Local")
  assert(#variables.breadcrumb.current_path == 1, "NavigateDown should add to path")
  assert(variables.breadcrumb.current_path[1] == "Local", "NavigateDown should add correct segment")
  print("✓ NavigateDown works")
  
  -- Test navigateDown again
  variables.breadcrumb:navigateDown("complexObject")
  assert(#variables.breadcrumb.current_path == 2, "Second navigateDown should add to path")
  assert(variables.breadcrumb.current_path[2] == "complexObject", "Second segment incorrect")
  print("✓ Multiple NavigateDown works")
  
  -- Test navigateUp
  variables.breadcrumb:navigateUp()
  assert(#variables.breadcrumb.current_path == 1, "NavigateUp should remove from path")
  assert(variables.breadcrumb.current_path[1] == "Local", "NavigateUp should leave correct segment")
  print("✓ NavigateUp works")
  
  -- Test navigateBack
  variables.breadcrumb:navigateBack()
  assert(#variables.breadcrumb.current_path == 2, "NavigateBack should restore previous path")
  print("✓ NavigateBack works")
  
  -- Test navigateToRoot
  variables.breadcrumb:navigateToRoot()
  assert(#variables.breadcrumb.current_path == 0, "NavigateToRoot should clear path")
  print("✓ NavigateToRoot works")
  
  print("\n=== ALL TESTS PASSED ===")
  print("Breadcrumb navigation is working correctly!")
  
else
  print("ERROR: Breadcrumb not initialized")
end