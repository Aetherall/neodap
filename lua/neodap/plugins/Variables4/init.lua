-- Variables4 Plugin - AsNode() Caching Strategy
-- Variables and Scopes get an asNode() method that creates and caches NuiTree.Nodes

local BasePlugin = require('neodap.plugins.BasePlugin')
local NvimAsync = require('neodap.tools.async')
local Collection = require('neodap.tools.Collection')
local Logger = require('neodap.tools.logger')

-- ========================================
-- PLUGIN CLASS
-- ========================================

---@class Variables4Plugin: BasePlugin
---@field frame api.Frame
---@field true_root_ids? string[]
---@field tree NuiTree
---@field popup NuiPopup
local Variables4Plugin = BasePlugin:extend()

Variables4Plugin.name = "Variables4"

-- ========================================
-- PLUGIN INITIALIZATION
-- ========================================

function Variables4Plugin.plugin(api)
  return BasePlugin.createPlugin(api, Variables4Plugin)
end

function Variables4Plugin:listen()
  self.logger:info("Initializing Variables4 plugin - asNode() caching strategy")
  
  -- Set up event handlers
  self:setupEventHandlers()

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
local BaseScope = require('neodap.api.Session.Scope.BaseScope')

local NuiTree = require("nui.tree")

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

-- Note: With scope unification, all scope functionality is now in BaseScope
-- No need to copy methods to individual scope classes since they're unified

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
  self.frame = frame
  self.logger:debug("Updated current frame")
end

function Variables4Plugin:ClearCurrentFrame()
  self.frame = nil
  -- Also clear UI state when session ends
  self:closeTree()
  self.logger:debug("Cleared current frame and UI state")
end

function Variables4Plugin:closeTree()
  if self.popup then
    self.popup:unmount()
    self.popup = nil
  end
  self.tree = nil
  self.true_root_ids = nil
end

-- ========================================
-- USER COMMANDS
-- ========================================

function Variables4Plugin:setupCommands()
  self:registerCommands({
    {"Variables4Tree", function() self:OpenVariablesTree() end, {desc = "Open Variables4 tree popup"}},
    {"Variables4UpdateFrame", function() self:UpdateFrameCommand() end, {desc = "Update Variables4 current frame to top of stack"}},
    {"Variables4ClearFrame", function() self:ClearCurrentFrame() end, {desc = "Clear Variables4 current frame"}}
  })
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
  if not self.frame then
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
    local frame = self.frame
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
-- UI COORDINATION HELPERS
-- ========================================

-- Simple helper to eliminate repetitive render+update+cursor pattern
function Variables4Plugin:refreshTreeUI(target_node_id)
  self.tree:render()
  self:updatePopupTitle()
  if target_node_id then
    self:setCursorToNode(target_node_id)
  end
end

-- Simple node data access helpers
local function getNodeDataObject(node)
  return node._scope or node._variable
end

local function getNodeVariable(node)
  return node._variable
end

local function getNodeVariableRef(node)
  return node._variable and node._variable.ref
end

local function isNodeLazy(node)
  local var_ref = getNodeVariableRef(node)
  return var_ref and var_ref.presentationHint and var_ref.presentationHint.lazy and not node._lazy_resolved
end

-- Helper to safely get current node (eliminates guard+fetch+validate pattern)
function Variables4Plugin:getCurrentNodeSafely()
  if not self.tree then return nil end
  return self.tree:get_node()
end

-- Helper to safely get node by ID
function Variables4Plugin:getNodeSafely(node_id)
  if not self.tree then return nil end
  return self.tree.nodes.by_id[node_id]
end

-- Helper to create properly configured variable instance (eliminates 5-line creation ritual)
local function createVariableInstance(child, data_object, parent_node)
  local instance = child.ref and child or Variable.instanciate(data_object.scope or data_object, child)
  local var_ref = getNodeVariableRef(parent_node)
  if var_ref then instance._parent_var_ref = var_ref.variablesReference end
  instance.asNode = instance.asNode or Variable.asNode
  instance.variables = instance.variables or Variable.variables
  return instance
end

-- Simple async wrapper helper
function Variables4Plugin:runAsync(operation)
  NvimAsync.run(operation)
end

-- ========================================
-- FOCUS MODE HELPER METHODS
-- ========================================


