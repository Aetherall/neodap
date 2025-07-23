-- Viewport Renderer for Variables Plugin
-- Handles geometric rendering of nodes based on their relationship to viewport focus
-- Replaces context-role based rendering with pure geometric relationships

local ViewportSystem = require('neodap.plugins.Variables.viewport_system')
local VisualImprovements = require('neodap.plugins.Variables.visual_improvements')
local NuiLine = require("nui.line")

local M = {}

-- ================================
-- GEOMETRIC RENDERING FUNCTIONS
-- ================================

---Render node based on its geometric relationship to viewport focus
---@param node table The node to render
---@param geometry NodeGeometry The node's geometric relationship to focus
---@param viewport Viewport Current viewport state
---@return string Display text for the node
function M.renderNodeWithGeometry(node, geometry, viewport)
  -- Get base display from existing visual improvements
  local base_display
  if node.type == "scope" then
    base_display = node.name or node.text or "Unknown Scope"
  else
    base_display = VisualImprovements.formatVariableDisplay(node.variable or node.dap_data or {
      name = node.name or "unknown",
      value = node.value or "",
      type = node.varType or "unknown"
    })
  end

  -- Apply geometric rendering based on relationship
  local relationship = geometry.relationship
  local depth_offset = geometry.depth_offset

  if relationship == "focus" then
    return "▾ " .. base_display .. " ← HERE"
  elseif relationship == "ancestor" then
    local level_indicator = string.rep("↑ ", math.abs(depth_offset))
    return level_indicator .. base_display .. " (up " .. math.abs(depth_offset) .. ")"
  elseif relationship == "sibling" then
    return "├─ " .. base_display
  elseif relationship == "child" then
    return "  " .. base_display
  elseif relationship == "descendant" then
    local indent = string.rep("  ", depth_offset)
    return indent .. base_display
  else
    -- Default rendering for distant nodes
    return base_display
  end
end

---Create breadcrumb display based on current viewport focus
---@param viewport Viewport Current viewport state
---@return string Breadcrumb text
function M.createBreadcrumbDisplay(viewport)
  local text = "📍 Variables"

  if #viewport.focus_path > 0 then
    for _, segment in ipairs(viewport.focus_path) do
      text = text .. " > " .. segment
    end
  end

  return text
end

---Create separator line for breadcrumb
---@param width? number Width of separator (default 60)
---@return string Separator line
function M.createSeparatorLine(width)
  width = width or 60
  return string.rep("─", width)
end

-- ================================
-- VIEWPORT-BASED TREE RENDERING
-- ================================

---Render complete tree at current viewport location
---@param complete_tree table[] The complete tree structure
---@param viewport Viewport Current viewport state
---@return table<string, {node: table, display: string, geometry: NodeGeometry}> Rendered nodes
function M.RenderTreeAtViewport(complete_tree, viewport)
  -- Get nodes within viewport radius
  local nodes_in_radius = ViewportSystem.GetNodesInRadius(
    complete_tree,
    viewport.focus_path,
    viewport.radius
  )

  local rendered_nodes = {}

  -- Render each visible node with geometric styling
  for node_id, node_data in pairs(nodes_in_radius) do
    local node = node_data.node
    local geometry = node_data.geometry

    -- Check if node should be visible based on viewport style
    if ViewportSystem.shouldShowNode(geometry, viewport) then
      rendered_nodes[node_id] = {
        node = node,
        display = M.renderNodeWithGeometry(node, geometry, viewport),
        geometry = geometry,
        path = node_data.path
      }
    end
  end

  return rendered_nodes
end

---Sort rendered nodes for display order
---@param rendered_nodes table<string, {node: table, display: string, geometry: NodeGeometry}>
---@return {id: string, node: table, display: string, geometry: NodeGeometry}[]
function M.sortNodesForDisplay(rendered_nodes)
  local sorted_list = {}

  -- Convert to array
  for node_id, node_data in pairs(rendered_nodes) do
    table.insert(sorted_list, {
      id = node_id,
      node = node_data.node,
      display = node_data.display,
      geometry = node_data.geometry,
      path = node_data.path
    })
  end

  -- Sort by geometric relationship and depth
  table.sort(sorted_list, function(a, b)
    local a_geo, b_geo = a.geometry, b.geometry

    -- Primary sort: relationship priority
    local relationship_priority = {
      ancestor = 1,
      focus = 2,
      sibling = 3,
      child = 4,
      descendant = 5,
      distant = 6
    }

    local a_priority = relationship_priority[a_geo.relationship] or 6
    local b_priority = relationship_priority[b_geo.relationship] or 6

    if a_priority ~= b_priority then
      return a_priority < b_priority
    end

    -- Secondary sort: by path depth and name
    if #a.path ~= #b.path then
      return #a.path < #b.path
    end

    -- Tertiary sort: alphabetical by node name
    local a_name = a.node.name or ""
    local b_name = b.node.name or ""
    return a_name < b_name
  end)

  return sorted_list
