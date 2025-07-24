-- UI Manager: Handles NuiTree integration and visual rendering
-- Works directly with node-enhanced API objects

local NuiSplit = require("nui.split")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local Logger = require('neodap.tools.logger')

-- ========================================
-- UI MANAGER CLASS
-- ========================================

local UIManager = {}
UIManager.__index = UIManager

function UIManager.new()
  return setmetatable({
    logger = Logger.get("Variables2:UIManager"),
    windows = {},      -- Track open windows by buffer
    active_tree = nil, -- Current NuiTree instance
  }, UIManager)
end

-- ========================================
-- WINDOW MANAGEMENT
-- ========================================

-- Create and show the variables window
function UIManager:showWindow()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Check if window already exists for this buffer
  if self.windows[bufnr] then
    self.logger:debug("Variables window already exists for buffer " .. bufnr)
    self.windows[bufnr].split:show()
    return self.windows[bufnr]
  end

  -- Create new split window
  local split = NuiSplit({
    relative = "win",
    position = "left",
    size = "30%",
  }, {
    buf_options = {
      filetype = "neo-tree",
      buftype = "nofile",
    },
    win_options = {
      number = false,
      relativenumber = false,
      signcolumn = "no",
    },
  })

  -- Create empty tree initially
  local tree = NuiTree({
    winid = split.winid,
    bufnr = bufnr,
    nodes = {},
    prepare_node = function(node)
      return self:prepareNodeLine(node)
    end,
  })

  -- Store window reference
  self.windows[bufnr] = {
    split = split,
    tree = tree,
    bufnr = bufnr,
  }

  self.active_tree = tree

  -- Show the split
  split:show()

  -- Set up keybindings
  self:setupKeybindings(tree)

  self.logger:debug("Created variables window for buffer " .. bufnr)

  return self.windows[bufnr]
end

-- Hide the variables window
function UIManager:hideWindow()
  local bufnr = vim.api.nvim_get_current_buf()
  local window = self.windows[bufnr]

  if window then
    window.split:hide()
    self.logger:debug("Hidden variables window for buffer " .. bufnr)
  end
end

-- Toggle window visibility
function UIManager:toggleWindow()
  local bufnr = vim.api.nvim_get_current_buf()
  local window = self.windows[bufnr]

  if window and window.split.winid and vim.api.nvim_win_is_valid(window.split.winid) then
    self:hideWindow()
  else
    self:showWindow()
  end
end

-- Close and cleanup window
function UIManager:closeWindow()
  local bufnr = vim.api.nvim_get_current_buf()
  local window = self.windows[bufnr]

  if window then
    window.split:unmount()
    self.windows[bufnr] = nil

    if self.active_tree == window.tree then
      self.active_tree = nil
    end

    self.logger:debug("Closed variables window for buffer " .. bufnr)
  end
end

-- ========================================
-- TREE RENDERING
-- ========================================

