-- Variables Plugin with Viewport-Based Architecture
-- Revolutionary tree navigation using geometric viewport concepts

local Class = require('neodap.tools.class')
local NuiSplit = require("nui.split")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local Logger = require('neodap.tools.logger')
-- IdGenerator no longer needed with API object approach
local VisualImprovements = require('neodap.plugins.Variables.visual_improvements')
local ViewportSystem = require('neodap.plugins.Variables.viewport_system')
local ViewportRenderer = require('neodap.plugins.Variables.viewport_renderer')
local TreeNodeTrait = require('neodap.plugins.Variables.tree_node_trait')

---@class VariablesTreeNuiProps
---@field api Api
---@field current_frame? Frame
---@field windows table<number, {split: NuiSplit, tree: NuiTree}>
---@field viewport Viewport Current viewport state
---@field tree_states table<string, table> UI states for tree nodes indexed by ID
---@field logger Logger Logger instance

---@class VariablesTreeNui: VariablesTreeNuiProps
---@field new Constructor<VariablesTreeNuiProps>
local VariablesTreeNui = Class()

VariablesTreeNui.name = "Variables"

---@param api Api
---@return VariablesTreeNui
function VariablesTreeNui.create(api)
  local instance = VariablesTreeNui:new({
    api = api,
    current_frame = nil,
    windows = {},
    logger = Logger.get("VariablesTreeNui"),
    viewport = ViewportSystem.createViewport(),
    tree_states = {} -- UI states for tree nodes
  })

  instance:init()
  return instance
end

function VariablesTreeNui.plugin(api)
  return VariablesTreeNui.create(api)
end

function VariablesTreeNui:init()
  -- Extend neodap API classes with tree capabilities
  self:extendApiClasses()
  
  -- Setup DAP event handlers
  self:setupEventHandlers()

  -- Create user commands
  self:setupCommands()
end

-- ================================
-- API CLASS EXTENSIONS
-- ================================

function VariablesTreeNui:extendApiClasses()
  -- Only extend once globally
  if _G._neodap_variables_tree_extended then
    return
  end
  _G._neodap_variables_tree_extended = true
  
  print("[DEBUG] Extending API classes...")
  
  -- Get API classes
  local Variable = require('neodap.api.Session.Variable')
  local BaseScope = require('neodap.api.Session.Scope.BaseScope')
  local Frame = require('neodap.api.Session.Frame')
  
  -- Also extend specific scope types that inherit from BaseScope
  local LocalsScope = require('neodap.api.Session.Scope.LocalsScope')
  local GlobalsScope = require('neodap.api.Session.Scope.GlobalsScope')
  local ArgumentsScope = require('neodap.api.Session.Scope.ArgumentsScope')
  local RegistersScope = require('neodap.api.Session.Scope.RegistersScope')
  
  -- Apply TreeNodeTrait to all classes
  TreeNodeTrait.extend(Variable)
  TreeNodeTrait.extend(BaseScope)
  TreeNodeTrait.extend(Frame)
  
  -- Also extend specific scope types
  TreeNodeTrait.extend(LocalsScope)
  TreeNodeTrait.extend(GlobalsScope)
  TreeNodeTrait.extend(ArgumentsScope)
  TreeNodeTrait.extend(RegistersScope)
  
  -- Variable specific implementations
  function Variable:getTreeNodeId()
    -- Use parent scope's reference + variable name for uniqueness
    if self.scope and self.scope.ref then
      return string.format("var:%d:%s", 
        self.scope.ref.variablesReference,
        self.ref.name)
    end
    return string.format("var:0:%s", self.ref.name)
  end
  
  function Variable:getTreeNodeChildren()
    if self.ref.variablesReference and self.ref.variablesReference > 0 then
      -- Get frame from scope
      local frame = self.scope and self.scope.frame
      if frame then
        local children = frame:variables(self.ref.variablesReference)
        -- Convert to Variable instances
        local var_children = {}
        for _, child_ref in ipairs(children or {}) do
          table.insert(var_children, Variable:instanciate(self.scope, child_ref))
        end
        return var_children
      end
    end
    return nil
  end
  
  -- Debug helper
  function Variable:__tostring()
    return string.format("Variable<%s=%s>", self.ref.name, self.ref.value or self.ref.type or "?")
  end
  
  function Variable:isTreeNodeExpandable()
    return self.ref.variablesReference and self.ref.variablesReference > 0
  end
  
  function Variable:formatTreeNodeDisplay()
    return VisualImprovements.formatVariableDisplay(self.ref)
  end
  
  function Variable:getTreeNodePath()
    -- Build path from variable name and parent scope
    local path = {}
    if self.scope and self.scope.ref then
      table.insert(path, self.scope.ref.name)
    end
    table.insert(path, self.ref.name)
    return path
  end
  
  -- Scope specific implementations
  function BaseScope:getTreeNodeId()
    return string.format("scope:%s", self.ref.name)
  end
  
  function BaseScope:getTreeNodeChildren()
    -- Don't implement here - let the fallback in getNodeChildren handle it
    -- since it needs to be in the proper async context
    return nil
  end
  
  -- Debug helper
  function BaseScope:__tostring()
    return string.format("Scope<%s>", self.ref.name)
  end
  
  -- Apply same methods to specific scope types
  for _, ScopeClass in ipairs({LocalsScope, GlobalsScope, ArgumentsScope, RegistersScope}) do
    ScopeClass.getTreeNodeId = BaseScope.getTreeNodeId
    ScopeClass.getTreeNodeChildren = BaseScope.getTreeNodeChildren
    -- Override isTreeNodeExpandable to always return true for scopes
    ScopeClass.isTreeNodeExpandable = function(self)
      return true  -- Scopes are always expandable
    end
    ScopeClass.formatTreeNodeDisplay = BaseScope.formatTreeNodeDisplay
    ScopeClass.getTreeNodePath = BaseScope.getTreeNodePath
    ScopeClass.__tostring = BaseScope.__tostring
    -- Don't override variables method as it already exists
  end
  
  function BaseScope:isTreeNodeExpandable()
    print("[DEBUG] BaseScope:isTreeNodeExpandable called for " .. tostring(self))
    return true -- Scopes are always expandable
  end
  
  function BaseScope:formatTreeNodeDisplay()
    return self.ref.name
  end
  
  function BaseScope:getTreeNodePath()
    return { self.ref.name }
  end
  
  -- Add metatable enhancements for lazy properties
  self:enhanceWithMetatables(Variable, BaseScope)
