-- Variables4 Plugin - AsNode() Caching Strategy
-- Variables and Scopes get an asNode() method that creates and caches NuiTree.Nodes

local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')
local NvimAsync = require('neodap.tools.async')

-- ========================================
-- PLUGIN CLASS
-- ========================================

---@class Variables4Plugin
---@field api Api
---@field current_frame? api.Frame
---@field logger Logger
---@field true_root_ids? string[]
local Variables4Plugin = Class()

Variables4Plugin.name = "Variables4"

-- ========================================
-- PLUGIN INITIALIZATION
-- ========================================

function Variables4Plugin.plugin(api)
  local instance = Variables4Plugin:new({
    api = api,
    logger = Logger.get("Variables4"),
  })

  instance:initialize()
  return instance
end

function Variables4Plugin:initialize()
  self.logger:info("Initializing Variables4 plugin - asNode() caching strategy")

  -- Initialize viewport state (no longer tracking focus mode as a boolean)

  -- Set up event handlers
  self:setupEventHandlers()

  -- Create commands
  self:setupCommands()

  self.logger:info("Variables4 plugin initialized")
end

-- ========================================
-- VARIABLE PRESENTATION STRATEGY (Information Gem)
-- ========================================

-- Variable Presentation: How a variable should appear in the UI
local VariablePresentation = {
  -- Visual representation (icon + highlight + truncation)
  styles = {
    -- JavaScript primitives
    string = { icon = "󰉿", highlight = "String", truncate = 35 },
    number = { icon = "󰎠", highlight = "Number", truncate = 40 },
    boolean = { icon = "◐", highlight = "Boolean", truncate = 40 },
    undefined = { icon = "󰟢", highlight = "Constant", truncate = 40 },
    ['nil'] = { icon = "∅", highlight = "Constant", truncate = 40 },
    null = { icon = "∅", highlight = "Constant", truncate = 40 },

    -- Complex types
    object = { icon = "󰅩", highlight = "Structure", truncate = 40 },
    array = { icon = "󰅪", highlight = "Structure", truncate = 40 },
    ['function'] = { icon = "󰊕", highlight = "Function", truncate = 25 },

    -- Special types
    date = { icon = "󰃭", highlight = "Special", truncate = 40 },
    regexp = { icon = "󰑑", highlight = "String", truncate = 40 },
    map = { icon = "󰘣", highlight = "Type", truncate = 40 },
    set = { icon = "󰘦", highlight = "Type", truncate = 40 },

    -- Default fallback
    default = { icon = "󰀬", highlight = "Identifier", truncate = 40 },
  }
}

-- Get presentation style for a variable type
function VariablePresentation.getStyle(var_type)
  return VariablePresentation.styles[var_type] or VariablePresentation.styles.default
end

-- Unified type detection using presentation strategy
local function getTypeInfo(ref)
  if not ref or not ref.type then
    local style = VariablePresentation.getStyle("default")
    return style.icon, style.highlight, false
  end

  local var_type = ref.type:lower()
  local is_array = var_type == "object" and ref.value and ref.value:match("^%[.*%]$")

  if is_array then
    local style = VariablePresentation.getStyle("array")
    return style.icon, style.highlight, true
  end

  local style = VariablePresentation.getStyle(var_type)
  return style.icon, style.highlight, false
end

-- Format variable value using presentation strategy
local function formatVariableValue(ref)
  if not ref then return "undefined" end

  local value = ref.value or ""
  local var_type = ref.type or "default"
  local style = VariablePresentation.getStyle(var_type)

  -- Handle multiline values by inlining
  if type(value) == "string" then
    value = value:gsub("[\r\n]+", " "):gsub("\\[nrt]", " "):gsub("%s+", " ")
    value = value:match("^%s*(.-)%s*$") or ""

    -- Smart truncation using presentation strategy
    if #value > style.truncate then
      value = value:sub(1, style.truncate - 3) .. "..."
    end
  end

  -- Type-specific formatting
  if var_type == "string" then
    return string.format('"%s"', value)
  elseif var_type == "function" and value:match("^function") then
    local signature = value:match("^function%s*([^{]*)")
    if signature then
      local max_sig = 20 -- signature truncation
      return "ƒ " .. signature:gsub("%s+", " "):sub(1, max_sig) .. (signature:len() > max_sig and "..." or "")
    end
  elseif var_type == "object" and ref.variablesReference and ref.variablesReference > 0 then
    return value:match("^%{.*%}$") and value or ("{" .. (value or "Object") .. "}")
  end

  return value
