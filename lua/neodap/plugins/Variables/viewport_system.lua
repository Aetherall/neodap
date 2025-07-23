-- Viewport System for Variables Plugin
-- Provides geometric navigation and rendering based on focus location
-- This replaces the dual-mode architecture with a single viewport-based system

local M = {}

---@class Viewport
---@field focus_path string[] Current focus location ["Local", "myVar", "property"]
---@field radius number How far from focus to show nodes (1-5)
---@field style string Rendering style ("full"|"contextual"|"minimal"|"highlight")
---@field history string[][] Navigation history for back button

---@class NodeGeometry
---@field depth_offset number Depth relative to focus (-1=parent, 0=sibling, 1=child)
---@field distance number Absolute distance from focus location
---@field on_focus_path boolean Whether node is on the path to current focus
---@field is_focus boolean Whether this node is the current focus
---@field relationship string Relationship type ("ancestor"|"focus"|"sibling"|"child"|"descendant")

-- ================================
-- VIEWPORT STATE MANAGEMENT
-- ================================

---Create a new viewport with default settings
---@param initial_focus? string[] Initial focus path
---@return Viewport
function M.createViewport(initial_focus)
  return {
    focus_path = initial_focus or {},
    radius = 2,
    style = "contextual",
    history = {}
  }
end

---Reset viewport to root with history tracking
---@param viewport Viewport
---@return Viewport
function M.resetToRoot(viewport)
  if #viewport.focus_path > 0 then
    table.insert(viewport.history, vim.deepcopy(viewport.focus_path))
  end
  viewport.focus_path = {}
  return viewport
end

---Navigate back in history
---@param viewport Viewport
---@return Viewport
function M.navigateBack(viewport)
  if #viewport.history > 0 then
    viewport.focus_path = table.remove(viewport.history)
  end
  return viewport
end

-- ================================
-- PATH MANIPULATION FUNCTIONS
-- ================================

---Extend a path with a new segment
---@param path string[]
---@param segment string
---@return string[]
function M.extendPath(path, segment)
  local new_path = vim.deepcopy(path)
  table.insert(new_path, segment)
  return new_path
end

---Shorten a path by removing the last segment
---@param path string[]
---@return string[]
function M.shortenPath(path)
  if #path == 0 then return {} end
  local new_path = vim.deepcopy(path)
  table.remove(new_path)
  return new_path
end

---Check if two paths are equal
---@param path1 string[]
---@param path2 string[]
---@return boolean
function M.arePathsEqual(path1, path2)
  if #path1 ~= #path2 then return false end
  for i = 1, #path1 do
    if path1[i] ~= path2[i] then return false end
  end
  return true
end

---Check if node_path contains focus_path as a prefix
---@param node_path string[]
---@param focus_path string[]
---@return boolean
function M.isNodeOnPath(node_path, focus_path)
  if #node_path < #focus_path then return false end
  for i = 1, #focus_path do
    if node_path[i] ~= focus_path[i] then return false end
  end
  return true
end

