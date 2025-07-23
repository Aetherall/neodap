-- Breadcrumb Navigation Prototype for Variables Tree
-- Implementation of Variation 1: Classic Breadcrumb with Focused View

local Class = require('neodap.tools.class')
local NuiSplit = require("nui.split")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")

---@class BreadcrumbVariables
---@field current_path string[] Path segments from root to current node
---@field focused_node_id string Currently focused node ID
---@field navigation_history string[][] Stack of previous paths for back navigation
local BreadcrumbVariables = Class()

-- Initialize breadcrumb navigation state
function BreadcrumbVariables:init(parentPlugin)
  self.parent = parentPlugin
  self.current_path = {}
  self.focused_node_id = nil
  self.navigation_history = {}
  self.breadcrumb_height = 2  -- Lines reserved for breadcrumb display
end

-- Navigate to a specific node by path
function BreadcrumbVariables:navigateToPath(path_segments)
  -- Save current path to history
  if #self.current_path > 0 then
    table.insert(self.navigation_history, vim.deepcopy(self.current_path))
  end
  
  self.current_path = path_segments or {}
  self:refreshView()
end

-- Navigate up one level in the hierarchy
function BreadcrumbVariables:navigateUp()
  if #self.current_path > 0 then
    table.insert(self.navigation_history, vim.deepcopy(self.current_path))
    table.remove(self.current_path) -- Remove last segment
    self:refreshView()
  end
end

-- Navigate to a child node
function BreadcrumbVariables:navigateDown(childName)
  table.insert(self.navigation_history, vim.deepcopy(self.current_path))
  table.insert(self.current_path, childName)
  self:refreshView()
end

-- Go back to previous location
function BreadcrumbVariables:navigateBack()
  if #self.navigation_history > 0 then
    self.current_path = table.remove(self.navigation_history)
    self:refreshView()
  end
end

-- Create breadcrumb display line
function BreadcrumbVariables:createBreadcrumbLine()
  local line = NuiLine()
  
  -- Home icon
  line:append("📍 ", "NeoTreeDirectoryIcon")
  
  if #self.current_path == 0 then
    line:append("Variables Root", "NeoTreeRootName")
    return line
  end
  
  -- Build path segments
  for i, segment in ipairs(self.current_path) do
    if i > 1 then
      line:append(" > ", "Comment")
    end
    
    -- Make segments clickable (future enhancement)
    local highlight = "NeoTreeDirectoryName"
    if i == #self.current_path then
      highlight = "NeoTreeFileNameOpened" -- Highlight current location
    end
    
    line:append(segment, highlight)
  end
  
  return line
end

-- Create separator line
function BreadcrumbVariables:createSeparatorLine()
  local line = NuiLine()
  line:append(string.rep("─", 60), "Comment")
  return line
end

-- Get nodes to display based on current path
function BreadcrumbVariables:getFilteredNodes()
  if not self.parent.current_frame then
    return {
      NuiTree.Node({
        id = "no-debug",
        name = "No active debug session",
        text = "No active debug session",
        type = "info",
      })
    }
  end
  
  -- Start with root scopes
  if #self.current_path == 0 then
    return self:getRootScopes()
  end
  
  -- Find the node matching our current path
  local current_node = self:findNodeByPath(self.current_path)
  if not current_node then
    -- Path not found, reset to root
    self.current_path = {}
    return self:getRootScopes()
  end
  
  -- Return children of current node
  return self:getNodeChildren(current_node)
end

-- Find a node by following a path
function BreadcrumbVariables:findNodeByPath(path)
  if #path == 0 then return nil end
  
  -- Start with root scopes
  local current_nodes = self:getRootScopes()
  local current_node = nil
  
  -- Follow each path segment
  for _, segment in ipairs(path) do
    current_node = self:findNodeByName(current_nodes, segment)
    if not current_node then
      return nil -- Path broken
    end
    
    -- Load children if needed
    if not current_node.loaded and current_node:has_children() then
      self.parent:loadNodeChildren(nil, current_node) -- Load synchronously
      current_node.loaded = true
    end
    
    current_nodes = current_node:has_children() and current_node:get_child_ids() or {}
  end
  
  return current_node
end

-- Find node by name in a list
function BreadcrumbVariables:findNodeByName(nodes, name)
  for _, node in ipairs(nodes) do
    if (node.name or node.text) == name then
      return node
    end
  end
  return nil
end

-- Get root scope nodes
function BreadcrumbVariables:getRootScopes()
  local nodes = {}
  local scopes = self.parent.current_frame:scopes()
  
  if scopes then
    for _, scope in ipairs(scopes) do
      local id = self.parent.id_generator.forScope(scope.ref)
      local node = NuiTree.Node({
        id = id,
        name = scope.ref.name,
        text = scope.ref.name,
        type = "scope",
        variablesReference = scope.ref.variablesReference,
        expensive = scope.ref.expensive,
        loaded = false,
      }, {})
      
      table.insert(nodes, node)
    end
  end
  
  return nodes
end

-- Get children of a specific node
function BreadcrumbVariables:getNodeChildren(node)
  if not node or not node:has_children() then
    return {}
  end
  
  -- Ensure children are loaded
  if not node.loaded then
    self.parent:loadNodeChildren(nil, node)
    node.loaded = true
  end
  
  return node:get_child_ids() or {}
end

