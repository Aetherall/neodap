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
      Logger.get("Variables4"):info("Found lazy variable: " .. self.ref.name .. " with hint: " .. vim.inspect(self.ref.presentationHint))
    end
  end
  
  -- Debug: Log getter functions to see if they should be marked as lazy
  if self.ref.value and type(self.ref.value) == "string" and self.ref.value:match("^ƒ get%(%)") then
    Logger.get("Variables4"):debug("Found getter function (potential lazy var): " .. self.ref.name .. " = " .. self.ref.value:sub(1, 50))
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
  INACTIVE = "inactive",    -- No debug session
  ACTIVE = "active",       -- Session running but not stopped
  STOPPED = "stopped",     -- Session stopped at breakpoint
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


-- Get a display string for the current viewport path
function Variables4Plugin:getViewportPathString(tree)
  -- If showing all roots, no path
  if tree.nodes.root_ids and self.true_root_ids then
    local showing_all_roots = true
    if #tree.nodes.root_ids == #self.true_root_ids then
      for i, id in ipairs(tree.nodes.root_ids) do
        if id ~= self.true_root_ids[i] then
          showing_all_roots = false
          break
        end
      end
    else
      showing_all_roots = false
    end
    
    if showing_all_roots then
      return nil  -- No path, showing root level
    end
  end
  
  -- Get the first root node to determine the viewport level
  local first_root_id = tree.nodes.root_ids and tree.nodes.root_ids[1]
  if not first_root_id then return nil end
  
  local first_root = tree.nodes.by_id[first_root_id]
  if not first_root then return nil end
  
  -- Build path from true root to current viewport
  local path_parts = {}
  local current = first_root
  
  while current do
    -- Extract simple name from node text
    local name = "?"
    if current.text then
      -- For variables: "icon name: value" format, extract name
      local colon_pos = current.text:find(": ")
      if colon_pos then
        local name_part = current.text:sub(1, colon_pos - 1)
        local space_pos = name_part:find(" ")
        name = space_pos and name_part:sub(space_pos + 1) or name_part
      else
        -- For scopes: "📁 ScopeName" format, extract name
        name = current.text:match("📁%s*(.+)") or current.text
      end
    end
    
    table.insert(path_parts, 1, name)
    
    -- Move to parent
    local parent_id = current:get_parent_id()
    if not parent_id then
      break
    end
    current = tree.nodes.by_id[parent_id]
  end
  
  -- Remove the last element (which is the current viewport level)
  table.remove(path_parts)
  
  if #path_parts > 0 then
    return table.concat(path_parts, " → ")
  else
    return nil
  end
end


-- Update popup title to show current viewport path
function Variables4Plugin:updatePopupTitle(tree, popup)
  if not popup or not popup.border or not popup.border.text then
    return
  end
  
  local viewport_path = self:getViewportPathString(tree)
  if viewport_path then
    popup.border.text.top = " Variables4: " .. viewport_path .. " "
  else
    popup.border.text.top = " Variables4 Debug Tree "
  end
  popup:update_layout()
end

-- Focus on a specific node by setting viewport to show it and its siblings
function Variables4Plugin:focusOnNode(tree, popup, node_id)
  local node = tree.nodes.by_id[node_id]
  if not node then return end
  
  local parent_id = node:get_parent_id()
  if parent_id then
    -- Focus on this level - show node and its siblings
    local parent_node = tree.nodes.by_id[parent_id]
    if parent_node and parent_node:has_children() then
      tree.nodes.root_ids = parent_node:get_child_ids()
    else
      tree.nodes.root_ids = { node_id }
    end
  else
    -- Node is at root level - focus on just this node
    tree.nodes.root_ids = { node_id }
  end
  
  tree:render()
  self:updatePopupTitle(tree, popup)
  self.logger:debug("Focused viewport on: " .. (node.text or "unknown"))
end

