-- Breadcrumb Navigation for Variables Tree
-- Provides hierarchical navigation with path display

local Class = require('neodap.tools.class')
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local NuiSplit = require("nui.split")
local VisualImprovements = require('neodap.plugins.Variables.visual_improvements')

---@class BreadcrumbNavigationProps
---@field parent VariablesTreeNui
---@field current_path string[]
---@field navigation_history string[][]
---@field breadcrumb_height number
---@field breadcrumb_splits table<number, {split: NuiSplit}>

---@class BreadcrumbNavigation: BreadcrumbNavigationProps
---@field new Constructor<BreadcrumbNavigationProps>
local BreadcrumbNavigation = Class()

---@param parent_plugin VariablesTreeNui
---@return BreadcrumbNavigation
function BreadcrumbNavigation.create(parent_plugin)
  local instance = BreadcrumbNavigation:new({
    parent = parent_plugin,
    current_path = {},
    navigation_history = {},
    breadcrumb_height = 2,
    breadcrumb_splits = {},
  })

  instance:init()
  return instance
end

function BreadcrumbNavigation:init()
  -- Initialization logic if needed
end

function BreadcrumbNavigation:initialize()
  -- Reset to root when entering breadcrumb mode
  self.current_path = {}
  self.navigation_history = {}
end

-- Create breadcrumb display text
function BreadcrumbNavigation:createBreadcrumbText()
  local text = "📍 "

  if #self.current_path == 0 then
    text = text .. "Variables"
    return text
  end

  -- Start with Variables root
  text = text .. "Variables"

  -- Build path segments
  for i, segment in ipairs(self.current_path) do
    text = text .. " > " .. segment
  end

  return text
end

-- Create separator line
function BreadcrumbNavigation:createSeparatorLine()
  local line = NuiLine()
  line:append(string.rep("─", 60), "Comment")
  return line
end

-- Get nodes to display based on current path with parent context (Variation 2)
function BreadcrumbNavigation:getFilteredNodes()
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
    return self.parent:getRootNodes()
  end

  -- Find the current node
  local current_node = self:findNodeByPath()
  if not current_node then
    -- Path not found, reset to root
    self.current_path = {}
    return self.parent:getRootNodes()
  end

  -- Build parent context display
  return self:buildParentContextView(current_node)
end

-- Find node by following current path
function BreadcrumbNavigation:findNodeByPath()
  if #self.current_path == 0 then return nil end

  -- Start with root scopes
  local current_nodes = self.parent:getRootNodes()
  local current_node = nil

  -- Follow each path segment
  for i, segment in ipairs(self.current_path) do
    current_node = self:findNodeByName(current_nodes, segment)
    if not current_node then
      -- Path broken, truncate to valid portion
      for j = i, #self.current_path do
        table.remove(self.current_path)
      end
      return nil
    end

    -- Load children if needed for next iteration
    if i < #self.current_path then
      -- Always load children for navigation, regardless of expand state
      current_nodes = self:getNodeChildren(current_node)
    end
  end

  return current_node
end

-- Find node by name in a list
function BreadcrumbNavigation:findNodeByName(nodes, name)
  for _, node in ipairs(nodes) do
    local node_name = node.name or ""

    -- For scope nodes, extract base name (e.g., "Local: testFunction" -> "Local")
    if node.type == "scope" then
      local base_name = node_name:match("^(%w+)") or node_name
      if base_name == name then
        return node
      end
    else
      -- For variables, use exact match on pure name (no preview data)
      if node_name == name then
        return node
      end
    end
  end

  return nil
end

-- Get children of a node
function BreadcrumbNavigation:getNodeChildren(node)
  if not node then return {} end

  if node.type == "scope" then
    -- Load scope variables
    if not self.parent.current_frame then return {} end

    local children = {}
    local variables = self.parent.current_frame:variables(node.variablesReference)
    if variables then
      for _, var in ipairs(variables) do
        table.insert(children, self.parent:createVariableNode(var, node.id))
      end
    end
    return children
  elseif node.type == "variable" and node.variableReference then
    -- Load variable children
    if not self.parent.current_frame then return {} end

    local children = {}
    local variables = self.parent.current_frame:variables(node.variableReference)
    if variables then
      for _, var in ipairs(variables) do
        table.insert(children, self.parent:createVariableNode(var, node.id))
      end
    end
    return children
  end

  return {}