end

-- ========================================
-- AS-NODE METHOD EXTENSIONS
-- ========================================

local Variable = require('neodap.api.Session.Variable')
local ArgumentsScope = require('neodap.api.Session.Scope.ArgumentsScope')
local LocalsScope = require('neodap.api.Session.Scope.LocalsScope')
local GlobalsScope = require('neodap.api.Session.Scope.GlobalsScope')
local ReturnValueScope = require('neodap.api.Session.Scope.ReturnValueScope')
local RegistersScope = require('neodap.api.Session.Scope.RegistersScope')
local GenericScope = require('neodap.api.Session.Scope.GenericScope')

local NuiTree = require("nui.tree")
local BaseScope = require("neodap.api.Session.Scope.BaseScope")

-- Helper function to validate variable structure
local function validateVariableRef(variable, method_name)
  if not variable.ref then
    error(method_name .. " called on variable with no ref property")
  end
  if not variable.ref.name then
    error(method_name .. " called on variable with no name in ref")
  end
end

---@class (partial) api.Variable
---@field _node NuiTree.Node?
---@field asNode fun(self: Variable): NuiTree.Node
---@field variables fun(self: Variable): api.Variable[]?
function Variable:asNode()
  if self._node then return self._node end

  validateVariableRef(self, "Variable:asNode()")

  -- Check for lazy variables - many global objects in Node.js are lazy-loaded getters
  if self.ref.presentationHint then
    if self.ref.presentationHint.lazy then
      Logger.get("Variables4"):info("Found lazy variable: " ..
        self.ref.name .. " with hint: " .. vim.inspect(self.ref.presentationHint))
    end
  end

  -- Debug: Log getter functions to see if they should be marked as lazy
  if self.ref.value and type(self.ref.value) == "string" and self.ref.value:match("^ƒ get%(%)") then
    Logger.get("Variables4"):debug("Found getter function (potential lazy var): " ..
      self.ref.name .. " = " .. self.ref.value:sub(1, 50))
  end

  -- Get icon, highlight, and formatted value using our enhancement functions
  local icon, highlight, _ = getTypeInfo(self.ref)
  local formatted_value = formatVariableValue(self.ref)

  -- Generate unique ID using parent context for hierarchy
  local parent_context = self._parent_var_ref or
      (self.scope and self.scope.ref and self.scope.ref.name) or
      "root"
  local node_id = string.format("var:%s:%s", parent_context, self.ref.name)

  self._node = NuiTree.Node({
    id = node_id,
    text = string.format("%s %s: %s", icon, self.ref.name, formatted_value),
    type = "variable",
    expandable = self.ref.variablesReference and self.ref.variablesReference > 0,
    _variable = self,       -- Store reference to original variable for access to methods
    _highlight = highlight, -- Store highlight group for tree rendering
  }, {})

  return self._node
end

-- Add variables method to Variable for nested children
function Variable:variables()
  validateVariableRef(self, "Variable:variables()")

  if not (self.ref.variablesReference and self.ref.variablesReference > 0) then
    return nil
  end

  -- Get the frame from our scope
  local frame = self.scope and self.scope.frame
  if not frame then
    error("Variable:variables() called on variable with no frame reference")
  end

  return frame:variables(self.ref.variablesReference)
end

function BaseScope:asNode()
  if self._node then return self._node end

  -- Use consistent folder icon and scope-specific highlighting
  local scope_text = "📁 " .. self.ref.name

  self._node = NuiTree.Node({
    id = string.format("scope:%s", self.ref.name),
    text = scope_text,
    type = "scope",
    expandable = true,
    _scope = self,            -- Store reference to original scope for access to methods
    _highlight = "Directory", -- Use Directory highlight for scopes
  }, {})

  return self._node
end

-- Add BaseScope methods to concrete scope classes (inheritance fix)
local scope_classes = {
  ArgumentsScope, LocalsScope, GlobalsScope,
  ReturnValueScope, RegistersScope, GenericScope
}

