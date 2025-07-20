local Class = require("neodap.tools.class")
local Logger = require("neodap.tools.logger")

---@class SimpleVariableTree3Props
---@field api Api
---@field logger Logger

---@class SimpleVariableTree3: SimpleVariableTree3Props
---@field new Constructor<SimpleVariableTree3Props>
local SimpleVariableTree3 = Class()

SimpleVariableTree3.name = "NeodapVariables"
SimpleVariableTree3.description = "Neodap Variables Tree (Neo-tree source)"
SimpleVariableTree3.display_name = "Variables"

SimpleVariableTree3.instance = nil;

-- Use common components suitable for any hierarchical data
local cc = require("neo-tree.sources.common.commands")
local utils = require("neo-tree.utils")
local renderer = require("neo-tree.ui.renderer")

-- Use filesystem components as base
SimpleVariableTree3.components = require("neo-tree.sources.filesystem.components")

-- Variable expansion function - NOT filesystem directory expansion
SimpleVariableTree3.toggle_variable = function(state, node, path_to_reveal, skip_redraw, recursive, callback)
  print("🚀 toggle_variable called!")
  local tree = state.tree
  if not node then
    node = assert(tree:get_node())
  end
  print("📊 Variable node type:", node.type, "loaded:", node.loaded)
  if node.type ~= "directory" then
    print("❌ Node is not expandable directory type, returning")
    return
  end
  
  state.explicitly_opened_nodes = state.explicitly_opened_nodes or {}
  
  if node.loaded == false then
    print("🔥 Variable not expanded, loading children!")
    -- Load variable children from DAP, not filesystem
    local id = node:get_id()
    state.explicitly_opened_nodes[id] = true
    renderer.position.set(state, nil)
    
    -- Call our variable loading method
    local instance = SimpleVariableTree3.instance
    if instance then
      print("✅ Calling LoadNodeChildren for node:", id)
      instance:LoadNodeChildren(state, node)
    else
      print("❌ No instance available")
    end
    
    if callback then callback() end
  elseif node:has_children() then
    print("🔄 Node has children, toggling expand/collapse")
    local updated = false
    if node:is_expanded() then
      updated = node:collapse()
      state.explicitly_opened_nodes[node:get_id()] = false
    else
      updated = node:expand()
    end
    if updated and not skip_redraw then
      renderer.redraw(state)
    end
  else
    print("❓ Node loaded but no children")
  end
end

-- Variable-specific commands - NOT filesystem commands
SimpleVariableTree3.commands = {
  -- Our custom toggle_node that expands variables, not directories
  toggle_node = function(state)
    print("🎯 Variable toggle_node command called!")
    local log = require("neodap.tools.logger").get("SimpleVariableTree3")
    log:info("toggle_node called")
    cc.toggle_node(state, utils.wrap(SimpleVariableTree3.toggle_variable, state))
  end,
  expand_all_nodes = function(state, node)
    cc.expand_all_nodes(state, node, SimpleVariableTree3.variable_prefetcher)
  end,
  expand_all_subnodes = function(state, node)
    cc.expand_all_subnodes(state, node, SimpleVariableTree3.variable_prefetcher)
  end,
}

