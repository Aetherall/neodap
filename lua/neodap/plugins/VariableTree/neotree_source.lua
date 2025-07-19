-- lua/neodap/plugins/VariableTree/neotree_source.lua
-- Neo-tree source module for Variable Tree

local M = {}

M.name = "neodap-variable-tree"
M.display_name = "Variable Tree"

local current_frame = nil
local variableCore = nil

-- Set the current frame and variableCore from the plugin
function M.set_context(frame, core)
  current_frame = frame
  variableCore = core
end

-- Convert variable to Neo-tree node format
local function variableToNode(var, parent_id)
  local node = {
    id = parent_id and (parent_id .. "." .. var.ref.name) or var.ref.name,
    name = var.ref.name,
    type = "variable",
    extra = {
      value = var.ref.value,
      type = var.ref.type,
      evaluateName = var.ref.evaluateName,
      variablesReference = var.ref.variablesReference,
    },
  }

  -- Add value to display using VariableCore formatting
  if variableCore then
    local formatted_value = variableCore:formatVariableValue(var.ref)
    node.name = string.format("%s = %s", var.ref.name, formatted_value)
    if var.ref.type then
      node.name = node.name .. " : " .. var.ref.type
    end
  else
    -- Fallback formatting if VariableCore is not available
    if var.ref.value then
      node.name = string.format("%s = %s", var.ref.name, var.ref.value)
      if var.ref.type then
        node.name = node.name .. " : " .. var.ref.type
      end
    else
      node.name = var.ref.name
    end
  end

  -- Check if variable has children (complex objects, arrays, etc.)
  if var.ref.variablesReference and var.ref.variablesReference > 0 then
    node.has_children = true
    node.children = {}
    -- Let Neo-tree manage expansion state - we just mark as expandable
    node.loaded = false
  end
  
  return node
end

-- Required method: show
function M.show(state, path, callback)
  if callback then callback() end
end

-- Required method: refresh
function M.refresh(state)
  local manager = require("neo-tree.sources.manager")
  manager.refresh(M.name)
end

-- Required method: navigate
function M.navigate(state, path)
  if current_frame then
    state.path = "/"
  end
end

-- Parse node ID to extract variable reference information
local function parseNodeId(node_id)
  if node_id:match("^scope_") then
    -- Scope node: "scope_12345"
    return "scope", tonumber(node_id:sub(7))
  elseif node_id:match("^var_") then
    -- Variable node: "var_12345" where 12345 is the variablesReference
    return "variable", tonumber(node_id:sub(5))
  else
    -- Legacy or unknown format
    return "unknown", nil
  end
end

-- Generate unique node ID for variables with children
local function generateVariableNodeId(var)
  if var.ref.variablesReference and var.ref.variablesReference > 0 then
    return "var_" .. tostring(var.ref.variablesReference)
  else
    -- For variables without children, use a simple name-based ID
    return "leaf_" .. (var.ref.name or "unknown")
  end
end

-- Get children for a node - async function
M.get_items = require("nio").create(function(state, parent_id, callback)
  if not current_frame then
    callback({})
    return
  end

  if not parent_id then
    -- Root level - show scopes
    local scopes = current_frame:scopes()
    if not scopes then
      callback({})
      return
    end

    local nodes = {}
    for _, scope in ipairs(scopes) do
      local scope_id = "scope_" .. tostring(scope.ref.variablesReference)
      
      -- Check if this scope should be auto-expanded initially
      -- After this, Neo-tree manages expansion state automatically
      local should_auto_expand = variableCore and variableCore:shouldAutoExpand(scope.ref) or false
      
      local node = {
        id = scope_id,
        name = scope.ref.name,
        type = "scope",
        has_children = true,
        loaded = should_auto_expand, -- Initial expansion state, then Neo-tree takes over
        children = {},
        extra = {
          expensive = scope.ref.expensive,
          variablesReference = scope.ref.variablesReference,
        },
      }
      table.insert(nodes, node)
    end

    callback(nodes)
  else
    -- Get variables for scope or nested variable
    local node_type, variablesReference = parseNodeId(parent_id)
    
    if not variablesReference then
      callback({})
      return
    end

    -- Fetch variables using the DAP variables reference
    local raw_variables = current_frame:variables(variablesReference)
    if raw_variables then
      local nodes = {}
      for _, raw_var in ipairs(raw_variables) do
        local wrapped_var = { ref = raw_var }
        local variable_node = variableToNode(wrapped_var, parent_id)
        
        -- Override the node ID to use our variable reference system for expandable variables
        if raw_var.variablesReference and raw_var.variablesReference > 0 then
          variable_node.id = generateVariableNodeId(wrapped_var)
        end
        
        table.insert(nodes, variable_node)
      end
      callback(nodes)
    else
      callback({})
    end
  end
end, 1)

return M