end

-- Build parent context view (Variation 2: show parent + current + children)
function BreadcrumbNavigation:buildParentContextView(current_node)
  local nodes = {}

  -- If we're at root level (no path segments), show all root scopes
  if #self.current_path == 0 then
    return self.parent:getRootNodes()
  end

  -- For single path segment (e.g., just "Local"), show siblings + children
  if #self.current_path == 1 then
    return self:buildSingleLevelView(current_node)
  end

  -- Get parent node (one level up from current)
  local parent_path = vim.deepcopy(self.current_path)
  table.remove(parent_path) -- Remove last segment to get parent path

  local parent_node = self:findNodeByPathArray(parent_path)
  if parent_node then
    -- Create parent context header
    local parent_display = NuiTree.Node({
      id = "parent-context-" .. parent_node.id,
      name = "↑ " .. (parent_node.name or parent_node.text) .. " (parent)",
      text = "↑ " .. (parent_node.name or parent_node.text) .. " (parent)",
      type = "parent-context",
    }, {})
    table.insert(nodes, parent_display)

    -- Get all children of parent (siblings of current node)
    local parent_children = self:getNodeChildren(parent_node)
    for _, sibling in ipairs(parent_children) do
      local sibling_name = sibling.name or sibling.text or ""
      local current_name = current_node.name or current_node.text or ""

      if sibling_name == current_name then
        -- This is the current node - mark it and show its children
        local current_display = NuiTree.Node({
          id = "current-" .. current_node.id,
          name = "  └▾ " .. current_name .. " ← YOU ARE HERE",
          text = "  └▾ " .. current_name .. " ← YOU ARE HERE",
          type = "current-context",
        }, {})
        table.insert(nodes, current_display)

        -- Add children of current node with extra indentation
        local current_children = self:getNodeChildren(current_node)
        for _, child in ipairs(current_children) do
          -- Create indented child node
          local child_display = NuiTree.Node({
            id = "child-" .. child.id,
            name = "    " .. (child.name or child.text),
            text = "    " .. (child.name or child.text),
            type = child.type,
            variableReference = child.variableReference,
            variable = child.variable,
            is_expandable = child.is_expandable,
            loaded = child.loaded,
          }, child:has_children() and {} or nil)
          table.insert(nodes, child_display)
        end
      else
        -- This is a sibling - show it with lighter emphasis
        local sibling_display = NuiTree.Node({
          id = "sibling-" .. sibling.id,
          name = "  ├─ " .. sibling_name,
          text = "  ├─ " .. sibling_name,
          type = "sibling-context",
        }, {})
        table.insert(nodes, sibling_display)
      end
    end
  else
    -- Fallback: show current children only
    return self:getNodeChildren(current_node)
  end

  return nodes
end

-- Find node by following a specific path array
function BreadcrumbNavigation:findNodeByPathArray(path_array)
  if #path_array == 0 then return nil end

  -- Start with root scopes
  local current_nodes = self.parent:getRootNodes()
  local current_node = nil

  -- Follow each path segment
  for i, segment in ipairs(path_array) do
    current_node = self:findNodeByName(current_nodes, segment)
    if not current_node then
      return nil
    end

    -- Load children if needed for next iteration
    if i < #path_array then
      current_nodes = self:getNodeChildren(current_node)
    end
  end

  return current_node
end

