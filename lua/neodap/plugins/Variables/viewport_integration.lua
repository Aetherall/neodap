-- Viewport Integration for Variables Plugin
-- Experimental integration that adds viewport capabilities to existing system
-- Allows testing viewport system alongside current dual-mode architecture

local Class = require('neodap.tools.class')
local NuiSplit = require("nui.split")
local NuiTree = require("nui.tree")
local ViewportSystem = require('neodap.plugins.Variables.viewport_system')
local ViewportRenderer = require('neodap.plugins.Variables.viewport_renderer')
local VisualImprovements = require('neodap.plugins.Variables.visual_improvements')

---@class ViewportIntegrationProps
---@field base_plugin VariablesTreeNui Reference to existing plugin
---@field viewport Viewport Current viewport state
---@field enabled boolean Whether viewport mode is active
---@field complete_tree table[] Complete tree structure for viewport system

---@class ViewportIntegration: ViewportIntegrationProps
---@field new Constructor<ViewportIntegrationProps>
local ViewportIntegration = Class()

---@param base_plugin VariablesTreeNui
---@return ViewportIntegration
function ViewportIntegration.create(base_plugin)
  local instance = ViewportIntegration:new({
    base_plugin = base_plugin,
    viewport = ViewportSystem.createViewport(),
    enabled = false,
    complete_tree = nil
  })

  instance:init()
  return instance
end

function ViewportIntegration:init()
  -- Initialize viewport system
  self:BuildCompleteTree()

  -- Add viewport-specific commands
  self:SetupViewportCommands()
end

-- ================================
-- COMPLETE TREE BUILDING
-- ================================

---Build complete tree structure from current debug frame
---This replaces the need for separate tree construction methods
function ViewportIntegration:BuildCompleteTree()
  if not self.base_plugin.current_frame then
    self.complete_tree = {}
    return
  end

  local tree = {}
  local scopes = self.base_plugin.current_frame:scopes()

  if scopes then
    for _, scope in ipairs(scopes) do
      local scope_node = self:CreateCompleteTreeNode(scope.ref, nil, "scope")
      table.insert(tree, scope_node)
    end
  end

  self.complete_tree = tree
end

---Create a complete tree node with all children loaded
---@param data_ref table DAP variable or scope reference
---@param parent_id? string Parent node ID
---@param node_type string "scope" or "variable"
---@return table Complete tree node
function ViewportIntegration:CreateCompleteTreeNode(data_ref, parent_id, node_type)
  local node_id
  if node_type == "scope" then
    local IdGenerator = require('neodap.plugins.Variables.id_generator')
    node_id = IdGenerator.forScope(data_ref)
  else
    local IdGenerator = require('neodap.plugins.Variables.id_generator')
    node_id = IdGenerator.forVariable(parent_id, data_ref)
  end

  local node = {
    id = node_id,
    name = data_ref.name,
    type = node_type,
    dap_data = data_ref,
    children = {},
    loaded = false
  }

  -- Add variable-specific properties
  if node_type == "variable" then
    node.variable = data_ref
    node.varType = data_ref.type
    node.is_expandable = data_ref.variablesReference and data_ref.variablesReference > 0
    node.variableReference = data_ref.variablesReference
  else
    node.variableReference = data_ref.variablesReference
    node.expensive = data_ref.expensive
  end

  -- Load children if expandable
  if data_ref.variablesReference and data_ref.variablesReference > 0 then
    self:LoadCompleteTreeChildren(node)
  end

  return node
end

---Load all children for a node in the complete tree
---@param node table Node to load children for
function ViewportIntegration:LoadCompleteTreeChildren(node)
  if not self.base_plugin.current_frame or node.loaded then
    return
  end

  local variables = self.base_plugin.current_frame:variables(node.variableReference)
  if variables then
    for _, var in ipairs(variables) do
      local child_node = self:CreateCompleteTreeNode(var, node.id, "variable")
      table.insert(node.children, child_node)
    end
  end

  node.loaded = true
end

-- ================================
-- VIEWPORT-BASED RENDERING
-- ================================

