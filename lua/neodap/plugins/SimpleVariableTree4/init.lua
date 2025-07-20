local M = {}
local nio = require("nio")

-- Neo-tree source properties  
M.name = "neodap_variables"
M.display_name = "Variables"

-- Required by Neo-tree
M.setup = function(config, global_config)
  -- Neo-tree initialization hook
  -- Ensure we have proper renderers if they weren't provided
  if not config.renderers then
    config.renderers = {}
  end
  
  -- Set default renderers if they don't exist
  if not config.renderers.directory then
    config.renderers.directory = {
      { "indent" },
      { "icon" },
      { "name", use_git_status_colors = false },
    }
  end
  
  if not config.renderers.file then
    config.renderers.file = {
      { "indent" },
      { "icon" },
      { "name", use_git_status_colors = false },
    }
  end
  
  -- Set up window mappings
  if not config.window then
    config.window = {}
  end
  if not config.window.mappings then
    config.window.mappings = {}
  end
  
  -- Override specific mappings for our source
  config.window.mappings["<cr>"] = "toggle_node"
  config.window.mappings["<space>"] = "toggle_node"
  config.window.mappings["o"] = "toggle_node"
end

-- Use filesystem components as a base
M.components = require("neo-tree.sources.filesystem.components")

-- Custom commands for variable expansion
M.commands = {
  toggle_node = function(state)
    local tree = state.tree
    local node = tree:get_node()
    
    if node and node.has_children then
      print("Toggling node:", node.id)
      
      -- Use Neo-tree's native toggle functionality
      local manager = require("neo-tree.sources.manager")
      local commands = require("neo-tree.sources.common.commands")
      
      -- Toggle the node using Neo-tree's built-in command
      commands.toggle_node(state)
    end
  end,
}

-- Store current frame for variable access
M.current_frame = nil

-- No manual expansion state or caching needed - Neo-tree handles this