-- Refined popup title update with simplified path generation
function Variables4Plugin:updatePopupTitle()
  if not (self.popup and self.popup.border and self.popup.border.text) then return end

  -- Quick path: if showing all roots, use default title
  if vim.deep_equal(self.tree.nodes.root_ids, self.true_root_ids) then
    self.popup.border.text.top = " Variables4 Debug Tree "
    self.popup:update_layout()
    return
  end

  -- Build viewport path from first root to its ancestors
  local path_parts = {}
  local current = self.tree.nodes.root_ids[1] and
      self.tree.nodes.by_id[self.tree.nodes.root_ids[1]]

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
    current = self.tree.nodes.by_id[parent_id]
  end

  -- Remove current level and build title
  table.remove(path_parts)
  local title = #path_parts > 0
      and " Variables4: " .. table.concat(path_parts, " → ") .. " "
      or " Variables4 Debug Tree "

  self.popup.border.text.top = title
  self.popup:update_layout()
end

-- Focus on a specific node by setting viewport to show it and its siblings
function Variables4Plugin:focusOnNode(node_id)
  local node = self:getNodeSafely(node_id)
  if not node then return end

  local parent_id = node:get_parent_id()
  local new_roots
  if parent_id then
    local parent_node = self.tree.nodes.by_id[parent_id]
    new_roots = (parent_node and parent_node:has_children()) and parent_node:get_child_ids() or { node_id }
  else
    new_roots = { node_id }
  end

  -- Inlined setViewportRoots logic
  self.tree.nodes.root_ids = new_roots
  self:refreshTreeUI()
  self.logger:debug("Viewport changed: focused on " .. (node.text or "unknown"))
end

-- ========================================
-- PATH AND VIEWPORT MANAGEMENT
-- ========================================

-- Check if a node is currently visible in the tree (crystallized inline)
function Variables4Plugin:isNodeVisible(node_id)
  -- Inline check without creating full visible_nodes array
  local function isVisible(check_id, root_ids)
    for _, root_id in ipairs(root_ids) do
      if root_id == check_id then return true end
      local root_node = self.tree.nodes.by_id[root_id]
      if root_node and root_node:is_expanded() and root_node:has_children() then
        if isVisible(check_id, root_node:get_child_ids()) then return true end
      end
    end
    return false
  end
  return isVisible(node_id, self.tree.nodes.root_ids)
end

-- Refined viewport adjustment with simplified logic
function Variables4Plugin:adjustViewportForNode(target_node_id)
  if self:isNodeVisible(target_node_id) then return false end

  local target_node = self.tree.nodes.by_id[target_node_id]
  if not target_node then return false end

  local parent_id = target_node:get_parent_id()

  -- No parent: show all roots
  if not parent_id then
    self.tree.nodes.root_ids = self.true_root_ids or self.tree.nodes.root_ids
    self.logger:debug("Viewport adjusted to show all roots")
    return true
  end

  -- Has parent: find appropriate level to show
  local parent_node = self.tree.nodes.by_id[parent_id]
  local grandparent_id = parent_node and parent_node:get_parent_id()

  if grandparent_id then
    -- Show parent and its siblings (children of grandparent)
    local grandparent = self.tree.nodes.by_id[grandparent_id]
    if grandparent and grandparent:has_children() then
      self.tree.nodes.root_ids = grandparent:get_child_ids()
      self.logger:debug("Viewport adjusted to show parent level and siblings")
      return true
    end
  end

  -- Fallback: show all roots
  self.tree.nodes.root_ids = self.true_root_ids or self.tree.nodes.root_ids
  self.logger:debug("Viewport adjusted to root level")
  return true
end

-- ========================================
-- OPERATION CONTEXT (Use-Case Optimization)
-- ========================================

-- Direct Navigation Methods: Eliminate TreeOperationContext indirection
-- These methods take the parameters they actually need rather than bundling them

function Variables4Plugin:navigateToNode(target_node_id, should_collapse)
  if not target_node_id or not self.tree then return false end

  -- Ensure target is visible
  if not self:isNodeVisible(target_node_id) then
    self:adjustViewportForNode(target_node_id)
  end

  -- Apply collapse if requested
  if should_collapse then
    local target_node = self.tree.nodes.by_id[target_node_id]
    if target_node and target_node:is_expanded() then
      target_node:collapse()
      self:collapseAllChildren(target_node)
    end
  end

  -- Render and position cursor
  self:refreshTreeUI(target_node_id)
  return true
end