for _, ScopeClass in ipairs(scope_classes) do
  -- Add both variables and asNode methods if not present
  if not ScopeClass.variables and BaseScope.variables then
    ScopeClass.variables = BaseScope.variables
  end
  if not ScopeClass.asNode and BaseScope.asNode then
    ScopeClass.asNode = BaseScope.asNode
  end
end

-- ========================================





-- ========================================
-- EVENT HANDLERS
-- ========================================

function Variables4Plugin:setupEventHandlers()
  self.api:onSession(function(session)
    session:onThread(function(thread)
      thread:onStopped(function(stopped_event)
        local stack = thread:stack()
        if stack then
          self:UpdateCurrentFrame(stack:top())
        end
      end)

      thread:onContinued(function()
        self:ClearCurrentFrame()
      end)
    end)

    session:onTerminated(function()
      self:ClearCurrentFrame()
    end)
  end)
end

function Variables4Plugin:UpdateCurrentFrame(frame)
  self.current_frame = frame
  self.logger:debug("Updated current frame")
end

function Variables4Plugin:ClearCurrentFrame()
  self.current_frame = nil
  self.logger:debug("Cleared current frame")
end

-- ========================================
-- USER COMMANDS
-- ========================================

function Variables4Plugin:setupCommands()
  -- Core functionality - open the variables tree popup
  vim.api.nvim_create_user_command("Variables4Tree", function()
    self:OpenVariablesTree()
  end, { desc = "Open Variables4 tree popup" })

  -- Frame management commands
  vim.api.nvim_create_user_command("Variables4UpdateFrame", function()
    self:UpdateFrameCommand()
  end, { desc = "Update Variables4 current frame to top of stack" })

  vim.api.nvim_create_user_command("Variables4ClearFrame", function()
    self:ClearCurrentFrame()
  end, { desc = "Clear Variables4 current frame" })
end

-- ========================================
-- DEBUG SESSION CONTEXT (Information Gem)
-- ========================================

-- Debug Session Context: The current debugging state and capabilities
local SessionContext = {
  INACTIVE = "inactive", -- No debug session
  ACTIVE = "active",     -- Session running but not stopped
  STOPPED = "stopped",   -- Session stopped at breakpoint
}

-- Get current session context
function Variables4Plugin:getSessionContext()
  if not self.current_frame then
    return SessionContext.INACTIVE
  end

  -- If we have a frame, we're stopped at a breakpoint
  return SessionContext.STOPPED
end

-- Execute action only in appropriate session context
function Variables4Plugin:withSessionContext(required_context, action, context_message)
  local current_context = self:getSessionContext()

  if current_context ~= required_context then
    local context_names = {
      [SessionContext.INACTIVE] = "no debug session",
      [SessionContext.ACTIVE] = "debug session running",
      [SessionContext.STOPPED] = "debug session stopped"
    }
    print(context_names[current_context] .. " - " .. context_message)
    return nil
  end

  return action()
end

-- Get current scopes (only available when stopped)
function Variables4Plugin:getCurrentScopesAndVariables()
  return self:withSessionContext(SessionContext.STOPPED, function()
    local frame = self.current_frame
    if not frame then
      print("No current frame available")
      return nil
    end

    local scopes = frame:scopes()
    if not scopes or #scopes == 0 then
      print("No scopes available")
      return nil
    end

    return scopes
  end, "cannot access variables")
end

-- ========================================
-- FOCUS MODE HELPER METHODS
-- ========================================


-- Refined popup title update with simplified path generation
function Variables4Plugin:updatePopupTitle(tree, popup)
  if not (popup and popup.border and popup.border.text) then return end

  -- Quick path: if showing all roots, use default title
  if vim.deep_equal(tree.nodes.root_ids, self.true_root_ids) then
    popup.border.text.top = " Variables4 Debug Tree "
    popup:update_layout()
    return
  end

  -- Build viewport path from first root to its ancestors
  local path_parts = {}
  local current = tree.nodes.root_ids[1] and tree.nodes.by_id[tree.nodes.root_ids[1]]
  
  while current do
    -- Extract simple name from node text
    local name = "?"
    if current.text then
      local colon_pos = current.text:find(": ")
      if colon_pos then
        -- Variable format: "icon name: value" → extract name
        local before_colon = current.text:sub(1, colon_pos - 1)
        name = before_colon:match(" ([^ ]+)$") or before_colon
      else
        -- Scope format: "📁 ScopeName" → extract name
        name = current.text:match("📁%s*(.+)") or current.text
      end
    end
    
    table.insert(path_parts, 1, name)
    local parent_id = current:get_parent_id()
    if not parent_id then break end
    current = tree.nodes.by_id[parent_id]
  end
  
  -- Remove current level and build title
  table.remove(path_parts)
  local title = #path_parts > 0 
    and " Variables4: " .. table.concat(path_parts, " → ") .. " "
    or " Variables4 Debug Tree "
    
  popup.border.text.top = title
  popup:update_layout()
