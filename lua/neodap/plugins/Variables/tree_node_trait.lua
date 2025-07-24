-- TreeNodeTrait: Adds tree behavior to neodap API objects
-- This trait allows Variable, Scope, and Frame objects to work directly as tree nodes

local TreeNodeTrait = {}

---Extend a class with tree node capabilities
---@param Class table The class to extend
---@return table The extended class
function TreeNodeTrait.extend(Class)
  -- Core tree interface methods
  
  ---Get a unique identifier for this node
  function Class:getTreeNodeId()
    -- Override in specific classes for proper IDs
    error("getTreeNodeId must be implemented by " .. (self.class_name or "class"))
  end
  
  ---Get display text for this node
  function Class:getTreeNodeText()
    if self.ref and self.ref.name then
      return self.ref.name
    end
    return tostring(self)
  end
  
  ---Get children of this node for tree display
  function Class:getTreeNodeChildren()
    -- Override in specific classes
    return nil
  end
  
  ---Check if this node can be expanded
  function Class:isTreeNodeExpandable()
    local children = self:getTreeNodeChildren()
    return children ~= nil and #children > 0
  end
  
  ---Get or create UI state for this node
  ---@param state_store table External state storage
  ---@return table UI state
  function Class:getTreeNodeState(state_store)
    local id = self:getTreeNodeId()
    if not state_store[id] then
      state_store[id] = {
        expanded = false,
        selected = false,
        visible = false,
        geometry = nil,
        children_loaded = false,
        cached_children = nil
      }
    end
    return state_store[id]
  end
  
  ---Toggle expansion state
  ---@param state_store table External state storage
  function Class:toggleTreeNodeExpanded(state_store)
    local state = self:getTreeNodeState(state_store)
    state.expanded = not state.expanded
    return state.expanded
  end
  
  ---Check if node is expanded
  ---@param state_store table External state storage
  ---@return boolean
  function Class:isTreeNodeExpanded(state_store)
    local state = self:getTreeNodeState(state_store)
    return state.expanded
  end
  
  ---Set node visibility
  ---@param state_store table External state storage
  ---@param visible boolean
  function Class:setTreeNodeVisible(state_store, visible)
    local state = self:getTreeNodeState(state_store)
    state.visible = visible
  end
  
  ---Get node geometry (viewport relationship)
  ---@param state_store table External state storage
  ---@return table|nil
  function Class:getTreeNodeGeometry(state_store)
    local state = self:getTreeNodeState(state_store)
    return state.geometry
  end
  
  ---Set node geometry (viewport relationship)
  ---@param state_store table External state storage
  ---@param geometry table
  function Class:setTreeNodeGeometry(state_store, geometry)
    local state = self:getTreeNodeState(state_store)
    state.geometry = geometry
  end
  
  ---Get the path to this node
  function Class:getTreeNodePath()
    -- Override in specific classes
    return {}
  end
  
  ---Format node for display (can be overridden)
  function Class:formatTreeNodeDisplay()
    return self:getTreeNodeText()
  end
  
  return Class
end

return TreeNodeTrait