end

function VariablesTreeNui:enhanceWithMetatables(Variable, BaseScope)
  -- Add lazy properties to Variable
  local var_mt = getmetatable(Variable)
  local original_var_index = var_mt.__index or Variable
  
  var_mt.__index = function(self, key)
    -- Check original first
    local value
    if type(original_var_index) == "function" then
      value = original_var_index(self, key)
    else
      value = original_var_index[key]
    end
    
    if value ~= nil then return value end
    
    -- Add lazy properties
    if key == "tree_path" then
      return self:getTreeNodePath()
    elseif key == "is_expandable" then
      return self:isTreeNodeExpandable()
    elseif key == "display_text" then
      return self:formatTreeNodeDisplay()
    end
    
    return nil
  end
  
  -- Similar for BaseScope
  local scope_mt = getmetatable(BaseScope)
  local original_scope_index = scope_mt.__index or BaseScope
  
  scope_mt.__index = function(self, key)
    local value
    if type(original_scope_index) == "function" then
      value = original_scope_index(self, key)
    else
      value = original_scope_index[key]
    end
    
    if value ~= nil then return value end
    
    if key == "tree_path" then
      return self:getTreeNodePath()
    elseif key == "is_expandable" then
      return true
    elseif key == "display_text" then
      return self:formatTreeNodeDisplay()
    end
    
    return nil
  end
end

function VariablesTreeNui:setupEventHandlers()
  self.api:onSession(function(session)
    session:onThread(function(thread)
      thread:onStopped(function()
        local stack = thread:stack()
        self.current_frame = stack and stack:top() or nil
        -- Clear UI states on new frame
        self.tree_states = {}
        self:RefreshAllWindows()
      end)

      thread:onContinued(function()
        self.current_frame = nil
        self.tree_states = {}
        self:RefreshAllWindows()
      end)
    end)
  end)
end