end

-- Focus on a specific node by setting viewport to show it and its siblings
function Variables4Plugin:focusOnNode(tree, popup, node_id)
  local node = tree.nodes.by_id[node_id]
  if not node then return end

  local parent_id = node:get_parent_id()
  local new_roots
  if parent_id then
    local parent_node = tree.nodes.by_id[parent_id]
    new_roots = (parent_node and parent_node:has_children()) and parent_node:get_child_ids() or { node_id }
  else
    new_roots = { node_id }
  end

  -- Inlined setViewportRoots logic
  tree.nodes.root_ids = new_roots
  tree:render()
  self:updatePopupTitle(tree, popup)
  self.logger:debug("Viewport changed: focused on " .. (node.text or "unknown"))
end

-- ========================================
-- PATH AND VIEWPORT MANAGEMENT
-- ========================================

-- Check if a node is currently visible in the tree (crystallized inline)
function Variables4Plugin:isNodeVisible(tree, node_id)
  -- Inline check without creating full visible_nodes array
  local function isVisible(check_id, root_ids)
    for _, root_id in ipairs(root_ids) do
      if root_id == check_id then return true end
      local root_node = tree.nodes.by_id[root_id]
      if root_node and root_node:is_expanded() and root_node:has_children() then
        if isVisible(check_id, root_node:get_child_ids()) then return true end
      end
    end
    return false
  end
  return isVisible(node_id, tree.nodes.root_ids)
end

-- Refined viewport adjustment with simplified logic
function Variables4Plugin:adjustViewportForNode(tree, target_node_id)
  if self:isNodeVisible(tree, target_node_id) then return false end
  
  local target_node = tree.nodes.by_id[target_node_id]
  if not target_node then return false end

  local parent_id = target_node:get_parent_id()
  
  -- No parent: show all roots
  if not parent_id then
    tree.nodes.root_ids = self.true_root_ids or tree.nodes.root_ids
    self.logger:debug("Viewport adjusted to show all roots")
    return true
  end
  
  -- Has parent: find appropriate level to show
  local parent_node = tree.nodes.by_id[parent_id]
  local grandparent_id = parent_node and parent_node:get_parent_id()
  
  if grandparent_id then
    -- Show parent and its siblings (children of grandparent)
    local grandparent = tree.nodes.by_id[grandparent_id]
    if grandparent and grandparent:has_children() then
      tree.nodes.root_ids = grandparent:get_child_ids()
      self.logger:debug("Viewport adjusted to show parent level and siblings")
      return true
    end
  end
  
  -- Fallback: show all roots
  tree.nodes.root_ids = self.true_root_ids or tree.nodes.root_ids
  self.logger:debug("Viewport adjusted to root level")
  return true
end

-- ========================================
-- OPERATION CONTEXT (Use-Case Optimization)
-- ========================================

-- TreeOperationContext: Encapsulates the working environment for all tree operations
local TreeOperationContext = {}
TreeOperationContext.__index = TreeOperationContext

function TreeOperationContext.new(plugin, tree, popup)
  return setmetatable({
    plugin = plugin,
    tree = tree,
    popup = popup,
  }, TreeOperationContext)
end

-- Simplified navigation to target node
function TreeOperationContext:navigateToNode(target_node_id, should_collapse)
  if not target_node_id then return false end
  
  -- Ensure target is visible
  if not self.plugin:isNodeVisible(self.tree, target_node_id) then
    self.plugin:adjustViewportForNode(self.tree, target_node_id)
  end

  -- Apply collapse if requested
  if should_collapse then
    local target_node = self.tree.nodes.by_id[target_node_id]
    if target_node and target_node:is_expanded() then
      target_node:collapse()
      self.plugin:collapseAllChildren(self.tree, target_node)
    end
  end

  -- Render and position cursor
  self.tree:render()
  self.plugin:updatePopupTitle(self.tree, self.popup)
  self.plugin:setCursorToNode(self.tree, target_node_id)
  return true