-- Enhanced node rendering for breadcrumb mode
function BreadcrumbVariables:prepareNodeLine(node)
  local line = NuiLine()
  
  -- No indentation needed in breadcrumb mode!
  
  -- Expand indicator
  if node:has_children() then
    local indicator = node:is_expanded() and "▾ " or "▸ "
    line:append(indicator, "NeoTreeExpander")
  else
    line:append("  ")
  end
  
  -- Icon based on type (reuse existing logic)
  local icon, highlight = self:getNodeIcon(node)
  line:append(icon .. " ", highlight)
  
  -- Node text with breadcrumb-aware formatting
  local text = self:formatNodeText(node)
  line:append(text)
  
  return line
end

-- Get appropriate icon for node
function BreadcrumbVariables:getNodeIcon(node)
  -- Reuse parent's icon logic or simplify
  if node.type == "scope" then
    return "󰌾", "NeoTreeDirectoryIcon"
  elseif node.type == "variable" then
    if node.is_expandable then
      return "󰆩", "NeoTreeDirectoryIcon"
    else
      return "󰀫", "NeoTreeFileIcon"
    end
  else
    return "󰀫", "Normal"
  end
end

-- Format node text for breadcrumb view
function BreadcrumbVariables:formatNodeText(node)
  local text = node.name or node.text
  
  -- For expandable nodes, show preview info
  if node.is_expandable and node.variable then
    local var = node.variable
    if var.type == "Array" then
      local count = var.value and var.value:match("%((%d+)%)") or "?"
      text = text .. " [" .. count .. " items]"
    elseif var.type == "Object" then
      local count = var.value and var.value:match("%((%d+)%)") or "?"
      text = text .. " {" .. count .. " properties}"
    end
  end
  
  return text
end

-- Refresh the entire view
function BreadcrumbVariables:refreshView()
  -- Get current window
  local tabpage = vim.api.nvim_get_current_tabpage()
  local win = self.parent.windows[tabpage]
  if not win then return end
  
  -- Clear buffer
  vim.api.nvim_buf_set_lines(win.split.bufnr, 0, -1, false, {})
  
  -- Add breadcrumb
  local breadcrumb_line = self:createBreadcrumbLine()
  local separator_line = self:createSeparatorLine()
  
  -- Render breadcrumb manually (simplified)
  local breadcrumb_text = breadcrumb_line:render()
  local separator_text = separator_line:render()
  
  vim.api.nvim_buf_set_lines(win.split.bufnr, 0, 0, false, {
    breadcrumb_text,
    separator_text
  })
  
  -- Create new tree with filtered nodes
  local filtered_nodes = self:getFilteredNodes()
  
  win.tree = NuiTree({
    bufnr = win.split.bufnr,
    nodes = filtered_nodes,
    get_node_id = function(node) return node.id end,
    prepare_node = function(node)
      return self:prepareNodeLine(node)
    end,
  })
  
  -- Render tree starting after breadcrumb
  win.tree:render(self.breadcrumb_height + 1)
end

-- Enhanced toggle node for breadcrumb navigation
function BreadcrumbVariables:toggleNode(tree)
  local node = tree:get_node()
  if not node then return end
  
  -- If expandable, navigate down instead of just expanding
  if node:has_children() and not node:is_expanded() then
    local node_name = node.name or node.text
    self:navigateDown(node_name)
  elseif node:is_expanded() then
    node:collapse()
    tree:render(self.breadcrumb_height + 1)
  end
end

-- Setup breadcrumb-specific keybindings
function BreadcrumbVariables:setupBreadcrumbKeybindings(split, tree)
  local map = function(key, fn, desc)
    vim.keymap.set("n", key, fn, {
      buffer = split.bufnr,
      nowait = true,
      silent = true,
      desc = desc or ""
    })
  end
  
  -- Standard navigation
  map("<CR>", function() self:toggleNode(tree) end, "Navigate/Toggle node")
  map("o", function() self:toggleNode(tree) end, "Navigate/Toggle node")
  
  -- Breadcrumb-specific navigation
  map("u", function() self:navigateUp() end, "Go up one level")
  map("<BS>", function() self:navigateUp() end, "Go up one level")
  map("b", function() self:navigateBack() end, "Go back to previous location")
  map("r", function() self:navigateToPath({}) end, "Go to root")
  
  -- Quick navigation to breadcrumb segments (1-9)
  for i = 1, 9 do
    map(tostring(i), function()
      if i <= #self.current_path then
        local new_path = {}
        for j = 1, i do
          table.insert(new_path, self.current_path[j])
        end
        self:navigateToPath(new_path)
      end
    end, "Jump to breadcrumb segment " .. i)
  end
  
  -- Search within current level
  map("/", function()
    -- Implement search within current filtered view
    vim.cmd("normal! /")
  end, "Search current level")
  
  map("q", function() self.parent:Close() end, "Close variables")
end

-- Integration with parent Variables plugin
function BreadcrumbVariables:integrateWithParent()
  -- Override parent's toggle node behavior
  local original_toggle = self.parent.ToggleNode
  self.parent.ToggleNode = function(parent_self, tree)
    return self:toggleNode(tree)
  end
  
  -- Override parent's setup keybindings
  local original_setup_keys = self.parent.setupKeybindings
  self.parent.setupKeybindings = function(parent_self, split, tree)
    return self:setupBreadcrumbKeybindings(split, tree)
  end
  
  -- Override parent's refresh
  local original_refresh = self.parent.RefreshAllWindows
  self.parent.RefreshAllWindows = function(parent_self)
    self:refreshView()
  end
end

return BreadcrumbVariables