-- Add common commands (but don't override our custom ones)
cc._add_common_commands(SimpleVariableTree3.commands)

-- Variable prefetcher for lazy loading variable children (not filesystem prefetching)
SimpleVariableTree3.variable_prefetcher = {
  prefetch = function(state, node)
    local instance = SimpleVariableTree3.instance
    if instance then
      instance:LoadNodeChildren(state, node)
    end
  end,
  should_prefetch = function(node)
    return not node.loaded and node.type == "directory"
  end,
}

function SimpleVariableTree3.plugin(api)
  local instance = SimpleVariableTree3:new({
    api = api,
    logger = Logger.get("Plugin:SimpleVariableTree3"),
  })
  instance:init()
  SimpleVariableTree3.instance = instance
  return instance
end

function SimpleVariableTree3:init()
  self.current_frame = nil

  -- Hook into DAP events (this is why we need API access!)
  self.api:onSession(function(session)
    -- Skip session ID 1 to avoid initialization conflicts
    if session.ref.id == 1 then return end
    
    session:onThread(function(thread)
      thread:onStopped(function()
        self.logger:info("Thread stopped, getting frame")
        local stack = thread:stack()
        if stack then
          self.current_frame = stack:top()

          require("neo-tree.sources.manager").refresh("NeodapVariables")

          self.logger:info("Got current frame:", self.current_frame ~= nil)
        end
      end)
    end)
  end)
end

function SimpleVariableTree3.navigate(state, path, path_to_reveal, callback, async)
  local instance = SimpleVariableTree3.instance
  if instance then
    return instance:Navigate(state, path, path_to_reveal, callback, async)
  end
  
  -- Fallback: create window and show message
  local renderer = require("neo-tree.ui.renderer")
  renderer.acquire_window(state)
  
  -- Return test data if no instance and call callback
  local items = {
    { id = "test1", name = "No debugging session", type = "file" }
  }
  
  if callback then
    callback()
  end
  
  return items
end

-- PascalCase for auto async wrapping
function SimpleVariableTree3:Navigate(state, path, path_to_reveal, callback, async)
  self.logger:info("Navigate called with path:", path, "state.path:", state.path)

  if not self.current_frame then
    self.logger:info("No current frame, returning empty")
    if callback then callback() end
    return {}
  end

  -- Set state path
  state.path = state.path or "/"
  
  local items = {}

  if not path then
    -- Root: return scopes
    self.logger:info("Getting scopes from current frame")
    local scopes = self.current_frame:scopes()
    self.logger:info("Got", #scopes, "scopes")
    for _, scope in ipairs(scopes) do
      local item = {
        id = "scope:" .. scope.ref.variablesReference,
        name = scope.ref.name,  -- Just the scope name (Local, Closure, Global)
        type = "directory",     -- Must be "directory" for Neo-tree to allow expansion
        path = "scope:" .. scope.ref.variablesReference,
        variable_ref = scope.ref.variablesReference,
        loaded = false,  -- Not expanded yet - will trigger variable loading
        -- Mark this as a DAP scope for our custom rendering
        is_dap_scope = true
      }
      self.logger:info("Adding scope:", scope.ref.name, "ref:", scope.ref.variablesReference, "id:", item.id)
      table.insert(items, item)
    end
  end

  self.logger:info("Returning", #items, "items for path:", path)
  for i, item in ipairs(items) do
    self.logger:info("  Item", i, ":", item.name, "type:", item.type, "path:", item.path, "loaded:", item.loaded)
  end
  
  -- Let Neo-tree handle the tree building and rendering
  local renderer = require("neo-tree.ui.renderer")
  renderer.show_nodes(items, state, path_to_reveal, callback)
  
  return items
end

-- PascalCase for auto async wrapping - loads children for a node
function SimpleVariableTree3:LoadNodeChildren(state, node)
  self.logger:info("LoadNodeChildren called for node:", node:get_id(), "type:", node.type)
  self.logger:info("Node properties:", vim.inspect({
    id = node:get_id(),
    type = node.type,
    variable_ref = node.variable_ref,
    path = node.path,
    name = node.name
  }))
  
  if not self.current_frame then
    self.logger:info("No current frame available")
    return
  end

  local children = {}
  
  -- Extract variable_ref from node ID if not directly available
  local variable_ref = node.variable_ref
  if not variable_ref and node:get_id():match("^scope:(%d+)$") then
    variable_ref = tonumber(node:get_id():match("^scope:(%d+)$"))
    self.logger:info("Extracted variable_ref from ID:", variable_ref)
  end
  
  if variable_ref and variable_ref > 0 then
    -- Load variables for this scope/variable reference
    self.logger:info("Loading variables for ref:", variable_ref)
    local variables = self.current_frame:variables(variable_ref)
    self.logger:info("Found", #variables, "variables")
    
    for i, var in ipairs(variables) do
      -- Create unique ID that includes parent context to avoid conflicts
      local child_id = node:get_id() .. ":child:" .. i .. ":" .. var.name
      
      local child_item = {
        id = child_id,
        name = var.name .. " = " .. (var.value or ""),
        type = (var.variablesReference and var.variablesReference > 0) and "directory" or "file",
        variable_ref = var.variablesReference or 0,
        loaded = var.variablesReference == 0 or var.variablesReference == nil,  -- primitives are loaded, objects need expansion
        parent_id = node:get_id(),
        -- Mark DAP variable types for custom rendering
        is_dap_variable = true,
        is_expandable = var.variablesReference and var.variablesReference > 0
      }
      
      self.logger:info("Adding child variable:", var.name, "value:", var.value, "ref:", var.variablesReference, "type:", child_item.type)
      table.insert(children, child_item)
    end
  else
    self.logger:info("Node has no variable_ref or ref is 0, skipping")
  end
  
  -- Add children to the tree using the correct Neo-tree pattern
  local renderer = require("neo-tree.ui.renderer")
  if #children > 0 then
    self.logger:info("Adding", #children, "children to parent:", node:get_id())
    renderer.show_nodes(children, state, node:get_id(), nil)
  end
  
  node.loaded = true
  self.logger:info("LoadNodeChildren completed, added", #children, "children")
end

function SimpleVariableTree3.setup(config, global_config)
  -- Simple setup required by Neo-tree
  print("SimpleVariableTree3 setup called")
end

return SimpleVariableTree3