-- Viewport focus toggle: zoom in/out based on current view
function Variables4Plugin:toggleViewportFocus(tree, popup)
  local current_node = tree:get_node()
  if not current_node then return end
  
  -- Strategy: Focus on parent of current node, or zoom out if can't focus deeper
  local parent_id = current_node:get_parent_id()
  
  if parent_id then
    -- Check if we're already focused at the parent level
    local already_focused_here = false
    if tree.nodes.root_ids then
      -- Check if parent's children are the current roots
      local parent_node = tree.nodes.by_id[parent_id]
      if parent_node and parent_node:has_children() then
        local parent_children = parent_node:get_child_ids()
        if #parent_children == #tree.nodes.root_ids then
          already_focused_here = true
          for i, child_id in ipairs(parent_children) do
            if child_id ~= tree.nodes.root_ids[i] then
              already_focused_here = false
              break
            end
          end
        end
      end
    end
    
    if already_focused_here then
      -- Already focused at this level, zoom out one level
      local grandparent_id = tree.nodes.by_id[parent_id]:get_parent_id()
      if grandparent_id then
        self:focusOnNode(tree, popup, parent_id)
      else
        -- Parent is at root, return to full root view
        tree.nodes.root_ids = self.true_root_ids
        tree:render()
        self:updatePopupTitle(tree, popup)
      end
    else
      -- Focus on parent level
      self:focusOnNode(tree, popup, parent_id)
    end
  else
    -- Current node is at root level
    -- Check if we're showing all roots or focused on this one
    if #tree.nodes.root_ids == 1 and tree.nodes.root_ids[1] == current_node:get_id() then
      -- Currently focused on just this root, expand to show all
      tree.nodes.root_ids = self.true_root_ids
      tree:render()
      self:updatePopupTitle(tree, popup)
    else
      -- Focus on just this root node
      tree.nodes.root_ids = { current_node:get_id() }
      tree:render()
      self:updatePopupTitle(tree, popup)
    end
  end
end


-- ========================================
-- PATH AND VIEWPORT MANAGEMENT
-- ========================================

-- Get the full path from root to a node as an array of node IDs
function Variables4Plugin:getNodePath(tree, node_id)
  local path = {}
  local current_id = node_id
  
  while current_id do
    table.insert(path, 1, current_id)  -- Insert at beginning to build path from root
    local node = tree.nodes.by_id[current_id]
    if not node then break end
    current_id = node:get_parent_id()
  end
  
  return path
end

-- Check if a node is currently visible in the tree
function Variables4Plugin:isNodeVisible(tree, node_id)
  local visible_nodes = self:getVisibleNodes(tree)
  for _, visible_id in ipairs(visible_nodes) do
    if visible_id == node_id then
      return true
    end
  end
  return false
end

-- Adjust viewport to ensure a node is visible by setting appropriate root_ids
function Variables4Plugin:adjustViewportForNode(tree, target_node_id)
  -- If node is already visible, no adjustment needed
  if self:isNodeVisible(tree, target_node_id) then
    return false  -- No adjustment made
  end
  
  -- Get the path to the target node
  local path = self:getNodePath(tree, target_node_id)
  if #path == 0 then return false end
  
  -- Find the appropriate level to show: the parent of the target and its siblings
  local target_node = tree.nodes.by_id[target_node_id]
  if not target_node then return false end
  
  local parent_id = target_node:get_parent_id()
  if parent_id then
    -- Set root to show parent and its siblings
    local grandparent_node = tree.nodes.by_id[parent_id]
    local grandparent_id = grandparent_node and grandparent_node:get_parent_id()
    
    if grandparent_id then
      -- Show all children of grandparent (parent and its siblings)
      local grandparent = tree.nodes.by_id[grandparent_id]
      if grandparent and grandparent:has_children() then
        tree.nodes.root_ids = grandparent:get_child_ids()
        self.logger:debug("Viewport adjusted to show parent level and siblings")
        return true
      end
    else
      -- Parent is at root level, show all root nodes
      tree.nodes.root_ids = self.true_root_ids or tree.nodes.root_ids
      self.logger:debug("Viewport adjusted to root level")
      return true
    end
  else
    -- Target is at root level, ensure all roots are visible
    tree.nodes.root_ids = self.true_root_ids or tree.nodes.root_ids
    self.logger:debug("Viewport adjusted to show all roots")
    return true
  end
  
  return false