-- Update the tree with new nodes
function UIManager:updateTree(tree_nodes)
  if not self.active_tree then
    self.logger:debug("No active tree to update")
    return
  end

  -- tree_nodes are already NuiTree.Node instances!
  self.active_tree:set_nodes(tree_nodes)

  self.logger:debug("Updated tree with " .. #tree_nodes .. " nodes")
end

-- Prepare a line for display in the tree
function UIManager:prepareNodeLine(node)
  local line = NuiLine()

  -- Get node depth for indentation
  local depth = 0
  if node.getTreeNodePath then
    local path = node:getTreeNodePath()
    depth = math.max(0, #path - 1)
  end

  local indent = string.rep("  ", depth)
  line:append(indent)

  -- Add expand/collapse indicator
  if node:isTreeNodeExpandable() then
    if node:is_expanded() then
      line:append("▾ ", "NonText")
    else
      line:append("▸ ", "NonText")
    end
  else
    line:append("  ")
  end

  -- Add icon based on node type
  local icon, icon_hl = self:getNodeIcon(node)
  if icon then
    line:append(icon .. " ", icon_hl or "NeoTreeFileIcon")
  end

  -- Add the node text (already formatted by the API extension)
  local text = node.text or node:formatTreeNodeDisplay()
  line:append(text, "Normal")

  return line
end

-- Get appropriate icon for a node
function UIManager:getNodeIcon(node)
  -- Check if it's a scope
  if node.ref and node.ref.name then
    local scope_names = { "Local", "Global", "Arguments", "Registers", "Closure" }
    for _, scope_name in ipairs(scope_names) do
      if node.ref.name:match("^" .. scope_name) then
        return "📁", "NeoTreeDirectoryIcon" -- Scope icon
      end
    end
  end

  -- Must be a variable
  if node:isTreeNodeExpandable() then
    return "📦", "NeoTreeDirectoryIcon" -- Expandable variable
  else
    return "📄", "NeoTreeFileIcon" -- Simple variable
  end
end

-- ========================================
-- USER INTERACTIONS
-- ========================================

-- Setup keybindings for the tree
function UIManager:setupKeybindings(tree)
  local function map(key, action, desc)
    vim.keymap.set("n", key, action, {
      buffer = tree.bufnr,
      noremap = true,
      silent = true,
      desc = desc or "Variables2: " .. key,
    })
    -- tree:map("n", key, action, { desc = desc })
  end

  -- Navigation
  map("<CR>", function()
    local node = tree:get_node()
    if node then
      self:handleNodeActivation(node, tree)
    end
  end, "Expand/collapse node")

  map("o", function()
    local node = tree:get_node()
    if node then
      self:handleNodeActivation(node, tree)
    end
  end, "Expand/collapse node")

  -- Refresh
  map("r", function()
    self:refreshTree()
  end, "Refresh tree")

  -- Close window
  map("q", function()
    self:closeWindow()
  end, "Close variables window")

  self.logger:debug("Setup keybindings for variables tree")
end

-- Handle node activation (expand/collapse)
function UIManager:handleNodeActivation(node, tree)
  if not node:isTreeNodeExpandable() then
    self.logger:debug("Node is not expandable: " .. node:get_id())
    return
  end

  local node_id = node:get_id()

  if node:is_expanded() then
    -- Collapse the node
    node:collapse()
    self.logger:debug("Collapsed node: " .. node_id)
  else
    -- Expand the node - get children using the enhanced API
    local children = node:GetTreeNodeChildren() -- Async method

    if children and #children > 0 then
      node:expand()
      -- Add children to the tree (they're already NuiTree.Nodes!)
      -- The tree will handle the display automatically
      self.logger:debug("Expanded node: " .. node_id .. " with " .. #children .. " children")
    else
      self.logger:debug("No children to expand for node: " .. node_id)
    end
  end

  -- Refresh the tree display
  tree:render()
end

-- Refresh the entire tree
function UIManager:refreshTree()
  self.logger:debug("Refreshing variables tree")

  -- This would be called by the main plugin to rebuild the tree
  -- For now, just re-render what we have
  if self.active_tree then
    self.active_tree:render()
  end
end

-- ========================================
-- UTILITY METHODS
-- ========================================

-- Get the currently active tree instance
function UIManager:getActiveTree()
  return self.active_tree
end

-- Get window for current buffer
function UIManager:getCurrentWindow()
  local bufnr = vim.api.nvim_get_current_buf()
  return self.windows[bufnr]
end

-- Check if variables window is open
function UIManager:isWindowOpen()
  local window = self:getCurrentWindow()
  return window and window.split.winid and vim.api.nvim_win_is_valid(window.split.winid)
end

-- Focus the variables window
function UIManager:focusWindow()
  local window = self:getCurrentWindow()
  if window and window.split.winid and vim.api.nvim_win_is_valid(window.split.winid) then
    vim.api.nvim_set_current_win(window.split.winid)
    self.logger:debug("Focused variables window")
  end
end

-- ========================================
-- MODULE EXPORTS
-- ========================================

return UIManager
