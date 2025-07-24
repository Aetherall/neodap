-- Tree Manager: Builds and manages the variable tree structure
-- Uses enhanced API objects that are already NuiTree.Nodes

local Logger = require('neodap.tools.logger')

-- ========================================
-- TREE MANAGER CLASS
-- ========================================

local TreeManager = {}
TreeManager.__index = TreeManager

function TreeManager.new()
  return setmetatable({
    logger = Logger.get("Variables2:TreeManager"),
    node_cache = {},  -- Cache for expanded nodes
  }, TreeManager)
end

-- ========================================
-- TREE BUILDING METHODS
-- ========================================

-- Build complete tree from a debug frame
function TreeManager:buildTree(frame)
  if not frame then
    self.logger:debug("No frame provided, returning empty tree")
    return {}
  end
  
  self.logger:debug("Building tree for frame")
  
  -- Get scopes - they're already NuiTree.Nodes!
  local scopes = frame:scopes()
  local tree_nodes = {}
  
  for _, scope in ipairs(scopes) do
    -- scope is already a NuiTree.Node with Scope methods
    table.insert(tree_nodes, scope)
    
    self.logger:debug("Added scope: " .. scope:get_id())
  end
  
  return tree_nodes
end

-- Build tree with variables expanded for specific scopes
function TreeManager:buildExpandedTree(frame, expanded_scope_ids)
  expanded_scope_ids = expanded_scope_ids or {}
  
  local tree_nodes = self:buildTree(frame)
  
  -- Expand requested scopes
  for _, scope in ipairs(tree_nodes) do
    local scope_id = scope:get_id()
    
    if expanded_scope_ids[scope_id] then
      self.logger:debug("Expanding scope: " .. scope_id)
      
      -- Get variables - they're already NuiTree.Nodes!
      local variables = scope:GetTreeNodeChildren()  -- Async method
      
      if variables then
        for _, variable in ipairs(variables) do
          table.insert(tree_nodes, variable)
          self.logger:debug("Added variable: " .. variable:get_id())
        end
      end
    end
  end
  
  return tree_nodes
end

-- Build tree with full expansion (all scopes and their variables)
function TreeManager:buildFullTree(frame)
  if not frame then
    return {}
  end
  
  local scopes = frame:scopes()
  local tree_nodes = {}
  
  for _, scope in ipairs(scopes) do
    table.insert(tree_nodes, scope)
    
    -- Get all variables in this scope
    local variables = scope:GetTreeNodeChildren()  -- Async method
    
    if variables then
      for _, variable in ipairs(variables) do
        table.insert(tree_nodes, variable)
      end
    end
  end
  
  return tree_nodes
end

-- ========================================
-- NODE EXPANSION METHODS
-- ========================================

-- Expand a specific node (load its children)
function TreeManager:expandNode(node)
  if not node then
    return nil
  end
  
  local node_id = node:get_id()
  self.logger:debug("Expanding node: " .. node_id)
  
  -- Check if node is expandable
  if not node:isTreeNodeExpandable() then
    self.logger:debug("Node is not expandable: " .. node_id)
    return nil
  end
  
  -- Get children - this uses the enhanced API methods
  local children = node:GetTreeNodeChildren()  -- Async method
  
  if children then
    self.logger:debug("Loaded " .. #children .. " children for " .. node_id)
    
    -- Cache the expansion
    self.node_cache[node_id] = {
      expanded = true,
      children = children,
      timestamp = os.time(),
    }
    
    return children
  else
    self.logger:debug("No children found for " .. node_id)
    return nil
  end
end

-- Check if a node is expanded
function TreeManager:isNodeExpanded(node)
  local node_id = node:get_id()
  local cached = self.node_cache[node_id]
  return cached and cached.expanded or false
end

-- Collapse a node
function TreeManager:collapseNode(node)
  local node_id = node:get_id()
  self.logger:debug("Collapsing node: " .. node_id)
  
  if self.node_cache[node_id] then
    self.node_cache[node_id].expanded = false
  end
end

-- ========================================
-- TREE NAVIGATION METHODS
-- ========================================

-- Find a node by path in the tree  
function TreeManager:findNodeByPath(tree_nodes, path)
  if not path or #path == 0 then
    return nil
  end
  
  -- Start with root level nodes
  local current_nodes = tree_nodes
  local target_node = nil
  
  for i, path_segment in ipairs(path) do
    target_node = nil
    
    -- Find node with matching name at current level
    for _, node in ipairs(current_nodes) do
      local node_path = node:getTreeNodePath()
      
      if node_path and #node_path >= i and node_path[i] == path_segment then
        target_node = node
        break
      end
    end
    
    if not target_node then
      self.logger:debug("Could not find path segment: " .. path_segment)
      return nil
    end
    
    -- If not the final segment, get children for next iteration
    if i < #path then
      local children = self:expandNode(target_node)
      if not children then
        self.logger:debug("Could not expand node for path: " .. path_segment)
        return nil
      end
      current_nodes = children
    end
  end
  
  return target_node
end

-- Get the parent of a node
function TreeManager:getNodeParent(node, tree_nodes)
  local node_path = node:getTreeNodePath()
  
  if not node_path or #node_path <= 1 then
    return nil  -- Root level node has no parent
  end
  
  -- Parent path is all but the last segment
  local parent_path = {}
  for i = 1, #node_path - 1 do
    table.insert(parent_path, node_path[i])
  end
  
  return self:findNodeByPath(tree_nodes, parent_path)
end

-- ========================================
-- CACHE MANAGEMENT
-- ========================================

-- Clear the node cache
function TreeManager:clearCache()
  self.logger:debug("Clearing node cache")
  self.node_cache = {}
end

-- Refresh a specific node's data
function TreeManager:refreshNode(node)
  local node_id = node:get_id()
  self.logger:debug("Refreshing node: " .. node_id)
  
  -- Clear cached data
  self.node_cache[node_id] = nil
  
  -- Refresh the node's value if it's a variable
  if node.RefreshValue then
    node:RefreshValue()  -- Async method
  end
  
  -- Re-expand if it was expanded
  if self:isNodeExpanded(node) then
    self:expandNode(node)
  end
end

-- Get cache statistics for debugging
function TreeManager:getCacheStats()
  local total_nodes = 0
  local expanded_nodes = 0
  
  for node_id, cache_entry in pairs(self.node_cache) do
    total_nodes = total_nodes + 1
    if cache_entry.expanded then
      expanded_nodes = expanded_nodes + 1
    end
  end
  
  return {
    total_cached_nodes = total_nodes,
    expanded_nodes = expanded_nodes,
    cache_size = total_nodes,
  }
end

-- ========================================
-- MODULE EXPORTS
-- ========================================

return TreeManager