function Variables4Plugin:drillIntoNode(node)
  if not self.tree then return end

  -- Check for lazy variables first
  if isNodeLazy(node) then
    return self:resolveLazyVariable(node)
  end

  -- Handle expandable nodes
  if node.expandable then
    if not node._children_loaded then
      return self:ExpandNodeAndNavigate(node)
    elseif not node:is_expanded() then
      node:expand()
      self:refreshTreeUI()
      self:moveToFirstChild(node)
    else
      self:moveToFirstChild(node)
    end
  end
  -- Leaf nodes: no action
end

function Variables4Plugin:expandVariableToSeeContents()
  local node = self:getCurrentNodeSafely()
  if node then
    return self:drillIntoNode(node)
  end
end

function Variables4Plugin:navigateToSibling(direction)
  local current_node = self:getCurrentNodeSafely()
  if not current_node then return end

  local target
  if direction == "next" then
    target = self:getVisibleNodeNeighbor(current_node, "next") or
        self:findNextLogicalSibling(current_node)
  else
    target = self:getVisibleNodeNeighbor(current_node, "previous") or current_node:get_parent_id()
  end

  if target then
    return self:navigateToNode(target, false)
  end
end

function Variables4Plugin:navigateToParentLevel()
  local current_node = self:getCurrentNodeSafely()
  if not current_node then return end

  local target = current_node:get_parent_id() or self:getViewportParent()
  if target then
    return self:navigateToNode(target, true) -- collapse when going up
  end
end

function Variables4Plugin:focusOnCurrentScope()
  local node = self:getCurrentNodeSafely()
  if node then
    local parent_id = node:get_parent_id()
    if parent_id then
      self:focusOnNode(parent_id)
    end
  end
end

-- ========================================
-- NAVIGATION CONCEPTS (Information Gems)
-- ========================================



-- Find next logical sibling when linear navigation reaches boundary
function Variables4Plugin:findNextLogicalSibling(current_node)
  local node_to_check = current_node
  while node_to_check do
    local parent_id = node_to_check:get_parent_id()
    if not parent_id then break end

    local parent_node = self.tree.nodes.by_id[parent_id]
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
function Variables4Plugin:getViewportParent()
  if not self.tree.nodes.root_ids or not self.true_root_ids then
    return nil
  end

  -- Check if we're in a focused view (not showing all roots)
  if #self.tree.nodes.root_ids == #self.true_root_ids then
    for i, id in ipairs(self.tree.nodes.root_ids) do
      if id ~= self.true_root_ids[i] then
        break
      end
      if i == #self.tree.nodes.root_ids then
        return nil -- Showing all roots
      end
    end
  end

  -- We're in a focused view - get parent of first root
  local first_root = self.tree.nodes.by_id[self.tree.nodes.root_ids[1]]
  return first_root and first_root:get_parent_id()
end

-- Unified visible node navigation (crystallized from 3 separate methods)
function Variables4Plugin:getVisibleNodeNeighbor(current_node, direction)
  local visible_nodes = {}

  -- Inline traversal (no separate getVisibleNodes method needed)
  local function traverse(node_id)
    local node = self.tree.nodes.by_id[node_id]
    if not node then return end
    table.insert(visible_nodes, node_id)
    if node:is_expanded() and node:has_children() then
      for _, child_id in ipairs(node:get_child_ids()) do
        traverse(child_id)
      end
    end
  end

  for _, root_id in ipairs(self.tree.nodes.root_ids) do
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
function Variables4Plugin:setCursorToNode(node_id)
  local node, linenr_start = self.tree:get_node(node_id)
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
function Variables4Plugin:moveToFirstChild(node)
  if node:is_expanded() and node:has_children() then
    local child_ids = node:get_child_ids()
    if child_ids and #child_ids > 0 then
      local first_child_id = child_ids[1]
      self:setCursorToNode(first_child_id)

      -- Log the drill-down action for better user feedback
      local first_child = self.tree.nodes.by_id[first_child_id]
      if first_child then
        self.logger:debug("Drilled down to: " .. (first_child.text or "unknown"))
      end
    end
  end
end

-- Simplified node expansion without callback complexity
function Variables4Plugin:ExpandNodeAndNavigate(node)
  if node._children_loaded then return end

  local data_object = getNodeDataObject(node)
  if not data_object or not data_object.variables then
    if not data_object then return end
    self.logger:warn("Data object has no variables() method: " .. (node.text or "unknown"))
    return
  end

  self:runAsync(function()
    local children = data_object:variables()
    local tree = self.tree

    if not tree then return end

    -- Build existing child name set for duplicate detection
    local existing_names = {}
    if node:has_children() then
      for _, child_id in ipairs(node:get_child_ids()) do
        local child = tree.nodes.by_id[child_id]
        local var_ref = getNodeVariableRef(child)
        if var_ref then
          existing_names[var_ref.name] = true
        end
      end
    end

    local added_count = 0
    if children and #children > 0 then
      for _, child in ipairs(children) do
        -- Prepare variable instance
        local instance = createVariableInstance(child, data_object, node)

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
      self:refreshTreeUI()
      self:moveToFirstChild(node) -- Direct call instead of callback
    else
      self.logger:debug("No new children for: " .. (node.text or "unknown"))
    end
  end)
