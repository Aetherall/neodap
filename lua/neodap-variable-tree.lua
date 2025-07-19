-- Neo-tree source module for neodap variable tree
-- This file allows Neo-tree to require("neodap-variable-tree")

local M = {
  name = "neodap-variable-tree",
  display_name = "🐛 Variables",
}

-- This will be set by the plugin when it initializes
local plugin_instance = nil

function M.set_plugin_instance(instance)
  plugin_instance = instance
end

-- Navigate method (required by Neo-tree)
function M.navigate(state, path)
  if not plugin_instance or not plugin_instance.current_frame then
    local renderer = require("neo-tree.ui.renderer")
    renderer.show_nodes({}, state)
    return
  end
  
  -- Build nodes for scopes
  local nodes = {}
  for _, scope in ipairs(plugin_instance.current_frame:scopes()) do
    table.insert(nodes, {
      id = "scope_" .. scope.ref.variablesReference,
      name = scope.ref.name,
      type = "scope",
      has_children = true,
      loaded = plugin_instance.variableCore:shouldAutoExpand(scope.ref)
    })
  end
  
  local renderer = require("neo-tree.ui.renderer")
  renderer.show_nodes(nodes, state)
end

-- Get items method for async loading
M.get_items = require("nio").create(function(_, parent_id, callback)
  if not plugin_instance or not plugin_instance.current_frame then
    return callback({})
  end
  
  if not parent_id then
    -- Scopes (root level)
    local nodes = {}
    for _, scope in ipairs(plugin_instance.current_frame:scopes()) do
      table.insert(nodes, {
        id = "scope_" .. scope.ref.variablesReference,
        name = scope.ref.name,
        type = "scope",
        has_children = true,
        loaded = plugin_instance.variableCore:shouldAutoExpand(scope.ref)
      })
    end
    callback(nodes)
  else
    -- Variables for a scope
    local ref = tonumber(parent_id:match("scope_(%d+)"))
    if ref then
      local nodes = {}
      for _, var in ipairs(plugin_instance.current_frame:variables(ref)) do
        local formatted_name = var.name
        if var.value then
          local formatted_value = plugin_instance.variableCore:formatVariableValue(var)
          formatted_name = var.name .. " = " .. formatted_value
          if var.type then
            formatted_name = formatted_name .. " : " .. var.type
          end
        end
        table.insert(nodes, {
          id = parent_id .. "." .. var.name,
          name = formatted_name,
          type = "variable",
          has_children = var.variablesReference and var.variablesReference > 0
        })
      end
      callback(nodes)
    else
      callback({})
    end
  end
end, 1)

-- Setup method (for Neo-tree source configuration)
function M.setup(config, global_config)
  -- Optional setup logic
end

return M