end

-- ========================================
-- NAVIGATION CONCEPTS (Information Gems)
-- ========================================

-- Navigation Intent: The semantic meaning behind a navigation action
local NavigationIntent = {
  LINEAR_FORWARD = "linear_forward",    -- j key: traverse down through visible nodes
  LINEAR_BACKWARD = "linear_backward",  -- k key: traverse up through visible nodes  
  HIERARCHICAL_UP = "hierarchical_up",  -- h key: jump to parent level
  HIERARCHICAL_DOWN = "hierarchical_down", -- l key: drill into children
}

-- Perform navigation based on intent, handling viewport and tree state automatically
function Variables4Plugin:navigate(tree, popup, intent)
  local current_node = tree:get_node()
  if not current_node then return end
  
  if intent == NavigationIntent.LINEAR_FORWARD then
    local target = self:getNextVisibleNode(tree, current_node) or self:findNextLogicalSibling(tree, current_node)
    if target then self:reconcileViewportAndNavigate(tree, popup, target, false) end
    
  elseif intent == NavigationIntent.LINEAR_BACKWARD then
    local target = self:getPreviousVisibleNode(tree, current_node) or current_node:get_parent_id()
    if target then self:reconcileViewportAndNavigate(tree, popup, target, false) end
    
  elseif intent == NavigationIntent.HIERARCHICAL_UP then
    local target = current_node:get_parent_id() or self:getViewportParent(tree)
    if target then self:reconcileViewportAndNavigate(tree, popup, target, true) end
    
  elseif intent == NavigationIntent.HIERARCHICAL_DOWN then
    self:drillIntoNode(tree, popup, current_node)
  end
end

-- Core viewport reconciliation: ensure target is visible and navigate to it
function Variables4Plugin:reconcileViewportAndNavigate(tree, popup, target_node_id, should_collapse_target)
  if not target_node_id then return false end
  
  -- Adjust viewport if needed
  local viewport_adjusted = false
  if not self:isNodeVisible(tree, target_node_id) then
    if self:adjustViewportForNode(tree, target_node_id) then
      viewport_adjusted = true
    end
  end
  
  -- Collapse target node if requested (for h key behavior)
  if should_collapse_target then
    local target_node = tree.nodes.by_id[target_node_id]
    if target_node then
      if target_node:is_expanded() then
        target_node:collapse()
      end
      self:collapseAllChildren(tree, target_node)
    end
  end
  
  -- Render changes
  tree:render()
  
  -- Update title if viewport changed
  if viewport_adjusted then
    self:updatePopupTitle(tree, popup)
  end
  
  -- Move cursor to target
  self:setCursorToNode(tree, target_node_id)
  
  return true
end

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

-- Drill into a node (l key behavior) - handles expansion, lazy loading, and navigation
function Variables4Plugin:drillIntoNode(tree, popup, node)
  -- Check for lazy variable resolution first
  if node._variable and node._variable.ref and node._variable.ref.presentationHint then
    local hint = node._variable.ref.presentationHint
    if hint.lazy and not node._lazy_resolved then
      self:resolveLazyVariable(tree, node, popup)
      return
    end
  end

  -- Expand and navigate to first child
  if not node:is_expanded() and node.expandable then
    if not node._children_loaded then
      self:ExpandNodeWithCallback(tree, node, popup, function()
        self:moveToFirstChild(tree, node)
      end)
    else
      node:expand()
      tree:render()
      self:moveToFirstChild(tree, node)
    end
  elseif node:is_expanded() and node:has_children() then
    self:moveToFirstChild(tree, node)
  end
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