function VariablesTreeNui:setupCommands()
  vim.api.nvim_create_user_command("VariablesShow", function()
    self:Show()
  end, { desc = "Show variables window" })

  vim.api.nvim_create_user_command("VariablesClose", function()
    self:Close()
  end, { desc = "Close variables window" })

  vim.api.nvim_create_user_command("VariablesToggle", function()
    self:Toggle()
  end, { desc = "Toggle variables window" })

  -- Viewport control commands
  vim.api.nvim_create_user_command("VariablesViewport", function(opts)
    local cmd = opts.args or "status"

    if cmd == "reset" then
      self.viewport = ViewportSystem.resetToRoot(self.viewport)
      self:RefreshAllWindows()
    elseif cmd == "clear-states" then
      self.tree_states = {}
      self:RefreshAllWindows()
    elseif cmd == "status" then
      local path = table.concat(self.viewport.focus_path, " → ")
      local state_count = vim.tbl_count(self.tree_states)
      vim.notify("Viewport: " .. (path ~= "" and path or "root") ..
        " | Radius: " .. self.viewport.radius ..
        " | Style: " .. self.viewport.style ..
        " | Node states: " .. state_count, vim.log.levels.INFO)
    end
  end, {
    desc = "Control viewport",
    nargs = "?",
    complete = function()
      return { "reset", "clear-states", "status" }
    end
  })
end

-- ================================
-- TREE BUILDING WITH API OBJECTS
-- ================================

---Get node at a specific path using API objects
---@param path string[] Path segments
---@return table? API object (Scope or Variable) at path
function VariablesTreeNui:GetNodeAtPath(path)
  if not self.current_frame or #path == 0 then
    return nil
  end
  
  -- Start with scopes
  local scopes = self.current_frame:scopes()
  if not scopes then return nil end
  
  -- Find matching scope
  local current_node = nil
  for _, scope in ipairs(scopes) do
    if scope.ref.name == path[1] then
      current_node = scope
      break
    end
  end
  
  if not current_node then return nil end
  
  -- Navigate deeper if needed
  for i = 2, #path do
    local children = current_node:getTreeNodeChildren()
    if not children then return nil end
    
    local found = false
    for _, child in ipairs(children) do
      if child.ref.name == path[i] then
        current_node = child
        found = true
        break
      end
    end
    
    if not found then return nil end
  end
  
  return current_node
end