---Render tree using viewport system
---@param tabpage number Tabpage to render for
function ViewportIntegration:RenderWithViewport(tabpage)
  local win = self.base_plugin.windows[tabpage]
  if not win or not vim.api.nvim_win_is_valid(win.split.winid) then
    return
  end

  -- Ensure complete tree is up to date
  self:BuildCompleteTree()

  -- Render tree at current viewport
  local rendered_nodes = ViewportRenderer.RenderTreeAtViewport(self.complete_tree, self.viewport)

  -- Apply viewport style
  rendered_nodes = ViewportRenderer.applyViewportStyle(rendered_nodes, self.viewport)

  -- Sort nodes for display
  local sorted_nodes = ViewportRenderer.sortNodesForDisplay(rendered_nodes)

  -- Create breadcrumb header
  local header_lines = ViewportRenderer.createBreadcrumbHeader(
    self.viewport,
    vim.api.nvim_win_get_width(win.split.winid)
  )

  -- Convert to NUI Tree nodes
  local nui_nodes = self:convertToNuiNodes(sorted_nodes)

  -- Update buffer content with header
  vim.api.nvim_buf_set_option(win.split.bufnr, 'modifiable', true)

  -- Add header lines
  local header_text = {}
  for _, header in ipairs(header_lines) do
    table.insert(header_text, header.text)
  end
  vim.api.nvim_buf_set_lines(win.split.bufnr, 0, -1, false, header_text)

  vim.api.nvim_buf_set_option(win.split.bufnr, 'modifiable', false)

  -- Create and render NUI Tree starting after header
  win.tree = NuiTree({
    bufnr = win.split.bufnr,
    nodes = nui_nodes,
    get_node_id = function(node) return node.id end,
    prepare_node = function(node)
      if node.viewport_geometry then
        return ViewportRenderer.prepareNodeLineWithGeometry(
          node,
          node.viewport_geometry,
          self.viewport
        )
      else
        return VisualImprovements.prepareNodeLine(node)
      end
    end,
  })

  -- Render starting after header lines
  win.tree:render(#header_lines + 1)

  -- Setup viewport-specific keybindings
  self:setupViewportKeybindings(win.split, win.tree)
end

---Convert rendered nodes to NUI Tree nodes
---@param sorted_nodes table[] Sorted nodes from renderer
---@return table[] NUI Tree nodes
function ViewportIntegration:convertToNuiNodes(sorted_nodes)
  local nui_nodes = {}

  for _, node_data in ipairs(sorted_nodes) do
    local node = node_data.node
    local nui_node = NuiTree.Node({
      id = node.id,
      name = node.name,
      text = node_data.display,
      type = node.type,
      variableReference = node.variableReference,
      variable = node.variable,
      dap_data = node.dap_data,
      is_expandable = node.is_expandable or false,
      loaded = node.loaded or false,
      viewport_geometry = node_data.geometry, -- Store geometry for rendering
      viewport_path = node_data.path,         -- Store path for navigation
    }, node.children and #node.children > 0 and {} or nil)

    table.insert(nui_nodes, nui_node)
  end

  return nui_nodes
end

-- ================================
-- VIEWPORT NAVIGATION
-- ================================

---Navigate using viewport system
---@param action string Navigation action
---@param current_node? table Currently selected node
function ViewportIntegration:NavigateViewport(action, current_node)
  local old_focus = vim.deepcopy(self.viewport.focus_path)

  if action == "enter" and current_node then
    -- Navigate deeper using viewport path
    if current_node.viewport_path then
      -- Store history
      table.insert(self.viewport.history, vim.deepcopy(self.viewport.focus_path))
      self.viewport.focus_path = vim.deepcopy(current_node.viewport_path)
    end
  elseif action == "up" then
    -- Go up one level
    if #self.viewport.focus_path > 0 then
      table.insert(self.viewport.history, vim.deepcopy(self.viewport.focus_path))
      self.viewport.focus_path = ViewportSystem.shortenPath(self.viewport.focus_path)
    end
  elseif action == "back" then
    -- Navigate back in history
    self.viewport = ViewportSystem.navigateBack(self.viewport)
  elseif action == "root" then
    -- Go to root
    self.viewport = ViewportSystem.resetToRoot(self.viewport)
  end

  -- Refresh view if focus changed
  if not ViewportSystem.arePathsEqual(old_focus, self.viewport.focus_path) then
    self:RefreshViewportForAllWindows()
  end
end

---Refresh viewport rendering for all windows
function ViewportIntegration:RefreshViewportForAllWindows()
  for tabpage, _ in pairs(self.base_plugin.windows) do
    if vim.api.nvim_tabpage_is_valid(tabpage) then
      self:RenderWithViewport(tabpage)
    end
  end
end

-- ================================
-- KEYBINDING SETUP
-- ================================

---Setup viewport-specific keybindings
---@param split NuiSplit Window split
---@param tree NuiTree Tree instance
function ViewportIntegration:setupViewportKeybindings(split, tree)
  local map = function(key, fn, desc)
    vim.keymap.set("n", key, fn, {
      buffer = split.bufnr,
      nowait = true,
      silent = true,
      desc = desc or ""
    })
  end

  -- Viewport navigation
  map("<CR>", function()
    local node = tree:get_node()
    self:NavigateViewport("enter", node)
  end, "Navigate into node")

  map("o", function()
    local node = tree:get_node()
    self:NavigateViewport("enter", node)
  end, "Navigate into node")

  map("u", function()
    self:NavigateViewport("up")
  end, "Go up one level")

  map("<BS>", function()
    self:NavigateViewport("up")
  end, "Go up one level")

  map("b", function()
    self:NavigateViewport("back")
  end, "Go back in history")

  map("r", function()
    self:NavigateViewport("root")
  end, "Go to root")

  -- Viewport controls
  map("+", function()
    self.viewport.radius = math.min(self.viewport.radius + 1, 5)
    self:RefreshViewportForAllWindows()
  end, "Increase viewport radius")

  map("-", function()
    self.viewport.radius = math.max(self.viewport.radius - 1, 1)
    self:RefreshViewportForAllWindows()
  end, "Decrease viewport radius")

  map("s", function()
    local styles = { "contextual", "minimal", "full", "highlight" }
    local current_index = 1
    for i, style in ipairs(styles) do
      if style == self.viewport.style then
        current_index = i
        break
      end
    end
    local next_index = (current_index % #styles) + 1
    self.viewport.style = styles[next_index]
    vim.notify("Viewport style: " .. self.viewport.style, vim.log.levels.INFO)
    self:RefreshViewportForAllWindows()
  end, "Cycle viewport style")

  -- Common keybindings
  map("q", function()
    self.base_plugin:Close()
  end, "Close variables")

  map("V", function()
    self:ToggleViewportMode()
  end, "Toggle viewport mode")
end

-- ================================
-- MODE MANAGEMENT
-- ================================

---Toggle viewport mode on/off
function ViewportIntegration:ToggleViewportMode()
  self.enabled = not self.enabled

  if self.enabled then
    vim.notify("Viewport mode: ON", vim.log.levels.INFO)
    self:RefreshViewportForAllWindows()
  else
    vim.notify("Viewport mode: OFF", vim.log.levels.INFO)
    self.base_plugin:RefreshAllWindows()
  end
end

---Check if viewport mode should be used for rendering
---@param tabpage number
---@return boolean
function ViewportIntegration:shouldUseViewport(tabpage)
  return self.enabled and self.complete_tree and #self.complete_tree > 0
end

-- ================================
-- COMMAND SETUP
-- ================================

---Setup additional commands for viewport system
function ViewportIntegration:SetupViewportCommands()
  vim.api.nvim_create_user_command("VariablesViewport", function(opts)
    local cmd = opts.args or "toggle"

    if cmd == "toggle" then
      self:ToggleViewportMode()
    elseif cmd == "enable" then
      self.enabled = true
      self:RefreshViewportForAllWindows()
    elseif cmd == "disable" then
      self.enabled = false
      self.base_plugin:RefreshAllWindows()
    elseif cmd == "reset" then
      self.viewport = ViewportSystem.resetToRoot(self.viewport)
      self:RefreshViewportForAllWindows()
    elseif cmd == "rebuild" then
      self:BuildCompleteTree()
      self:RefreshViewportForAllWindows()
    end
  end, {
    desc = "Control viewport mode",
    nargs = "?",
    complete = function()
      return { "toggle", "enable", "disable", "reset", "rebuild" }
    end
  })
end

return ViewportIntegration