end


-- Get current node with context
function TreeOperationContext:getCurrentNode()
  return self.tree:get_node()
end


-- Simplified node expansion logic
function TreeOperationContext:drillIntoNode(node)
  -- Check for lazy variables first
  if node._variable and node._variable.ref and node._variable.ref.presentationHint then
    local hint = node._variable.ref.presentationHint
    if hint.lazy and not node._lazy_resolved then
      return self.plugin:resolveLazyVariable(self.tree, node, self.popup)
    end
  end

  -- Handle expandable nodes
  if node.expandable then
    if not node._children_loaded then
      return self.plugin:ExpandNodeAndNavigate(self.tree, node, self.popup)
    elseif not node:is_expanded() then
      node:expand()
      self.tree:render()
      self.plugin:moveToFirstChild(self.tree, node)
    else
      self.plugin:moveToFirstChild(self.tree, node)
    end
  end
  -- Leaf nodes: no action
end

-- Use-Case Focused Operations: Direct expression of user intentions
function TreeOperationContext:expandVariableToSeeContents()
  local node = self:getCurrentNode()
  if node then
    return self:drillIntoNode(node)
  end
end

function TreeOperationContext:navigateToSibling(direction)
  local current_node = self:getCurrentNode()
  if not current_node then return end
  
  local target
  if direction == "next" then
    target = self.plugin:getVisibleNodeNeighbor(self.tree, current_node, "next") or self.plugin:findNextLogicalSibling(self.tree, current_node)
  else
    target = self.plugin:getVisibleNodeNeighbor(self.tree, current_node, "previous") or current_node:get_parent_id()
  end
  
  if target then
    return self:navigateToNode(target, false)
  end
end

function TreeOperationContext:navigateToParentLevel()
  local current_node = self:getCurrentNode()
  if not current_node then return end
  
  local target = current_node:get_parent_id() or self.plugin:getViewportParent(self.tree)
  if target then
    return self:navigateToNode(target, true)  -- collapse when going up
  end
end

function TreeOperationContext:focusOnCurrentScope()
  local node = self:getCurrentNode()
  if node then
    local parent_id = node:get_parent_id()
    if parent_id then
      self.plugin:focusOnNode(self.tree, self.popup, parent_id)
    end
  end
end

-- Concept Composition: Complex operations using multiple concepts
function TreeOperationContext:smartExpand()
  -- Smart expand: if already expanded, focus on scope; if collapsed, expand
  local node = self:getCurrentNode()
  if not node then return end

  local state = NodeStateMachine.getState(node)
  if state == "expanded" then
    -- Already expanded, focus on this level instead
    self:focusOnCurrentScope()
  else
    -- Not expanded, do normal expansion
    self:expandVariableToSeeContents()
  end
end

function TreeOperationContext:quickNavigate(direction)
  -- Quick navigate: try linear first, fallback to hierarchical
  local intent = direction == "down" and NavigationIntent.LINEAR_FORWARD or NavigationIntent.LINEAR_BACKWARD
  local success = self:navigate(intent)

  if not success and direction == "up" then
    -- If linear up failed, try hierarchical up
    self:navigateToParentLevel()
  end
end

-- ========================================
-- NAVIGATION CONCEPTS (Information Gems)
-- ========================================



-- Find next logical sibling when linear navigation reaches boundary
function Variables4Plugin:findNextLogicalSibling(tree, current_node)
  local node_to_check = current_node
  while node_to_check do
    local parent_id = node_to_check:get_parent_id()
    if not parent_id then break end

    local parent_node = tree.nodes.by_id[parent_id]
    if parent_node and parent_node:has_children() then
      local sibling_ids = parent_node:get_child_ids()
      local current_check_id = node_to_check:get_id()

      for i, sibling_id in ipairs(sibling_ids) do
        if sibling_id == current_check_id and i < #sibling_ids then
          return sibling_ids[i + 1]
        end
      end
    end
    node_to_check = parent_node
  end
  return nil
end