---Ensure children are loaded for a node
---@param api_object table API object (Scope or Variable)
function VariablesTreeNui:EnsureChildrenLoaded(api_object)
  local state = self:getNodeState(api_object)
  
  if not state.children_loaded and self:isNodeExpandable(api_object) then
    -- Mark as loading to prevent duplicate requests
    state.children_loaded = true
    
    -- Load children asynchronously
    self:LoadChildrenAsync(api_object, function(children)
      print("[DEBUG] LoadChildrenAsync callback: got " .. tostring(children and #children or "nil") .. " children")
      if children then
        state.cached_children = children
        -- Refresh to show the newly loaded children
        vim.schedule(function()
          print("[DEBUG] Refreshing windows after loading children")
          self:RefreshAllWindows()
        end)
      end
    end)
  end
end

-- ================================
-- VIEWPORT-BASED RENDERING
-- ================================

---Build tree structure for current viewport using API objects
---@return table[] Scopes with loaded children based on viewport
function VariablesTreeNui:BuildViewportTree()  -- PascalCase for async
  if not self.current_frame then
    self.logger:debug("BuildViewportTree: No current frame")
    return {}
  end

  print("[DEBUG] BuildViewportTree: Starting with focus_path = " .. vim.inspect(self.viewport.focus_path))

  -- Get scopes from frame (cached by neodap)
  local scopes = self.current_frame:scopes()
  if not scopes then
    self.logger:debug("BuildViewportTree: No scopes found")
    return {}
  end

  print("[DEBUG] BuildViewportTree: Found " .. #scopes .. " scopes")
  
  -- Build tree structure from API objects
  local tree_nodes = {}
  
  for _, scope in ipairs(scopes) do
    -- Check if scope should be visible based on viewport
    local scope_path = self:getScopePath(scope)
    local geometry = ViewportSystem.calculateNodeGeometry(scope_path, self.viewport.focus_path)
    
    if ViewportSystem.shouldShowNode(geometry, self.viewport) then
      -- Get UI state
      local state = self:getNodeState(scope)
      
      -- Mark as visible
      state.visible = true
      state.geometry = geometry
      
      -- Build tree node structure
      local node = {
        api_object = scope,
        children = nil,
        geometry = geometry,
        path = scope_path
      }
      
      -- Load children if expanded
      print("[DEBUG] BuildViewportTree: Checking scope " .. scope.ref.name .. ", state.expanded=" .. tostring(state.expanded))
      if state.expanded then
        self.logger:debug("BuildViewportTree: Scope " .. scope.ref.name .. " is expanded, loading children...")
        node.children = self:BuildChildrenForNode(scope, scope_path)
        self.logger:debug("BuildViewportTree: Loading children for expanded scope " .. scope.ref.name .. 
          ", got " .. tostring(node.children and #node.children or 0) .. " children")
      else
        self.logger:debug("BuildViewportTree: Scope " .. scope.ref.name .. " is NOT expanded")
      end
      
      table.insert(tree_nodes, node)
    end
  end
  
  return tree_nodes
end

---Build children for a node recursively
---@param parent table API object (Scope or Variable)
---@param parent_path string[] Path to parent
---@return table[]? Child nodes
function VariablesTreeNui:BuildChildrenForNode(parent, parent_path)  -- PascalCase for async
  self.logger:debug("BuildChildrenForNode: parent=" .. tostring(parent) .. ", parent_path=" .. vim.inspect(parent_path))
  local children = self:getNodeChildren(parent)
  self.logger:debug("BuildChildrenForNode: got " .. tostring(children and #children or "nil") .. " children")
  if not children or #children == 0 then
    return nil
  end
  
  local child_nodes = {}
  
  for _, child in ipairs(children) do
    -- Build child path
    local child_path = vim.deepcopy(parent_path)
    table.insert(child_path, child.ref.name)
    
    -- Calculate geometry
    local geometry = ViewportSystem.calculateNodeGeometry(child_path, self.viewport.focus_path)
    
    -- Check visibility
    if ViewportSystem.shouldShowNode(geometry, self.viewport) then
      local state = self:getNodeState(child)
      
      -- Mark as visible
      state.visible = true
      state.geometry = geometry
      
      local node = {
        api_object = child,
        children = nil,
        geometry = geometry,
        path = child_path
      }
      
      -- Recursively load children if expanded
      if state.expanded then
        node.children = self:BuildChildrenForNode(child, child_path)
        self.logger:debug("BuildChildrenForNode: Loading children for expanded node " .. child.ref.name)
      end
      
      table.insert(child_nodes, node)
    end
  end
  
  return #child_nodes > 0 and child_nodes or nil
end

-- ================================
-- HELPER METHODS FOR API OBJECTS
-- ================================

---Get node ID for any API object
---@param node table Scope or Variable
---@return string
function VariablesTreeNui:getNodeId(node)
  if node.getTreeNodeId then
    return node:getTreeNodeId()
  end
  
  -- Fallback logic
  if node.type and node.type == "scope" then
    return string.format("scope:%s", node.ref.name)
  elseif node.scope then
    return string.format("var:%d:%s", 
      node.scope.ref.variablesReference,
      node.ref.name)
  else
    return string.format("unknown:%s", tostring(node))
  end
end

---Get or create state for node
---@param node table API object
---@return table State
function VariablesTreeNui:getNodeState(node)
  local id = self:getNodeId(node)
  if not self.tree_states[id] then
    self.tree_states[id] = {
      expanded = false,
      selected = false,
      visible = false,
      geometry = nil,
      children_loaded = false,
      cached_children = nil
    }
  end
  return self.tree_states[id]
end

---Get path for scope
---@param scope table Scope object
---@return string[]
function VariablesTreeNui:getScopePath(scope)
  if scope.getTreeNodePath then
    return scope:getTreeNodePath()
  end
  return { scope.ref.name }
end

---Get children of node
---@param node table API object
---@return table[]?
function VariablesTreeNui:getNodeChildren(node)
  self.logger:debug("getNodeChildren called for node: " .. tostring(node))
  
  -- Check if we have cached children first
  local state = self:getNodeState(node)
  if state.cached_children then
    self.logger:debug("getNodeChildren: returning cached children for " .. self:getNodeId(node))
    return state.cached_children
  end
  
  -- For now, return nil - children will be loaded asynchronously
  self.logger:debug("getNodeChildren: no cached children for " .. self:getNodeId(node))
  return nil
end

---Load children asynchronously
---@param node table API object
---@param callback function Called with children when loaded
function VariablesTreeNui:LoadChildrenAsync(node, callback)
  -- This method is PascalCase to indicate it's async
  self.logger:debug("LoadChildrenAsync called for node: " .. tostring(node))
  
  if node.getTreeNodeChildren then
    local children = node:getTreeNodeChildren()
    if children then
      callback(children)
      return
    end
  end
  
  -- Fallback logic for scopes
  if node.type and (node.type == "scope" or node.ref and node.ref.variablesReference) then
    -- It's a scope - use frame to get variables
    if self.current_frame and node.ref and node.ref.variablesReference then
      local vars = self.current_frame:variables(node.ref.variablesReference)
      self.logger:debug("LoadChildrenAsync: got " .. tostring(vars and #vars or "nil") .. " variables")
      -- Convert to Variable instances
      if vars then
        local var_instances = {}
        for _, v in ipairs(vars) do
          local Variable = require('neodap.api.Session.Variable')
          table.insert(var_instances, Variable:instanciate(node, v))
        end
        callback(var_instances)
        return
      end
    end
  elseif node.ref and node.ref.variablesReference and node.ref.variablesReference > 0 then
    -- Variable with children
    local frame = node.scope and node.scope.frame
    if frame then
      local vars = frame:variables(node.ref.variablesReference)
      -- Wrap in Variable instances
      local children = {}
      for _, v in ipairs(vars or {}) do
        local Variable = require('neodap.api.Session.Variable')
        table.insert(children, Variable:instanciate(node.scope, v))
      end
      callback(children)
      return
    end
  end
  
  callback(nil)
end

---Check if node is expandable
---@param node table API object
---@return boolean
function VariablesTreeNui:isNodeExpandable(node)
  print("[DEBUG] isNodeExpandable: node type = " .. type(node) .. ", node = " .. tostring(node))
  print("[DEBUG] isNodeExpandable: class_name = " .. tostring(node.class_name) .. ", type = " .. tostring(node.type))
  print("[DEBUG] isNodeExpandable: has isTreeNodeExpandable = " .. tostring(node.isTreeNodeExpandable ~= nil))
  
  if node.isTreeNodeExpandable then
    local result = node:isTreeNodeExpandable()
    print("[DEBUG] isNodeExpandable: calling isTreeNodeExpandable returned " .. tostring(result))
    return result
  end
  
  -- Fallback
  print("[DEBUG] isNodeExpandable: using fallback logic")
  if node.type and node.type == "scope" then
    return true
  elseif node.ref then
    return node.ref.variablesReference and node.ref.variablesReference > 0
  end
  return false
end

---Format node display
---@param node table API object
---@return string
function VariablesTreeNui:formatNodeDisplay(node)
  if node.formatTreeNodeDisplay then
    return node:formatTreeNodeDisplay()
  end
  
  -- Fallback
  if node.ref then
    if node.ref.value then
      return VisualImprovements.formatVariableDisplay(node.ref)
    else
      return node.ref.name
    end
  end
  return "unknown"
end

-- Path utilities are now handled directly through API objects and viewport system

---Check if current node has a valid API object
---@param node table NUI tree node
---@return boolean
function VariablesTreeNui:hasApiObject(node)
  return node and node.api_object ~= nil
end

-- ================================
-- WINDOW MANAGEMENT
-- ================================

function VariablesTreeNui:Show()
  local tabpage = vim.api.nvim_get_current_tabpage()

  -- Check if already open
  local win = self.windows[tabpage]
  if win and vim.api.nvim_win_is_valid(win.split.winid) then
    vim.api.nvim_set_current_win(win.split.winid)
    return
  end

  -- Create split window
  local split = NuiSplit({
    relative = "editor",
    position = "left",
    size = "30%",
    buf_options = {
      buftype = "nofile",
      bufhidden = "hide",
      swapfile = false,
      modifiable = true,
    },
    win_options = {
      wrap = false,      -- Disable line wrapping
      linebreak = false,
      cursorline = true, -- Highlight current line
      number = false,
      relativenumber = false,
      sidescrolloff = 5, -- Keep 5 columns visible when scrolling horizontally
      scrolloff = 3,     -- Keep 3 lines visible when scrolling vertically
    },
  })

  split:mount()

  -- Store reference
  self.windows[tabpage] = {
    split = split,
    tree = nil, -- Will be created by RenderWithViewport
  }

  -- Initial render with viewport
  self:RenderWithViewport(tabpage)

  -- Set buffer name for display
  vim.api.nvim_buf_set_name(split.bufnr, "Variables")
end

function VariablesTreeNui:Close()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local win = self.windows[tabpage]

  if win then
    win.split:unmount()
    self.windows[tabpage] = nil
  end
end

function VariablesTreeNui:Toggle()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local win = self.windows[tabpage]

  if win and vim.api.nvim_win_is_valid(win.split.winid) then
    self:Close()
  else
    self:Show()
  end
end

---Render tree using viewport system
---@param tabpage number Tabpage to render for
function VariablesTreeNui:RenderWithViewport(tabpage)  -- PascalCase for async
  local win = self.windows[tabpage]
  if not win or not vim.api.nvim_win_is_valid(win.split.winid) then
    return
  end

  self.logger:debug("RenderWithViewport: Starting render for tabpage " .. tabpage)

  -- Build the tree structure with API objects
  local tree_nodes = self:BuildViewportTree()
  self.logger:debug("RenderWithViewport: Built tree with " .. #tree_nodes .. " root nodes")

  -- Create breadcrumb header
  local header_lines = ViewportRenderer.createBreadcrumbHeader(
    self.viewport,
    vim.api.nvim_win_get_width(win.split.winid)
  )

  -- Convert to NUI Tree nodes
  local nui_nodes = self:convertToNuiNodes(tree_nodes)

  -- If no nodes, show a message
  if #nui_nodes == 0 then
    if not self.current_frame then
      -- No debug session
      nui_nodes = {
        NuiTree.Node({
          id = "no-debug",
          name = "No active debug session",
          text = "No active debug session",
          type = "info",
        })
      }
    else
      -- No variables in viewport
      nui_nodes = {
        NuiTree.Node({
          id = "no-vars",
          name = "No variables in current viewport",
          text = "No variables in current viewport",
          type = "info",
        })
      }
    end
  end

  -- Update buffer content with header
  vim.api.nvim_buf_set_option(win.split.bufnr, 'modifiable', true)

  -- Add header lines as text
  local header_text = {
    ViewportRenderer.createBreadcrumbDisplay(self.viewport),
    ViewportRenderer.createSeparatorLine(vim.api.nvim_win_get_width(win.split.winid))
  }
  vim.api.nvim_buf_set_lines(win.split.bufnr, 0, -1, false, header_text)

  -- Create and render NUI Tree starting after header
  local tree = NuiTree({
    bufnr = win.split.bufnr,
    nodes = nui_nodes,
    get_node_id = function(node) return node.id end,
    prepare_node = function(node)
      -- Use API object to prepare the line
      if node.api_object and node.viewport_geometry then
        return self:prepareNodeLine(node.api_object, node.viewport_geometry)
      else
        -- Fallback for non-API nodes
        return VisualImprovements.prepareNodeLine(node)
      end
    end,
  })

  -- Store tree reference
  win.tree = tree
  
  -- Debug: log tree structure
  self.logger:debug("Tree has " .. #nui_nodes .. " root nodes")
  for _, node in ipairs(nui_nodes) do
    self.logger:debug("  Node " .. node.id .. " has " .. (node:has_children() and node:get_child_ids() and #node:get_child_ids() or 0) .. " children")
  end
  
  -- Render starting after header lines
  tree:render(#header_lines)

  -- Setup viewport keybindings
  self:setupViewportKeybindings(win.split, win.tree)
end

---Convert API object tree to NUI Tree nodes
---@param tree_nodes table[] Tree nodes with API objects
---@return table[] NUI Tree nodes
function VariablesTreeNui:convertToNuiNodes(tree_nodes)
  local nui_nodes = {}

  for _, node in ipairs(tree_nodes) do
    local api_object = node.api_object
    local state = self:getNodeState(api_object)
    
    self.logger:debug("convertToNuiNodes: Converting " .. self:getNodeId(api_object) .. 
      ", has children: " .. tostring(node.children ~= nil) .. 
      ", expanded: " .. tostring(state.expanded))
    
    -- Create NUI node from API object
    local nui_node = NuiTree.Node({
      id = self:getNodeId(api_object),
      text = self:formatNodeDisplay(api_object),
      
      -- Store references
      api_object = api_object,
      viewport_geometry = node.geometry,
      viewport_path = node.path,
      
      -- UI properties
      is_expandable = self:isNodeExpandable(api_object),
      expanded = state.expanded
    }, node.children and self:convertToNuiNodes(node.children) or nil)

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
function VariablesTreeNui:NavigateViewport(action, current_node)
  local old_focus = vim.deepcopy(self.viewport.focus_path)

  self.logger:debug("NavigateViewport: action=" .. action .. ", old_focus=" .. vim.inspect(old_focus))
  if current_node then
    self.logger:debug("  Current node id=" .. (current_node.id or "?") .. 
      ", viewport_path=" .. vim.inspect(current_node.viewport_path))
  end

  if action == "enter" and current_node then
    -- Navigate deeper using API object
    if current_node.api_object then
      -- Store history
      table.insert(self.viewport.history, vim.deepcopy(self.viewport.focus_path))
      
      -- Use the viewport path
      if current_node.viewport_path then
        self.viewport.focus_path = vim.deepcopy(current_node.viewport_path)
      end
      
      -- Ensure node is expanded
      local state = self:getNodeState(current_node.api_object)
      if not state.expanded then
        state.expanded = true
      end
      
      self.logger:debug("  New focus_path after enter: " .. vim.inspect(self.viewport.focus_path))
    else
      self.logger:debug("  WARNING: current_node has no api_object!")
    end
  elseif action == "up" then
    -- Go up one level
    if #self.viewport.focus_path > 0 then
      table.insert(self.viewport.history, vim.deepcopy(self.viewport.focus_path))
      self.viewport.focus_path = ViewportSystem.shortenPath(self.viewport.focus_path)
      self.logger:debug("  New focus_path after up: " .. vim.inspect(self.viewport.focus_path))
    end
  elseif action == "back" then
    -- Navigate back in history
    self.viewport = ViewportSystem.navigateBack(self.viewport)
    self.logger:debug("  New focus_path after back: " .. vim.inspect(self.viewport.focus_path))
  elseif action == "root" then
    -- Go to root
    self.viewport = ViewportSystem.resetToRoot(self.viewport)
    self.logger:debug("  New focus_path after root: " .. vim.inspect(self.viewport.focus_path))
  end

  -- Refresh view if focus changed
  if not ViewportSystem.arePathsEqual(old_focus, self.viewport.focus_path) then
    self.logger:debug("  Focus changed - refreshing windows")
    self:RefreshAllWindows()
  else
    self.logger:debug("  Focus unchanged - no refresh needed")
  end
end

---Setup viewport keybindings
---@param split NuiSplit Window split
---@param tree NuiTree Tree instance
function VariablesTreeNui:setupViewportKeybindings(split, tree)
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
    if self:hasApiObject(node) then
      self:NavigateViewport("enter", node)
    end
  end, "Navigate into node")

  map("o", function()
    print("[DEBUG] 'o' key pressed")
    local node = tree:get_node()
    if self:hasApiObject(node) and node.api_object then
      -- Toggle expansion without changing viewport
      local state = self:getNodeState(node.api_object)
      print("[DEBUG] Toggling expansion for " .. self:getNodeId(node.api_object) .. " from " .. tostring(state.expanded))
      state.expanded = not state.expanded
      print("[DEBUG] New expanded state: " .. tostring(state.expanded))
      
      -- If expanding, ensure children are loaded first
      if state.expanded then
        self:EnsureChildrenLoaded(node.api_object)
      end
      
      self:RefreshAllWindows()
    else
      print("[DEBUG] No api_object on node")
    end
  end, "Toggle node expansion")

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
    self:RefreshAllWindows()
  end, "Increase viewport radius")

  map("-", function()
    self.viewport.radius = math.max(self.viewport.radius - 1, 1)
    self:RefreshAllWindows()
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
    self:RefreshAllWindows()
  end, "Cycle viewport style")

  -- Common keybindings
  map("q", function()
    self:Close()
  end, "Close variables")
end

-- ================================
-- WINDOW REFRESH
-- ================================

function VariablesTreeNui:RefreshAllWindows()  -- PascalCase for async
  print("[DEBUG] RefreshAllWindows called")
  for tabpage, win in pairs(self.windows) do
    if vim.api.nvim_tabpage_is_valid(tabpage) and
        vim.api.nvim_win_is_valid(win.split.winid) then
      print("[DEBUG] Refreshing tabpage " .. tabpage)
      self:RenderWithViewport(tabpage)
    else
      -- Clean up invalid windows
      self.windows[tabpage] = nil
    end
  end
end

-- ================================
-- NODE LINE PREPARATION
-- ================================

---Prepare a NUI line for an API object node
---@param api_object table Variable or Scope object
---@param geometry NodeGeometry Viewport geometry
---@return NuiLine
function VariablesTreeNui:prepareNodeLine(api_object, geometry)
  local line = NuiLine()
  
  -- Calculate indentation based on geometry depth
  local depth = math.max(0, geometry.depth_offset or 0)
  if geometry.relationship == "focus" or geometry.relationship == "sibling" then
    -- Adjust depth for proper visual hierarchy
    if api_object.getTreeNodePath then
      local path = api_object:getTreeNodePath()
      depth = math.max(0, #path - 1)
    else
      -- Fallback - count path segments
      depth = #(self:getScopePath(api_object)) - 1
    end
  end
  local indent = string.rep("  ", depth)
  line:append(indent)
  
  -- Add expand/collapse indicator
  local expandable = self:isNodeExpandable(api_object)
  print("[DEBUG] prepareNodeLine: " .. self:getNodeId(api_object) .. " expandable=" .. tostring(expandable))
  if expandable then
    local state = self:getNodeState(api_object)
    print("[DEBUG] prepareNodeLine: " .. self:getNodeId(api_object) .. " expanded=" .. tostring(state.expanded))
    if state.expanded then
      line:append("▾ ", geometry.is_focus and "Special" or "NonText")
    else
      line:append("▸ ", "NonText")
    end
  else
    line:append("  ")
  end
  
  -- Add icon based on type
  local icon, highlight
  
  -- Check if it's a scope - scopes have specific names and always have variablesReference
  local is_scope = false
  if api_object.ref and api_object.ref.name then
    local scope_names = {"Local", "Global", "Arguments", "Registers", "Closure"}
    for _, name in ipairs(scope_names) do
      if api_object.ref.name:match("^" .. name) then
        is_scope = true
        break
      end
    end
  end
  
  if is_scope then
    -- Scope
    local scope_base_name = api_object.ref.name:match("^(%w+)") or api_object.ref.name
    local scope_icon = VisualImprovements.SCOPE_ICONS[scope_base_name] or VisualImprovements.SCOPE_ICONS["Block"]
    icon = scope_icon
    highlight = "NeoTreeDirectoryIcon"
  elseif self:isNodeExpandable(api_object) then
    -- Expandable variable
    icon = VisualImprovements.getIcon(api_object.ref and api_object.ref.type or "unknown", true)
    highlight = "NeoTreeDirectoryIcon"
  else
    -- Leaf variable
    icon = VisualImprovements.getIcon(api_object.ref and api_object.ref.type or "unknown", false)
    highlight = "NeoTreeFileIcon"
  end
  
  line:append(icon .. " ", highlight)
  
  -- Add the display text
  local display_text = self:formatNodeDisplay(api_object)
  
  -- Parse display text for syntax highlighting (for variables)
  if api_object.ref and api_object.ref.value then
    local colonPos = display_text:find(": ")
    if colonPos then
      -- Property name
      local propName = display_text:sub(1, colonPos - 1)
      local value = display_text:sub(colonPos + 2)
      
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
      line:append(display_text)
    end
  else
    -- Scope or variable without value
    line:append(display_text)
  end
  
  -- Add focus indicator only if we have an actual focus path
  if geometry.is_focus and self.viewport.focus_path and #self.viewport.focus_path > 0 then
    line:append(" ← HERE", "Special")
  end
  
  return line
end

return VariablesTreeNui