-- Get all visible nodes in display order (depth-first traversal)
function Variables4Plugin:getVisibleNodes(tree)
  local visible_nodes = {}
  
  -- Helper function to traverse nodes recursively
  local function traverse(node_id)
    local node = tree.nodes.by_id[node_id]
    if not node then return end
    
    table.insert(visible_nodes, node_id)
    
    -- If node is expanded, traverse its children
    if node:is_expanded() and node:has_children() then
      local child_ids = node:get_child_ids()
      for _, child_id in ipairs(child_ids) do
        traverse(child_id)
      end
    end
  end
  
  -- Start with root nodes
  for _, root_id in ipairs(tree.nodes.root_ids) do
    traverse(root_id)
  end
  
  return visible_nodes
end

-- Get the next visible node after the current one
function Variables4Plugin:getNextVisibleNode(tree, current_node)
  local visible_nodes = self:getVisibleNodes(tree)
  local current_id = current_node:get_id()
  
  for i, node_id in ipairs(visible_nodes) do
    if node_id == current_id and i < #visible_nodes then
      return visible_nodes[i + 1]
    end
  end
  
  return nil -- Already at last node
end

-- Get the previous visible node before the current one
function Variables4Plugin:getPreviousVisibleNode(tree, current_node)
  local visible_nodes = self:getVisibleNodes(tree)
  local current_id = current_node:get_id()
  
  for i, node_id in ipairs(visible_nodes) do
    if node_id == current_id and i > 1 then
      return visible_nodes[i - 1]
    end
  end
  
  return nil -- Already at first node
end

-- Helper to set cursor to a specific node using vim API with smart column positioning
function Variables4Plugin:setCursorToNode(tree, node_id)
  -- Smart but simple cursor positioning based on the line content
  local node, linenr_start, linenr_end = tree:get_node(node_id)
  if node and linenr_start then
    local winid = vim.api.nvim_get_current_win()
    
    -- Get the actual line content to find where the name starts
    local line_content = vim.api.nvim_buf_get_lines(0, linenr_start - 1, linenr_start, false)[1] or ""
    local name_start_col = self:findNameStartColumn(line_content)
    
    vim.api.nvim_win_set_cursor(winid, { linenr_start, name_start_col })
    self.logger:debug(string.format("Set cursor to line %d, column %d (name start)", linenr_start, name_start_col))
  else
    -- Fallback: use column 4 as default
    local current_line = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())[1]
    vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), { current_line, 4 })
    self.logger:debug("Node lookup failed, set cursor to column 4 on current line")
  end
end

-- Find where the actual name starts in a tree line
function Variables4Plugin:findNameStartColumn(line_content)
  -- Simple and effective approach: look for the first letter/word after icons
  -- Based on typical lines like: "│▶ 📁  Local: testVariables"
  
  -- Strategy: Find where text starts after all the tree decorations
  -- Skip tree chars (│╰─), arrows (▶▼), emojis, and spaces
  local pos = 0
  local len = #line_content
  
  -- Skip initial tree characters and arrows
  while pos < len do
    local char = line_content:sub(pos + 1, pos + 1)
    local byte = string.byte(char)
    
    -- Skip known tree characters: │ ╰ ─ ▶ ▼
    if char == "│" or char == "╰" or char == "─" or char == "▶" or char == "▼" or char == " " then
      pos = pos + 1
    -- Skip UTF-8 emoji characters (usually have high byte values)
    elseif byte and byte > 127 then
      pos = pos + 1
    -- Found a regular character - this should be the start of the name
    elseif char:match("[%w_]") then
      return pos  -- Return 0-based position for vim cursor
    else
      pos = pos + 1
    end
  end
  
  -- Fallback: if we can't find a good position, use a reasonable default
  return 6  -- Approximately where names usually start
end

-- Simple cursor positioning: just put cursor at column 4 for most items
-- This covers the common case of "▶ 📁  Name" where name starts at column 4

function Variables4Plugin:navigateToFirstChild(tree, popup)
  self:navigate(tree, popup, NavigationIntent.HIERARCHICAL_DOWN)
end

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