-- Get parent of current viewport for focused view navigation
function Variables4Plugin:getViewportParent(tree)
  if not tree.nodes.root_ids or not self.true_root_ids then
    return nil
  end

  -- Check if we're in a focused view (not showing all roots)
  if #tree.nodes.root_ids == #self.true_root_ids then
    for i, id in ipairs(tree.nodes.root_ids) do
      if id ~= self.true_root_ids[i] then
        break
      end
      if i == #tree.nodes.root_ids then
        return nil -- Showing all roots
      end
    end
  end

  -- We're in a focused view - get parent of first root
  local first_root = tree.nodes.by_id[tree.nodes.root_ids[1]]
  return first_root and first_root:get_parent_id()
end

-- Unified visible node navigation (crystallized from 3 separate methods)
function Variables4Plugin:getVisibleNodeNeighbor(tree, current_node, direction)
  local visible_nodes = {}

  -- Inline traversal (no separate getVisibleNodes method needed)
  local function traverse(node_id)
    local node = tree.nodes.by_id[node_id]
    if not node then return end
    table.insert(visible_nodes, node_id)
    if node:is_expanded() and node:has_children() then
      for _, child_id in ipairs(node:get_child_ids()) do
        traverse(child_id)
      end
    end
  end

  for _, root_id in ipairs(tree.nodes.root_ids) do
    traverse(root_id)
  end

  local current_id = current_node:get_id()
  for i, node_id in ipairs(visible_nodes) do
    if node_id == current_id then
      if direction == "next" and i < #visible_nodes then
        return visible_nodes[i + 1]
      elseif direction == "previous" and i > 1 then
        return visible_nodes[i - 1]
      end
      break
    end
  end
  return nil
end

-- Crystallized cursor positioning: simplified smart positioning
function Variables4Plugin:setCursorToNode(tree, node_id)
  local node, linenr_start = tree:get_node(node_id)
  if node and linenr_start then
    -- Simplified: find first alphanumeric char after tree decorations
    local line = vim.api.nvim_buf_get_lines(0, linenr_start - 1, linenr_start, false)[1] or ""
    local col = line:find("[%w_]") or 6 -- Find first word char or default to 6
    vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), { linenr_start, col - 1 })
  else
    -- Fallback: stay on current line, column 4
    local current_line = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())[1]
    vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), { current_line, 4 })
  end
end

-- Simple cursor positioning: just put cursor at column 4 for most items
-- This covers the common case of "▶ 📁  Name" where name starts at column 4

-- Note: navigateToFirstChild wrapper removed - using navigate() directly

-- Helper to move cursor to first child of a node with drill-down behavior
function Variables4Plugin:moveToFirstChild(tree, node)
  if node:is_expanded() and node:has_children() then
    local child_ids = node:get_child_ids()
    if child_ids and #child_ids > 0 then
      local first_child_id = child_ids[1]
      self:setCursorToNode(tree, first_child_id)

      -- Log the drill-down action for better user feedback
      local first_child = tree.nodes.by_id[first_child_id]
      if first_child then
        self.logger:debug("Drilled down to: " .. (first_child.text or "unknown"))
      end
    end
  end
end