-- Build single level view: show siblings + current + children
function BreadcrumbNavigation:buildSingleLevelView(current_node)
  local nodes = {}
  local current_name = current_node.name or current_node.text or ""

  -- Extract base name for scopes
  if current_node.type == "scope" then
    current_name = current_name:match("^(%w+)") or current_name
  end

  -- Get all siblings (root scopes for level 1)
  local siblings = self.parent:getRootNodes()

  -- Add siblings with current one highlighted
  for _, sibling in ipairs(siblings) do
    local sibling_name = sibling.name or sibling.text or ""
    if sibling.type == "scope" then
      sibling_name = sibling_name:match("^(%w+)") or sibling_name
    end

    if sibling_name == current_name then
      -- This is the current scope - mark it
      local current_display = NuiTree.Node({
        id = "current-" .. sibling.id,
        name = "▾ " .. (sibling.name or sibling.text) .. " ← YOU ARE HERE",
        text = "▾ " .. (sibling.name or sibling.text) .. " ← YOU ARE HERE",
        type = "current-scope",
      }, {})
      table.insert(nodes, current_display)

      -- Add children of current scope with indentation
      local children = self:getNodeChildren(current_node)
      for _, child in ipairs(children) do
        local child_display = NuiTree.Node({
          id = "child-" .. child.id,
          name = "  " .. (child.name or child.text),
          text = "  " .. (child.name or child.text),
          type = child.type,
          variableReference = child.variableReference,
          variable = child.variable,
          is_expandable = child.is_expandable,
          loaded = child.loaded,
        }, child:has_children() and {} or nil)
        table.insert(nodes, child_display)
      end
    else
      -- This is a sibling scope - show it collapsed
      local sibling_display = NuiTree.Node({
        id = "sibling-" .. sibling.id,
        name = "▸ " .. (sibling.name or sibling.text),
        text = "▸ " .. (sibling.name or sibling.text),
        type = "sibling-scope",
      }, {})
      table.insert(nodes, sibling_display)
    end
  end

  return nodes
end

-- Navigate up one level
function BreadcrumbNavigation:navigateUp()
  if #self.current_path > 0 then
    table.insert(self.navigation_history, vim.deepcopy(self.current_path))
    table.remove(self.current_path)
    self:refreshCurrentView()
  end
end

-- Navigate to a child node (PascalCase for async support)
function BreadcrumbNavigation:NavigateDown(childName)
  table.insert(self.navigation_history, vim.deepcopy(self.current_path))
  table.insert(self.current_path, childName)
  self:RefreshCurrentView()
end

-- Go back to previous location
function BreadcrumbNavigation:navigateBack()
  if #self.navigation_history > 0 then
    self.current_path = table.remove(self.navigation_history)
    self:refreshCurrentView()
  end
end

-- Navigate to root
function BreadcrumbNavigation:navigateToRoot()
  if #self.current_path > 0 then
    table.insert(self.navigation_history, vim.deepcopy(self.current_path))
    self.current_path = {}
    self:refreshCurrentView()
  end
end

-- Jump to specific breadcrumb segment
function BreadcrumbNavigation:jumpToSegment(index)
  if index > 0 and index <= #self.current_path then
    table.insert(self.navigation_history, vim.deepcopy(self.current_path))
    -- Truncate path to the selected segment
    local new_path = {}
    for i = 1, index do
      table.insert(new_path, self.current_path[i])
    end
    self.current_path = new_path
    self:refreshCurrentView()
  end
end

-- Refresh the current view only (PascalCase for async support)
function BreadcrumbNavigation:RefreshCurrentView()
  local tabpage = vim.api.nvim_get_current_tabpage()
  self:RefreshView(tabpage)
end

-- Create breadcrumb split window
function BreadcrumbNavigation:createBreadcrumbSplit(tabpage)
  local main_win = self.parent.windows[tabpage]
  if not main_win or not vim.api.nvim_win_is_valid(main_win.split.winid) then
    return nil
  end

  -- Get main window absolute position
  local main_win_pos = vim.api.nvim_win_get_position(main_win.split.winid)
  local main_win_width = vim.api.nvim_win_get_width(main_win.split.winid)

  -- Create a split positioned above the Variables window
  local breadcrumb_split = NuiSplit({
    relative = "editor",
    position = {
      row = main_win_pos[1] - 2, -- Position 2 lines above main window
      col = main_win_pos[2],
    },
    size = {
      width = main_win_width,
      height = 2, -- Height of 2 lines for breadcrumb and separator
    },
    buf_options = {
      buftype = "nofile",
      bufhidden = "hide",
      swapfile = false,
      modifiable = false,
      filetype = "neodap-breadcrumb",
    },
    win_options = {
      wrap = false,
      cursorline = false,
      number = false,
      relativenumber = false,
      signcolumn = "no",
      foldcolumn = "0",
      colorcolumn = "",
    },
  })

  breadcrumb_split:mount()

  -- Store reference
  self.breadcrumb_splits[tabpage] = { split = breadcrumb_split }

  return breadcrumb_split