---Get the common prefix between two paths
---@param path1 string[]
---@param path2 string[]
---@return string[]
function M.getCommonPrefix(path1, path2)
  local common = {}
  local min_length = math.min(#path1, #path2)

  for i = 1, min_length do
    if path1[i] == path2[i] then
      table.insert(common, path1[i])
    else
      break
    end
  end

  return common
end

-- ================================
-- GEOMETRIC CALCULATIONS
-- ================================

---Calculate geometric distance between two paths
---@param node_path string[]
---@param focus_path string[]
---@return number
function M.calculateDistance(node_path, focus_path)
  local common_prefix = M.getCommonPrefix(node_path, focus_path)
  local distance = (#node_path - #common_prefix) + (#focus_path - #common_prefix)
  return distance
end

---Calculate depth offset relative to focus
---@param node_path string[]
---@param focus_path string[]
---@return number
function M.calculateDepthOffset(node_path, focus_path)
  return #node_path - #focus_path
end

---Determine relationship between node and focus
---@param node_path string[]
---@param focus_path string[]
---@return string
function M.determineRelationship(node_path, focus_path)
  if M.arePathsEqual(node_path, focus_path) then
    return "focus"
  end

  local depth_offset = M.calculateDepthOffset(node_path, focus_path)
  local on_focus_path = M.isNodeOnPath(node_path, focus_path)
  local focus_on_node_path = M.isNodeOnPath(focus_path, node_path)

  if focus_on_node_path and depth_offset < 0 then
    return "ancestor"
  elseif on_focus_path and depth_offset > 0 then
    return "descendant"
  elseif depth_offset == 0 then
    return "sibling"
  elseif depth_offset == 1 then
    return "child"
  else
    return "distant"
  end
end

---Calculate complete node geometry relative to focus
---@param node_path string[]
---@param focus_path string[]
---@return NodeGeometry
function M.calculateNodeGeometry(node_path, focus_path)
  return {
    depth_offset = M.calculateDepthOffset(node_path, focus_path),
    distance = M.calculateDistance(node_path, focus_path),
    on_focus_path = M.isNodeOnPath(node_path, focus_path),
    is_focus = M.arePathsEqual(node_path, focus_path),
    relationship = M.determineRelationship(node_path, focus_path)
  }
end

-- ================================
-- TREE TRAVERSAL UTILITIES
-- ================================

---Extract path from node using IdGenerator format
---@param node table Node with id field
---@return string[]
function M.getPathToNode(node)
  if not node or not node.id then return {} end

  local path = {}
  local id = node.id

  -- Parse IdGenerator format: "scope[123]:Local.myVar[0].property"
  -- First extract scope part
  local scope_part, rest = id:match("^scope%[%d+%]:([^.]+)(.*)$")
  if scope_part then
    table.insert(path, scope_part)

    -- Parse the rest of the path
    if rest and rest ~= "" then
      -- Remove leading dot
      rest = rest:gsub("^%.", "")

      -- Split by dots, handling brackets
      local current = ""
      local in_brackets = false

      for char in rest:gmatch(".") do
        if char == "[" then
          if current ~= "" then
            table.insert(path, current)
            current = ""
          end
          current = current .. char
          in_brackets = true
        elseif char == "]" then
          current = current .. char
          table.insert(path, current)
          current = ""
          in_brackets = false
        elseif char == "." and not in_brackets then
          if current ~= "" then
            table.insert(path, current)
            current = ""
          end
        else
          current = current .. char
        end
      end

      if current ~= "" then
        table.insert(path, current)
      end
    end
  end

  return path
end

---Find node in tree by following a path
---@param tree table[] Root nodes of the tree
---@param path string[] Path to follow
---@return table? Found node or nil
function M.findNodeByPath(tree, path)
  if #path == 0 then return nil end

  local current_nodes = tree
  local current_node = nil

  for i, segment in ipairs(path) do
    current_node = nil

    -- Find node with matching name in current level
    for _, node in ipairs(current_nodes) do
      local node_name = node.name or ""

      -- For scope nodes, extract base name
      if node.type == "scope" then
        local base_name = node_name:match("^(%w+)") or node_name
        if base_name == segment then
          current_node = node
          break
        end
      else
        -- For variables, exact match
        if node_name == segment then
          current_node = node
          break
        end
      end
    end

    if not current_node then return nil end

    -- Get children for next iteration (if not last segment)
    if i < #path then
      if current_node.children then
        current_nodes = current_node.children
      else
        return nil -- Path continues but node has no children
      end
    end
  end

  return current_node
end

---Get all nodes within radius of focus location
---@param tree table[] Root nodes
---@param focus_path string[] Current focus location
---@param radius number Maximum distance from focus
---@return table<string, {node: table, geometry: NodeGeometry}>
function M.GetNodesInRadius(tree, focus_path, radius)
  local visible_nodes = {}

  -- Recursive function to walk all nodes
  local function walkNodes(nodes, current_path)
    current_path = current_path or {}

    for _, node in ipairs(nodes) do
      local node_path = vim.deepcopy(current_path)

      -- Add current node name to path
      local node_name = node.name or ""
      if node.type == "scope" then
        -- Extract base name for scopes
        node_name = node_name:match("^(%w+)") or node_name
      end
      table.insert(node_path, node_name)

      -- Calculate geometry
      local geometry = M.calculateNodeGeometry(node_path, focus_path)

      -- Include if within radius
      if geometry.distance <= radius then
        visible_nodes[node.id] = {
          node = node,
          geometry = geometry,
          path = node_path
        }
      end

      -- Recursively process children
      if node.children and #node.children > 0 then
        walkNodes(node.children, node_path)
      end
    end
  end

  walkNodes(tree)
  return visible_nodes
end

---Check if viewport should show a node based on focus and style
---@param geometry NodeGeometry
---@param viewport Viewport
---@return boolean
function M.shouldShowNode(geometry, viewport)
  -- Always show nodes within radius
  if geometry.distance <= viewport.radius then
    return true
  end

  -- Style-specific visibility rules
  if viewport.style == "full" then
    return true                                 -- Show everything in full mode
  elseif viewport.style == "minimal" then
    return geometry.distance <= 1               -- Very focused view
  elseif viewport.style == "contextual" then
    return geometry.distance <= viewport.radius -- Respect radius
  elseif viewport.style == "highlight" then
    -- Show focus path and immediate surroundings
    return geometry.on_focus_path or geometry.distance <= 1
  end

  return false
end

return M