-- Enhanced ExpandNode with callback support for complete l-key behavior
function Variables4Plugin:ExpandNodeWithCallback(tree, node, popup, callback)
  if node._children_loaded then
    return -- Already loaded
  end

  -- Get the underlying data object (scope or variable)
  local data_object = node._scope or node._variable
  if not data_object then
    return -- No data object found
  end

  -- Both scopes and variables should have a variables() method now
  if not data_object.variables then
    self.logger:warn("Data object has no variables() method: " .. (node.text or "unknown"))
    return
  end

  -- Load children asynchronously
  NvimAsync.run(function()
    local children = data_object:variables()

    if children and #children > 0 then
      -- Check if node already has children to prevent duplication
      local existing_child_ids = node:has_children() and node:get_child_ids() or {}
      local existing_child_names = {}
      
      -- Build set of existing child names to detect duplicates
      for _, child_id in ipairs(existing_child_ids) do
        local existing_child = tree.nodes.by_id[child_id]
        if existing_child and existing_child._variable and existing_child._variable.ref then
          existing_child_names[existing_child._variable.ref.name] = true
        end
      end
      
      -- Create child nodes and add them to the tree, skipping duplicates
      local new_children_added = 0
      for _, child in ipairs(children) do
        local variable_instance = self:ensureVariableWrapper(child, data_object, node)
        
        -- Skip if this child already exists (prevents self-evaluation duplication)
        if not existing_child_names[variable_instance.ref.name] then
          local child_node = variable_instance:asNode()
          child_node._variable = variable_instance
          tree:add_node(child_node, node:get_id())
          new_children_added = new_children_added + 1
        else
          self.logger:debug("Skipping duplicate child: " .. variable_instance.ref.name)
        end
      end

      node._children_loaded = true

      self.logger:debug("Loaded " .. new_children_added .. " new children (skipped " .. (#children - new_children_added) .. " duplicates) for: " .. (node.text or "unknown"))

      -- Expand the node now that children are loaded
      node:expand()

      -- Re-render the tree
      tree:render()
      
      -- Execute callback (e.g., move to first child)
      if callback then
        callback()
      end
    else
      -- Mark as loaded even if no children, to avoid repeated attempts
      node._children_loaded = true
      self.logger:debug("No children found for: " .. (node.text or "unknown"))
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

function Variables4Plugin:navigateToParent(tree, popup)
  self:navigate(tree, popup, NavigationIntent.HIERARCHICAL_UP)
end

-- Note: Removed checkAndResolveLazyAfterNavigation helper
-- j/k navigation is now pure linear movement without auto-drill behavior
-- Lazy resolution and focus updates only happen on intentional l/h navigation

-- Simplified navigation methods using the unified intent-based system
function Variables4Plugin:navigateDown(tree, popup)
  self:navigate(tree, popup, NavigationIntent.LINEAR_FORWARD)
end

function Variables4Plugin:navigateUp(tree, popup)
  self:navigate(tree, popup, NavigationIntent.LINEAR_BACKWARD)
end


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
-- UNIFIED EXPANSION LOGIC
-- ========================================

-- Helper function to ensure a child is wrapped as a proper Variable instance
function Variables4Plugin:ensureVariableWrapper(child, data_object, parent_node)
  local variable_instance

  if child.ref then
    -- This is already a wrapped Variable API object
    variable_instance = child
  else
    -- This is a raw DAP variable object - wrap it
    local parent_scope = data_object.scope or data_object -- Variable has scope, Scope is itself
    variable_instance = Variable.instanciate(parent_scope, child)
  end

  -- Set parent context for hierarchical ID generation
  if parent_node and parent_node._variable and parent_node._variable.ref.variablesReference then
    variable_instance._parent_var_ref = parent_node._variable.ref.variablesReference
  end

  -- Ensure child has asNode method (in case it's a new Variable instance)
  if not variable_instance.asNode then
    -- Apply asNode method to new Variable instances
    variable_instance.asNode = Variable.asNode
    if not variable_instance.variables then
      variable_instance.variables = Variable.variables
    end
  end

  return variable_instance
end


-- ========================================
-- LAZY VARIABLE RESOLUTION
-- ========================================

-- Resolve a lazy variable by evaluating it and replacing the node
---@param tree NuiTree
---@param node NuiTreeNode
---@param popup any
function Variables4Plugin:resolveLazyVariable(tree, node, popup)
  if not node._variable or not node._variable.ref then
    return
  end

  local variable = node._variable
  local variable_name = variable.ref.name

  -- Get the frame for evaluation context
  local frame = variable.scope and variable.scope.frame
  if not frame or not frame.ref then
    self.logger:warn("No frame available for lazy variable evaluation: " .. variable_name)
    return
  end

  -- Use the Variable's resolve method to get the actual value
  NvimAsync.run(function()
    self.logger:debug("Resolving lazy variable: " .. variable_name)
    
    -- Call the resolve method which updates the variable's ref in-place
    local resolved = variable:resolve()
    
    if resolved then
      self.logger:debug("Lazy variable resolved successfully: " .. variable_name)
      
      -- After resolution, we need to update the node's display
      -- Clear the cached node so asNode() creates a new one with updated values
      variable._node = nil
      
      -- Create a new node with the resolved values
      local resolved_node = variable:asNode()
      
      -- Update the existing node's properties to reflect the resolved state
      node.text = resolved_node.text
      node.expandable = resolved_node.expandable
      node._highlight = resolved_node._highlight
      
      -- Mark as resolved so we don't re-resolve it
      node._lazy_resolved = true
      
      -- If the resolved variable is expandable, mark children as not loaded
      if node.expandable then
        node._children_loaded = false
      end
      
      self.logger:debug("Resolved lazy variable: " .. variable_name .. " -> " .. (variable.ref.value or ""))
      
      -- After successful resolution, continue with expansion if the variable is expandable
      if node.expandable and not node._children_loaded then
        self:ExpandNodeWithCallback(tree, node, popup, function()
          self:moveToFirstChild(tree, node)
          -- No automatic focus updates - focus is manual only
        end)
      elseif node.expandable and node:has_children() then
        -- If already has children, just move to first child
        self:moveToFirstChild(tree, node)
        -- No automatic focus updates - focus is manual only
      else
        -- Variable resolved but not expandable - no action needed
        -- No automatic focus updates - focus is manual only
      end
    else
      self.logger:debug("Failed to resolve lazy variable: " .. variable_name)
    end
    
    -- Re-render the tree to show the updated values
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

  -- Initialize cursor position
  self:initializeCursor()

  -- Setup navigation and controls
  self:setupTreeKeybindings(popup, tree)
end

-- Helper methods for tree assembly
function Variables4Plugin:initializeCursor()
  local winid = vim.api.nvim_get_current_win()
  local line_content = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
  local name_start_col = self:findNameStartColumn(line_content)
  vim.api.nvim_win_set_cursor(winid, { 1, name_start_col })
end

function Variables4Plugin:setupTreeKeybindings(popup, tree)
  local map_options = { noremap = true, silent = true }

  -- Navigation
  popup:map("n", "h", function() self:navigateToParent(tree, popup) end, map_options)
  popup:map("n", "j", function() self:navigateDown(tree, popup) end, map_options)
  popup:map("n", "k", function() self:navigateUp(tree, popup) end, map_options)
  popup:map("n", "l", function() self:navigateToFirstChild(tree, popup) end, map_options)

  -- Controls
  popup:map("n", "q", function() popup:unmount() end, map_options)
  popup:map("n", "<Esc>", function() popup:unmount() end, map_options)
  popup:map("n", "f", function() self:toggleViewportFocus(tree, popup) end, map_options)

  -- Help
  popup:map("n", "?", function()
    print("Variables4 Tree Controls:")
    print("Navigation (Path-aware with automatic viewport adjustment):")
    print("  j/k: Navigate down/up through tree")
    print("  h: Jump to parent (collapses parent node)")
    print("  l: Drill into first child (expands & resolves lazy vars)")
    print("Viewport Management:")  
    print("  f: Toggle viewport focus")
    print("Other: q/Esc: Close popup, ?: Show this help")
    print("The tree automatically adjusts its viewport as you navigate.")
  end, map_options)
end

-- ========================================
-- MODULE EXPORTS
-- ========================================

return Variables4Plugin