-- Simplified node expansion without callback complexity
function Variables4Plugin:ExpandNodeAndNavigate(tree, node, popup)
  if node._children_loaded then return end
  
  local data_object = node._scope or node._variable
  if not data_object or not data_object.variables then
    if not data_object then return end
    self.logger:warn("Data object has no variables() method: " .. (node.text or "unknown"))
    return
  end

  NvimAsync.run(function()
    local children = data_object:variables()
    
    -- Build existing child name set for duplicate detection
    local existing_names = {}
    if node:has_children() then
      for _, child_id in ipairs(node:get_child_ids()) do
        local child = tree.nodes.by_id[child_id]
        if child and child._variable and child._variable.ref then
          existing_names[child._variable.ref.name] = true
        end
      end
    end

    local added_count = 0
    if children and #children > 0 then
      for _, child in ipairs(children) do
        -- Prepare variable instance
        local instance = child.ref and child or Variable.instanciate(data_object.scope or data_object, child)
        local parent_ref = node._variable and node._variable.ref.variablesReference
        if parent_ref then instance._parent_var_ref = parent_ref end
        instance.asNode = instance.asNode or Variable.asNode
        instance.variables = instance.variables or Variable.variables

        -- Add if not duplicate
        if not existing_names[instance.ref.name] then
          local child_node = instance:asNode()
          child_node._variable = instance
          tree:add_node(child_node, node:get_id())
          added_count = added_count + 1
        end
      end
    end

    node._children_loaded = true
    
    if added_count > 0 then
      self.logger:debug(string.format("Loaded %d children (skipped %d duplicates) for: %s", 
        added_count, #children - added_count, node.text or "unknown"))
      node:expand()
      tree:render()
      self:moveToFirstChild(tree, node)  -- Direct call instead of callback
    else
      self.logger:debug("No new children for: " .. (node.text or "unknown"))
    end
  end)
end

-- Helper to recursively collapse all children of a node
function Variables4Plugin:collapseAllChildren(tree, node)
  if not node or not node:has_children() then
    return
  end

  -- Get all child IDs
  local child_ids = node:get_child_ids()
  if not child_ids then
    return
  end

  -- Recursively collapse children first (depth-first)
  for _, child_id in ipairs(child_ids) do
    local child_node = tree.nodes.by_id[child_id]
    if child_node then
      -- Recursively collapse children of this child
      self:collapseAllChildren(tree, child_node)
      -- Then collapse this child if it's expanded
      if child_node:is_expanded() then
        child_node:collapse()
      end
    end
  end
end

-- Note: Navigation wrapper methods removed - keybindings call navigate() directly


-- ========================================
-- COMMAND IMPLEMENTATIONS
-- ========================================

function Variables4Plugin:UpdateFrameCommand()
  self:withSessionContext(SessionContext.STOPPED, function()
    local frame = self.current_frame
    local stack = frame.stack
    if stack then
      local top_frame = stack:top()
      if top_frame then
        self:UpdateCurrentFrame(top_frame)
        print("✓ Variables4 frame updated to stack top")
        print("Frame: " .. (top_frame.ref.name or "unknown"))
      else
        print("No frames available in current stack")
      end
    else
      print("No stack available for current thread")
    end
  end, "cannot update frame")
end

-- ========================================
-- LAZY VARIABLE RESOLUTION
-- ========================================

-- Refined lazy variable resolution
function Variables4Plugin:resolveLazyVariable(tree, node, popup)
  local variable = node._variable
  if not (variable and variable.ref) then return end
  
  local frame = variable.scope and variable.scope.frame
  if not (frame and frame.ref) then
    self.logger:warn("No frame available for lazy variable: " .. variable.ref.name)
    return
  end

  NvimAsync.run(function()
    local resolved = variable:resolve()
    
    if resolved then
      -- Update node with resolved values
      variable._node = nil
      local resolved_node = variable:asNode()
      node.text = resolved_node.text
      node.expandable = resolved_node.expandable
      node._highlight = resolved_node._highlight
      node._lazy_resolved = true
      
      if node.expandable then
        node._children_loaded = false
        if not node._children_loaded then
          self:ExpandNodeAndNavigate(tree, node, popup)
        elseif node:has_children() then
          self:moveToFirstChild(tree, node)
        end
      end
      
      self.logger:debug("Resolved: " .. variable.ref.name .. " -> " .. (variable.ref.value or ""))
    else
      self.logger:debug("Failed to resolve: " .. variable.ref.name)
    end

    tree:render()
  end)
end

-- ========================================
-- TREE ASSEMBLY PIPELINE (Information Gem)
-- ========================================

-- Tree Assembly Pipeline: Transform debug data into interactive UI
local TreeAssembly = {}

-- Step 1: Prepare debug data for UI
function TreeAssembly.prepareData(scopes)
  local tree_nodes = {}
  for _, scope in ipairs(scopes) do
    table.insert(tree_nodes, scope:asNode())
  end
  return tree_nodes
end

-- Step 2: Create popup window
function TreeAssembly.createPopup()
  local Popup = require("nui.popup")
  local popup = Popup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = { top = " Variables4 Debug Tree ", top_align = "center" },
    },
    position = "50%",
    size = { width = "80%", height = "70%" },
    buf_options = { modifiable = false, readonly = true },
    win_options = { wrap = false },
  })
  popup:mount()
  return popup
end

-- Step 3: Create tree widget
function TreeAssembly.createTree(popup, tree_nodes)
  local NuiTree = require("nui.tree")
  return NuiTree({
    bufnr = popup.bufnr,
    nodes = tree_nodes,
  })
