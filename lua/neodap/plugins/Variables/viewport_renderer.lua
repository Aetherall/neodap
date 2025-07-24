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

  -- Return just the base display - geometric indicators are added in prepareNodeLineWithGeometry
  return base_display
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

  -- Sort by path order and depth
  -- table.sort(sorted_list, function(a, b)
  --   -- First, sort by path depth
  --   if #a.path ~= #b.path then
  --     return #a.path < #b.path
  --   end

  --   -- Then by path components
  --   for i = 1, #a.path do
  --     if a.path[i] ~= b.path[i] then
  --       -- Try to maintain scope order
  --       if i == 1 then
  --         -- For scopes, maintain their natural order
  --         local a_scope_order = a.node.name == "Local" and 1 or (a.node.name == "Global" and 2 or 3)
  --         local b_scope_order = b.node.name == "Local" and 1 or (b.node.name == "Global" and 2 or 3)
  --         if a_scope_order ~= b_scope_order then
  --           return a_scope_order < b_scope_order
  --         end
  --       end
  --       return a.path[i] < b.path[i]
  --     end
  --   end

  --   -- Finally by name
  --   return (a.node.name or "") < (b.node.name or "")
  -- end)

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

  -- Calculate proper indentation based on depth
  local path = geometry.path or {}
  local depth = math.max(0, #path - 1)
  local indent = string.rep("  ", depth)
  line:append(indent)

  -- Add relationship indicators based on geometry
  local relationship = geometry.relationship

  if relationship == "focus" then
    -- Focus node - show expanded indicator
    if node.is_expandable then
      line:append("▾ ", "Special")
    else
      line:append("  ")
    end
  elseif depth > 0 then
    -- Non-root nodes - show tree connectors
    if node.is_expandable then
      line:append("▸ ", "NonText")
    else
      line:append("  ")
    end
  else
    -- Root level nodes (scopes)
    line:append("  ")
  end

  -- Add icon
  local icon, highlight
  if node.type == "scope" then
    local scope_icon = VisualImprovements.SCOPE_ICONS[node.name] or VisualImprovements.SCOPE_ICONS["Block"]
    icon = scope_icon
    highlight = "Directory"
  else
    icon = VisualImprovements.getIcon(node.varType, node.is_expandable)
    highlight = node.is_expandable and "Directory" or "Normal"
  end

  line:append(icon .. " ", highlight)

  -- Add the node text
  if node.type == "variable" then
    -- For variables, parse the display text for highlighting
    local text = node.text or VisualImprovements.formatVariableDisplay(node.variable or node.dap_data)
    local colonPos = text:find(": ")

    if colonPos then
      -- Property name
      local propName = text:sub(1, colonPos - 1)
      local value = text:sub(colonPos + 2)

      -- Special highlighting for internal properties
      if propName:match("^%[%[") then
        line:append(propName, "Comment")
      else
        line:append(propName, "Identifier")
      end

      line:append(": ", "Delimiter")

      -- Value with appropriate highlighting
      if value:match("^'.*'$") or value:match('^".*"$') then
        line:append(value, "String")
      elseif value == "true" or value == "false" then
        line:append(value, "Boolean")
      elseif value == "null" or value == "undefined" then
        line:append(value, "Keyword")
      elseif tonumber('0' .. value) then
        line:append(value, "Number")
      else
        line:append(value, "Normal")
      end
    else
      -- No value, just the name
      if text:match("^%[%[") then
        line:append(text, "Comment")
      else
        line:append(text)
      end
    end
  else
    -- Scope nodes
    line:append(node.name or node.text)
  end

  -- Add focus indicator
  if relationship == "focus" then
    line:append(" ← HERE", "Special")
  end

  return line
end

-- ================================
-- VIEWPORT STYLE FUNCTIONS
-- ================================

---Apply viewport style modifications to rendered nodes
---@param rendered_nodes table<string, {node: table, display: string, geometry: NodeGeometry}>
---@param viewport Viewport Current viewport state
---@return table<string, {node: table, display: string, geometry: NodeGeometry}>
function M.applyViewportStyle(rendered_nodes, viewport)
  -- Style modifiers based on viewport style setting
  if viewport.style == "minimal" then
    -- Remove extra decorations
    for _, node_data in pairs(rendered_nodes) do
      node_data.display = node_data.display:gsub(" ← HERE", "")
    end
  elseif viewport.style == "highlight" then
    -- Add emphasis to focus path
    for _, node_data in pairs(rendered_nodes) do
      if node_data.geometry.on_focus_path then
        node_data.display = "➜ " .. node_data.display
      end
    end
  elseif viewport.style == "full" then
    -- Add full path information
    for _, node_data in pairs(rendered_nodes) do
      if #node_data.path > 0 then
        node_data.display = node_data.display .. " [" .. table.concat(node_data.path, ".") .. "]"
      end
    end
  end

  return rendered_nodes
end

-- ================================
-- BREADCRUMB HEADER FUNCTIONS
-- ================================

---Create breadcrumb header lines for viewport
---@param viewport Viewport Current viewport state
---@param width number Width of the window
---@return NuiLine[] Header lines
function M.createBreadcrumbHeader(viewport, width)
  local lines = {}

  -- Create breadcrumb line
  local breadcrumb_line = NuiLine()
  breadcrumb_line:append(M.createBreadcrumbDisplay(viewport), "Title")
  table.insert(lines, breadcrumb_line)

  -- Create separator line
  local separator_line = NuiLine()
  separator_line:append(M.createSeparatorLine(width), "NonText")
  table.insert(lines, separator_line)

  return lines
end

return M