end

-- ================================
-- NUI INTEGRATION FUNCTIONS
-- ================================

---Prepare NUI line for a node with geometric styling
---@param node table The node to render
---@param geometry NodeGeometry Node's geometric relationship
---@param viewport Viewport Current viewport state
---@return NuiLine Prepared line for NUI rendering
function M.prepareNodeLineWithGeometry(node, geometry, viewport)
  local line = NuiLine()
  local relationship = geometry.relationship

  -- Add relationship indicators
  if relationship == "ancestor" then
    line:append("↑ ", "Comment")
  elseif relationship == "focus" then
    line:append("▾ ", "Special")
  elseif relationship == "sibling" then
    line:append("├─ ", "NonText")
  elseif relationship == "child" then
    line:append("  ", "Normal")
  end

  -- Use existing visual improvements for the main content
  local visual_line = VisualImprovements.prepareNodeLine(node, {
    useTreeGuides = false -- Disable tree guides in viewport mode
  })

  -- Append the formatted content
  if visual_line and visual_line._segments then
    for _, segment in ipairs(visual_line._segments) do
      if segment.text and segment.highlight then
        line:append(segment.text, segment.highlight)
      elseif segment.text then
        line:append(segment.text)
      end
    end
  else
    -- Fallback to simple text
    local display = M.renderNodeWithGeometry(node, geometry, viewport)
    line:append(display)
  end

  -- Add focus indicator for current focus
  if relationship == "focus" then
    line:append(" ← HERE", "WarningMsg")
  end

  return line
end

---Create breadcrumb header lines for NUI display
---@param viewport Viewport Current viewport state
---@param window_width? number Width for separator line
---@return {text: string, line: NuiLine}[] Header lines
function M.createBreadcrumbHeader(viewport, window_width)
  window_width = window_width or 60

  local breadcrumb_text = M.createBreadcrumbDisplay(viewport)
  local separator_text = M.createSeparatorLine(window_width)

  -- Create styled breadcrumb line
  local breadcrumb_line = NuiLine()
  breadcrumb_line:append("📍 ", "Special")
  breadcrumb_line:append("Variables", "Title")

  if #viewport.focus_path > 0 then
    for i, segment in ipairs(viewport.focus_path) do
      breadcrumb_line:append(" > ", "Comment")
      if i == #viewport.focus_path then
        -- Highlight current segment
        breadcrumb_line:append(segment, "Special")
      else
        breadcrumb_line:append(segment, "Normal")
      end
    end
  end

  -- Create separator line
  local separator_line = NuiLine()
  separator_line:append(separator_text, "Comment")

  return {
    { text = breadcrumb_text, line = breadcrumb_line },
    { text = separator_text,  line = separator_line }
  }
end

-- ================================
-- VIEWPORT STYLE RENDERING
-- ================================

---Apply style-specific rendering modifications
---@param rendered_nodes table<string, any> Rendered nodes
---@param viewport Viewport Current viewport state
---@return table<string, any> Style-modified nodes
function M.applyViewportStyle(rendered_nodes, viewport)
  if viewport.style == "minimal" then
    -- In minimal mode, reduce visual clutter
    for node_id, node_data in pairs(rendered_nodes) do
      if node_data.geometry.relationship == "distant" then
        rendered_nodes[node_id] = nil -- Remove distant nodes
      end
    end
  elseif viewport.style == "highlight" then
    -- In highlight mode, emphasize focus path
    for node_id, node_data in pairs(rendered_nodes) do
      if node_data.geometry.on_focus_path then
        node_data.display = "★ " .. node_data.display
      end
    end
  elseif viewport.style == "full" then
    -- Full mode shows everything without geometric indicators
    for node_id, node_data in pairs(rendered_nodes) do
      local base_display = node_data.node.name or node_data.node.text or "unknown"
      node_data.display = base_display
    end
  end

  return rendered_nodes
end

return M