-- Core plugin that provides variables
function M.plugin(api)
  -- Neo-tree source registration happens automatically when module is included in sources array
  -- No manual registration needed - follow SimpleVariableTree3 pattern
  
  -- Track current stopped frame
  api:onSession(function(session)
    session:onThread(function(thread)
      thread:onStopped(function()
        print("SimpleVariableTree4: Thread stopped, updating current frame")
        local stack = thread:stack()
        M.current_frame = stack and stack:top() or nil
        print("Frame set:", M.current_frame ~= nil)
        if M.current_frame then
          local scopes = M.current_frame:scopes()
          print("Frame has", scopes and #scopes or 0, "scopes")
          print("Ready for variable debugging - using pure Neo-tree source pattern")
        end
        
        -- Trigger Neo-tree refresh if available
        vim.schedule(function()
          local ok, manager = pcall(require, "neo-tree.sources.manager")
          if ok and manager then
            manager.refresh("neodap_variables")
          end
        end)
      end)
      
      thread:onContinued(function()
        print("SimpleVariableTree4: Thread continued, clearing frame")
        M.current_frame = nil
        
        -- Trigger Neo-tree refresh
        vim.schedule(function()
          local ok, manager = pcall(require, "neo-tree.sources.manager")
          if ok and manager then
            manager.refresh("neodap_variables")
          end
        end)
      end)
    end)
  end)
end

-- Convert variable reference to Neo-tree node
local function variable_to_node(var_ref, parent_id)
  -- Encode variable reference in the ID for nested expansion
  local node_id = parent_id and (parent_id .. "/" .. var_ref.name) or var_ref.name
  if var_ref.variablesReference and var_ref.variablesReference > 0 then
    node_id = node_id .. "#" .. var_ref.variablesReference
  end
  
  local is_expandable = var_ref.variablesReference and var_ref.variablesReference > 0
  
  local node = {
    id = node_id,
    name = var_ref.name .. ": " .. (var_ref.value or ""),
    type = is_expandable and "directory" or "file",  -- Use directory for expandable nodes
    path = node_id,  -- Required by Neo-tree
    loaded = not is_expandable,  -- Expandable nodes start unloaded
    has_children = is_expandable,  -- Mark expandable nodes as having children
    extra = {
      variable_reference = var_ref.variablesReference,
      var_type = var_ref.type,
      var_value = var_ref.value,
    },
  }
  
  return node
end

-- Convert scope to Neo-tree node  
local function scope_to_node(scope_ref)
  local node_id = "scope_" .. scope_ref.variablesReference
  local node = {
    id = node_id,
    name = scope_ref.name,
    type = "directory",  -- Use directory type for proper expand/collapse icons
    path = node_id,  -- Required by Neo-tree
    loaded = false,  -- Scopes start unloaded to show expand icon
    has_children = true,  -- Mark as having children to show expand icon
    extra = {
      variables_reference = scope_ref.variablesReference,
      expensive = scope_ref.expensive,
    },
  }
  
  return node
end

-- Internal function to load variables data (like fs_scan.get_items)
local function load_variables_data(state, parent_id, callback)
  print("load_variables_data called with parent_id:", parent_id or "nil")
  
  if not M.current_frame then
    print("No current frame available")
    if callback then callback() end
    return
  end
  
  local nodes = {}
  
  if not parent_id then
    -- Root level: create root container and populate with scopes
    print("Loading root level scopes")
    local scopes = M.current_frame:scopes()
    if scopes then
      for _, scope in ipairs(scopes) do
        table.insert(nodes, scope_to_node(scope.ref))
      end
    end
    print("Loaded", #nodes, "scope nodes")
    
    -- For full tree render, we need to provide root nodes
    local renderer = require("neo-tree.ui.renderer")
    renderer.show_nodes(nodes, state, nil, callback)
    
  elseif parent_id:match("^scope_") then
    -- Expanding a scope: return its variables
    local variables_reference = tonumber(parent_id:match("^scope_(%d+)"))
    print("Loading scope variables with reference:", variables_reference)
    
    if variables_reference then
      -- Use direct DAP call to get variables
      local response = M.current_frame.stack.thread.session.ref.calls:variables({
        variablesReference = variables_reference,
        threadId = M.current_frame.stack.thread.id,
      }):wait()
      
      if response and response.variables then
        print("Loaded", #response.variables, "variables for scope")
        for _, var_ref in ipairs(response.variables) do
          table.insert(nodes, variable_to_node(var_ref, parent_id))
        end
      else
        print("No variables received for scope")
      end
    end
    
    -- For lazy loading, provide child nodes
    local renderer = require("neo-tree.ui.renderer")
    renderer.show_nodes(nodes, state, parent_id, callback)
    
  else
    -- Expanding a variable: return its child properties
    print("Loading variable children for parent_id:", parent_id)
    
    -- Extract variable reference from the encoded ID
    local variables_reference = parent_id:match("#(%d+)$")
    if variables_reference then
      variables_reference = tonumber(variables_reference)
      print("Loading child variables with reference:", variables_reference)
      
      -- Use direct DAP call to get child variables
      local response = M.current_frame.stack.thread.session.ref.calls:variables({
        variablesReference = variables_reference,
        threadId = M.current_frame.stack.thread.id,
      }):wait()
      
      if response and response.variables then
        print("Loaded", #response.variables, "child variables")
        for _, var_ref in ipairs(response.variables) do
          table.insert(nodes, variable_to_node(var_ref, parent_id))
        end
      else
        print("No child variables received")
      end
    else
      print("Could not extract variables_reference from parent_id")
    end
    
    -- For lazy loading, provide child nodes
    local renderer = require("neo-tree.ui.renderer")
    renderer.show_nodes(nodes, state, parent_id, callback)
  end
end

-- Navigate function that follows proper Neo-tree source pattern
function M.navigate(state, path, path_to_reveal, callback)
  print("navigate called with path:", path, "path_to_reveal:", path_to_reveal)
  
  -- Acquire window so Neo-tree can display our source
  local renderer = require("neo-tree.ui.renderer")
  renderer.acquire_window(state)
  
  state.dirty = false
  
  -- Set position if specified
  if path_to_reveal then
    renderer.position.set(state, path_to_reveal)
  end
  
  -- Load and display the variables data
  load_variables_data(state, nil, callback)
end

return M