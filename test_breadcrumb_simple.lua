-- Test breadcrumb navigation directly without full debug session
-- This will test the logic without needing a running debugger

print("Testing breadcrumb navigation logic...")

-- Create a mock Variables plugin
local BreadcrumbNavigation = require('neodap.plugins.Variables.breadcrumb_navigation')

-- Create a mock parent with simple node structure
local mock_parent = {
  current_frame = {
    -- Mock the frame:variables() method
    variables = function(self, ref)
      if ref == 1 then -- Local scope
        return {
          {name = "complexObject", type = "Object", variablesReference = 2},
          {name = "simpleVar", type = "string", value = "test"}
        }
      elseif ref == 2 then -- complexObject
        return {
          {name = "level1", type = "Object", variablesReference = 3},
          {name = "description", type = "string", value = "test object"}
        }
      end
      return {}
    end
  },
  
  -- Mock getRootNodes method
  getRootNodes = function(self)
    local NuiTree = require("nui.tree")
    return {
      NuiTree.Node({
        id = "scope-local",
        name = "Local",
        text = "Local", 
        type = "scope",
        variablesReference = 1,
      }, {}),
      NuiTree.Node({
        id = "scope-global", 
        name = "Global",
        text = "Global",
        type = "scope",
        variablesReference = 99,
      }, {})
    }
  end,
  
  -- Mock createVariableNode method
  createVariableNode = function(self, var, parent_id)
    local NuiTree = require("nui.tree") 
    return NuiTree.Node({
      id = parent_id .. "-" .. var.name,
      name = var.name,
      text = var.name,
      type = "variable",
      variableReference = var.variablesReference,
      variable = var
    }, var.variablesReference and {} or nil)
  end
}

-- Create breadcrumb instance
local breadcrumb = BreadcrumbNavigation.create(mock_parent)

print("\n=== Testing Navigation Logic ===")

-- Test 1: Initial state
print("1. Initial breadcrumb:", breadcrumb:createBreadcrumbText())
print("   Current path:", vim.inspect(breadcrumb.current_path))

-- Test 2: Navigate into Local
print("\n2. Navigate into Local...")
breadcrumb:navigateDown("Local")
print("   Breadcrumb after Local:", breadcrumb:createBreadcrumbText())
print("   Current path:", vim.inspect(breadcrumb.current_path))

-- Test 3: Get filtered nodes (should show Local variables)
local filtered = breadcrumb:getFilteredNodes()
print("   Filtered nodes count:", #filtered)
for i, node in ipairs(filtered) do
  print("   Node " .. i .. ":", node.name or node.text)
end

-- Test 4: Navigate deeper
print("\n3. Navigate into complexObject...")
breadcrumb:navigateDown("complexObject")
print("   Breadcrumb after complexObject:", breadcrumb:createBreadcrumbText())
print("   Current path:", vim.inspect(breadcrumb.current_path))

-- Test 5: Get filtered nodes again
local filtered2 = breadcrumb:getFilteredNodes()
print("   Filtered nodes count:", #filtered2)
for i, node in ipairs(filtered2) do
  print("   Node " .. i .. ":", node.name or node.text)
end

-- Test 6: Navigate up
print("\n4. Navigate up...")
breadcrumb:navigateUp()
print("   Breadcrumb after up:", breadcrumb:createBreadcrumbText())
print("   Current path:", vim.inspect(breadcrumb.current_path))

print("\n=== Tests Complete ===")