end

-- Update breadcrumb split content
function BreadcrumbNavigation:updateBreadcrumbSplit(tabpage)
  local breadcrumb_win = self.breadcrumb_splits[tabpage]
  if not breadcrumb_win or not vim.api.nvim_win_is_valid(breadcrumb_win.split.winid) then
    -- Create new split window if needed
    local split = self:createBreadcrumbSplit(tabpage)
    if not split then return end
    breadcrumb_win = self.breadcrumb_splits[tabpage]
  end

  -- Update breadcrumb content
  local breadcrumb_text = self:createBreadcrumbText()
  local separator_text = string.rep("─", vim.api.nvim_win_get_width(breadcrumb_win.split.winid))

  vim.notify("Split breadcrumb text: " .. breadcrumb_text, vim.log.levels.INFO)

  -- Set content in split window
  vim.api.nvim_buf_set_option(breadcrumb_win.split.bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_lines(breadcrumb_win.split.bufnr, 0, -1, false, {
    breadcrumb_text,
    separator_text
  })
  vim.api.nvim_buf_set_option(breadcrumb_win.split.bufnr, 'modifiable', false)
end

-- Refresh the view for a specific tabpage (PascalCase for async support)
function BreadcrumbNavigation:RefreshView(tabpage)
  local win = self.parent.windows[tabpage]
  if not win or not vim.api.nvim_win_is_valid(win.split.winid) then
    return
  end

  -- Create breadcrumb content
  local breadcrumb_text = self:createBreadcrumbText()
  local separator_text = string.rep("─", 60)

  -- Clear buffer and add breadcrumb lines
  vim.api.nvim_buf_set_option(win.split.bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_lines(win.split.bufnr, 0, -1, false, {
    breadcrumb_text,
    separator_text
  })
  vim.api.nvim_buf_set_option(win.split.bufnr, 'modifiable', false)

  -- Create filtered tree
  local filtered_nodes = self:getFilteredNodes()

  win.tree = NuiTree({
    bufnr = win.split.bufnr,
    nodes = filtered_nodes,
    get_node_id = function(node) return node.id end,
    prepare_node = function(node)
      return self:prepareNodeLine(node)
    end,
  })

  -- Render tree starting at line 3 (after breadcrumb + separator)
  -- This tells NUI Tree exactly where to start rendering
  win.tree:render(3)

  -- Update keybindings for current tree
  self:setupKeybindings(win.split, win.tree)
end

-- Simple line rendering (without full NuiLine complexity)
function BreadcrumbNavigation:renderLine(line)
  -- Extract text content from NuiLine segments
  local text = ""
  if line._segments then
    for _, segment in ipairs(line._segments) do
      if segment.text then
        text = text .. segment.text
      end
    end
  end
  return text
end

-- Enhanced node rendering for breadcrumb mode
function BreadcrumbNavigation:prepareNodeLine(node)
  -- Simply delegate to VisualImprovements with breadcrumb-specific options
  return VisualImprovements.prepareNodeLine(node, {
    useTreeGuides = false -- Disable tree guides in breadcrumb mode
  })
end

-- Toggle node with navigation behavior
function BreadcrumbNavigation:toggleNode(tree)
  local node = tree:get_node()
  if not node then
    vim.notify("BreadcrumbNav: toggleNode - no node selected!", vim.log.levels.WARN)
    return
  end

  local raw_name = node.name or node.text or ""
  local node_type = node.type or "unknown"

  vim.notify("BreadcrumbNav: toggleNode called - raw_name: '" .. raw_name .. "', type: " .. node_type,
    vim.log.levels.INFO)

  -- Handle different node types in parent context view
  if node_type == "parent-context" then
    -- Clicking parent goes up one level
    vim.notify("BreadcrumbNav: Clicked parent context, navigating up", vim.log.levels.INFO)
    self:navigateUp()
    return
  elseif node_type == "sibling-context" then
    -- Clicking sibling navigates to that sibling
    local sibling_name = raw_name:match("├─ (.+)") or raw_name
    vim.notify("BreadcrumbNav: Clicked sibling context, navigating to: " .. sibling_name, vim.log.levels.INFO)
    -- Go up one level first, then navigate to sibling
    self:navigateUp()
    self:NavigateDown(sibling_name)
    return
  elseif node_type == "current-context" or node_type == "current-scope" then
    -- Clicking "YOU ARE HERE" does nothing (already there)
    vim.notify("BreadcrumbNav: Clicked current context marker (no action)", vim.log.levels.INFO)
    return
  elseif node_type == "sibling-scope" then
    -- Clicking sibling scope navigates to that scope
    local scope_name = raw_name:match("▸ (.+)") or raw_name
    vim.notify("BreadcrumbNav: Clicked sibling scope, navigating to: " .. scope_name, vim.log.levels.INFO)
    -- Reset to root first, then navigate to sibling
    self.current_path = {}
    local base_name = scope_name:match("^(%w+)") or scope_name
    self:NavigateDown(base_name)
    return
  end

  -- For actual content nodes (children), handle normal navigation
  local navigation_name = raw_name

  -- Clean up the name for navigation (remove indentation and prefixes)
  navigation_name = navigation_name:gsub("^%s*", "") -- Remove leading whitespace

  -- For scope nodes, extract base name (e.g., "Local: testFunction" -> "Local")
  if node.type == "scope" then
    navigation_name = navigation_name:match("^(%w+)") or navigation_name
  end

  -- Check if this is a navigable node
  if node.type == "scope" or node.is_expandable or node.variableReference then
    -- Navigate down into expandable nodes (scopes, variables with children)
    vim.notify("BreadcrumbNav: Navigating down into: " .. navigation_name, vim.log.levels.INFO)
    self:NavigateDown(navigation_name)
  elseif node:is_expanded() then
    -- Collapse if already expanded
    vim.notify("BreadcrumbNav: Node is expanded, collapsing", vim.log.levels.INFO)
    node:collapse()
    tree:render()
  else
    -- For non-expandable nodes, just expand to show any metadata
    vim.notify("BreadcrumbNav: Expanding non-navigable node", vim.log.levels.INFO)
    node:expand()
    tree:render()
  end
end

-- Clean up breadcrumb splits
function BreadcrumbNavigation:cleanup()
  for tabpage, breadcrumb_win in pairs(self.breadcrumb_splits) do
    if breadcrumb_win.split and vim.api.nvim_win_is_valid(breadcrumb_win.split.winid) then
      breadcrumb_win.split:unmount()
    end
  end
  self.breadcrumb_splits = {}
end

-- Close breadcrumb split for specific tabpage
function BreadcrumbNavigation:closeBreadcrumbSplit(tabpage)
  local breadcrumb_win = self.breadcrumb_splits[tabpage]
  if breadcrumb_win and breadcrumb_win.split then
    if vim.api.nvim_win_is_valid(breadcrumb_win.split.winid) then
      breadcrumb_win.split:unmount()
    end
    self.breadcrumb_splits[tabpage] = nil
  end
end

-- Setup breadcrumb-specific keybindings
function BreadcrumbNavigation:setupKeybindings(split, tree)
  local map = function(key, fn, desc)
    vim.keymap.set("n", key, fn, {
      buffer = split.bufnr,
      nowait = true,
      silent = true,
      desc = desc or ""
    })
  end

  -- Navigation
  map("<CR>", function()
    vim.notify("BreadcrumbNav: <CR> keybinding triggered!", vim.log.levels.INFO)
    self:toggleNode(tree)
  end, "Navigate into node")
  map("o", function()
    vim.notify("BreadcrumbNav: 'o' keybinding triggered!", vim.log.levels.INFO)
    self:toggleNode(tree)
  end, "Navigate into node")

  -- Breadcrumb navigation
  map("u", function() self:navigateUp() end, "Go up one level")
  map("<BS>", function() self:navigateUp() end, "Go up one level")
  map("b", function() self:navigateBack() end, "Go back to previous location")
  map("r", function() self:navigateToRoot() end, "Go to root")

  -- Quick jump to breadcrumb segments
  for i = 1, 9 do
    map(tostring(i), function()
      self:jumpToSegment(i)
    end, "Jump to breadcrumb segment " .. i)
  end

  -- Search within current level
  map("/", function()
    vim.cmd("normal! /")
  end, "Search current level")
end

return BreadcrumbNavigation