end

-- Step 4: Setup custom rendering
function TreeAssembly.setupRendering(tree)
  local NuiLine = require("nui.line")

  tree._.prepare_node = function(node)
    local line = NuiLine()

    -- Calculate relative indentation for viewport
    local min_depth = math.huge
    for _, root_id in ipairs(tree.nodes.root_ids) do
      local root_node = tree.nodes.by_id[root_id]
      if root_node then
        min_depth = math.min(min_depth, root_node:get_depth())
      end
    end
    local relative_depth = math.max(0, node:get_depth() - min_depth)

    -- Add UTF-8 indent indicators
    for i = 1, relative_depth do
      if i == relative_depth then
        line:append("╰─ ", "Comment")
      else
        line:append("│  ", "Comment")
      end
    end

    -- Add expand/collapse indicator
    if node:has_children() or node.expandable then
      if node:is_expanded() then
        line:append("▼ ", "Comment")
      else
        line:append("▶ ", "Comment")
      end
    else
      line:append("  ")
    end

    -- Add content with highlighting
    local text = node.text or ""
    if node.type == "scope" then
      local scope_name = text:match("📁%s+(.+)") or text
      line:append("📁 ", "Directory")
      line:append(scope_name, "Directory")
    else
      -- Parse "icon name: value" format
      local icon_pos, colon_pos = text:find(" "), text:find(": ")
      if icon_pos and colon_pos and icon_pos < colon_pos then
        local icon = text:sub(1, icon_pos - 1)
        local name = text:sub(icon_pos + 1, colon_pos - 1)
        local value = text:sub(colon_pos + 2)

        line:append(icon .. " ", "Comment")
        line:append(name .. ": ", "Identifier")
        line:append(value, node._highlight or "Normal")
      else
        line:append(text)
      end
    end

    return line
  end
end

-- Main tree assembly function
function Variables4Plugin:OpenVariablesTree()
  local scopes = self:getCurrentScopesAndVariables()
  if not scopes then return end

  -- Execute assembly pipeline
  local tree_nodes = TreeAssembly.prepareData(scopes)
  local popup = TreeAssembly.createPopup()
  local tree = TreeAssembly.createTree(popup, tree_nodes)

  -- Setup tree appearance and behavior
  TreeAssembly.setupRendering(tree)
  self.true_root_ids = vim.deepcopy(tree.nodes.root_ids)
  tree:render()

  -- Initialize cursor position (crystallized inline)
  local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
  local col = line:find("[%w_]") or 6
  vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), { 1, col - 1 })

  -- Setup navigation and controls
  self:setupTreeKeybindings(popup, tree)
end

function Variables4Plugin:setupTreeKeybindings(popup, tree)
  local map_options = { noremap = true, silent = true }
  local context = TreeOperationContext.new(self, tree, popup)

  -- Use-case driven navigation (expresses user intent directly)
  popup:map("n", "h", function() context:navigateToParentLevel() end, map_options)
  popup:map("n", "j", function() context:navigateToSibling("next") end, map_options)
  popup:map("n", "k", function() context:navigateToSibling("previous") end, map_options)
  popup:map("n", "l", function() context:expandVariableToSeeContents() end, map_options)

  -- Controls
  popup:map("n", "q", function() popup:unmount() end, map_options)
  popup:map("n", "<Esc>", function() popup:unmount() end, map_options)
  popup:map("n", "f", function() context:focusOnCurrentScope() end, map_options)

  -- Help
  popup:map("n", "?", function()
    print("Variables4 Tree Controls (Use-Case Driven):")
    print("")
    print("Core Actions:")
    print("  l: Expand variable to see contents")
    print("  h: Navigate to parent level")
    print("  j/k: Navigate to next/previous sibling")
    print("  f: Focus on current scope")
    print("")
    print("Controls:")
    print("  q/Esc: Close popup")
    print("  ?: Show this help")
    print("")
    print("The interface automatically handles:")
    print("- Lazy variable resolution")
    print("- Viewport adjustment for navigation")
    print("- Node state transitions")
    print("- Tree rendering and updates")
  end, map_options)
end

-- ========================================
-- MODULE EXPORTS
-- ========================================

return Variables4Plugin