end

-- Helper to recursively collapse all children of a node
function Variables4Plugin:collapseAllChildren(node)
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
    local child_node = self.tree.nodes.by_id[child_id]
    if child_node then
      -- Recursively collapse children of this child
      self:collapseAllChildren(child_node)
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
    local frame = self.frame
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
function Variables4Plugin:resolveLazyVariable(node)
  local variable = getNodeVariable(node)
  if not (variable and variable.ref) then return end

  local frame = variable.scope and variable.scope.frame
  if not (frame and frame.ref) then
    self.logger:warn("No frame available for lazy variable: " .. variable.ref.name)
    return
  end

  self:runAsync(function()
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
          self:ExpandNodeAndNavigate(node)
        elseif node:has_children() then
          self:moveToFirstChild(node)
        end
      end

      self.logger:debug("Resolved: " .. variable.ref.name .. " -> " .. (variable.ref.value or ""))
    else
      self.logger:debug("Failed to resolve: " .. variable.ref.name)
    end

    self:refreshTreeUI()
  end)
end

-- ========================================
-- TREE ASSEMBLY PIPELINE (Information Gem)
-- ========================================

-- Tree Assembly Pipeline: Transform debug data into interactive UI
local TreeAssembly = {}

-- Step 1: Prepare debug data for UI with auto-expansion of non-expensive scopes
function TreeAssembly.prepareData(scopes)
  return Collection.create({items = scopes})
    :map(function(scope)
      local scope_node = scope:asNode()
      
      -- Auto-expand non-expensive scopes by pre-loading their variables
      if not scope.ref.expensive then
        local variables = scope:variables()
        if variables and #variables > 0 then
          -- Create child nodes for all variables using Collection
          local children = Collection.create({items = variables})
            :map(function(variable) return variable:asNode() end)
            :toArray()
          
          -- Create expanded scope node with children
          scope_node = NuiTree.Node({
            id = string.format("scope:%s", scope.ref.name),
            text = "📁 " .. scope.ref.name,
            type = "scope",
            expandable = true,
            _scope = scope,
            _highlight = "Directory",
            _children_loaded = true,
          }, children)
          scope_node:expand() -- Start in expanded state
        end
      end
      
      return scope_node
    end)
    :toArray()
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

  -- Close existing tree if open
  if self.popup then
    self.popup:unmount()
  end

  -- Execute assembly pipeline
  local tree_nodes = TreeAssembly.prepareData(scopes)
  local popup = TreeAssembly.createPopup()
  local tree = TreeAssembly.createTree(popup, tree_nodes)

  -- Store UI state on plugin instance
  self.popup = popup
  self.tree = tree
  self.true_root_ids = vim.deepcopy(tree.nodes.root_ids)

  -- Setup tree appearance and behavior
  TreeAssembly.setupRendering(tree)
  
  -- Initialize with smart cursor positioning
  self:refreshTreeUI()
  local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
  local col = line:find("[%w_]") or 6
  vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), { 1, col - 1 })

  -- Setup navigation and controls
  self:setupTreeKeybindings()
end

function Variables4Plugin:setupTreeKeybindings()
  local map_options = { noremap = true, silent = true }

  -- Direct method calls using stored UI state
  self.popup:map("n", "h", function() self:navigateToParentLevel() end, map_options)
  self.popup:map("n", "j", function() self:navigateToSibling("next") end, map_options)
  self.popup:map("n", "k", function() self:navigateToSibling("previous") end, map_options)
  self.popup:map("n", "l", function() self:expandVariableToSeeContents() end, map_options)
  self.popup:map("n", "<CR>", function() self:expandVariableToSeeContents() end, map_options) -- Add Enter key support

  -- Controls
  self.popup:map("n", "q", function() self:closeTree() end, map_options)
  self.popup:map("n", "<Esc>", function() self:closeTree() end, map_options)
  self.popup:map("n", "f", function() self:focusOnCurrentScope() end, map_options)

  -- Help
  self.popup:map("n", "?", function()
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
