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
---@field focus_mode_active boolean
---@field focus_node_id? string
---@field original_scopes? any[]
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

  -- Initialize focus mode state
  self.focus_mode_active = false
  self.focus_node_id = nil
  self.original_scopes = nil
  self.focus_history = {} -- Track focus drill-down history for smart defocusing

  -- Set up event handlers
  self:setupEventHandlers()

  -- Create commands
  self:setupCommands()

  self.logger:info("Variables4 plugin initialized")
end

-- ========================================
-- VALUE FORMATTING AND VISUAL ENHANCEMENTS
-- ========================================

-- DAP type to icon mapping for visual clarity
local TYPE_ICONS = {
  -- JavaScript primitives
  string = "󰉿", -- String icon
  number = "󰎠", -- Number icon
  boolean = "◐", -- Boolean icon
  undefined = "󰟢", -- Undefined icon
  ['nil'] = "∅", -- Null icon
  null = "∅", -- Null icon (alternative)

  -- Complex types
  object = "󰅩", -- Object icon
  array = "󰅪", -- Array icon
  ['function'] = "󰊕", -- Function icon

  -- Special types
  date = "󰃭", -- Calendar icon
  regexp = "󰑑", -- Regex icon
  map = "󰘣", -- Map icon
  set = "󰘦", -- Set icon

  -- Default fallback
  default = "󰀬", -- Generic icon
}

-- DAP type to treesitter highlight mapping
local TYPE_HIGHLIGHTS = {
  -- JavaScript primitives (match treesitter highlights)
  string = "String",      -- @string
  number = "Number",      -- @number
  boolean = "Boolean",    -- @boolean
  undefined = "Constant", --kk @constant.builtin
  ['nil'] = "Constant",   -- @constant.builtin
  null = "Constant",      -- @constant.builtin

  -- Complex types
  object = "Structure",      -- @structure / Type
  array = "Structure",       -- @structure
  ['function'] = "Function", -- @function

  -- Special types
  date = "Special",  -- @special
  regexp = "String", -- @string.regex
  map = "Type",      -- @type
  set = "Type",      -- @type

  -- Default
  default = "Identifier", -- @variable
}

-- Constants for formatting (reduced to prevent line wrapping)
local TRUNCATION_LENGTHS = {
  default = 40,      -- Reduced from 60
  ['function'] = 25, -- Reduced from 40
  string = 35,       -- Reduced from 50
  signature = 20,    -- Reduced from 30
}

-- Unified type detection - returns icon, highlight, and whether it's an array
local function getTypeInfo(ref)
  if not ref or not ref.type then
    return TYPE_ICONS.default, TYPE_HIGHLIGHTS.default, false
  end

  local var_type = ref.type:lower()
  local is_array = var_type == "object" and ref.value and ref.value:match("^%[.*%]$")

  if is_array then
    return TYPE_ICONS.array, TYPE_HIGHLIGHTS.array, true
  end

  local icon = TYPE_ICONS[var_type] or TYPE_ICONS.default
  local highlight = TYPE_HIGHLIGHTS[var_type] or TYPE_HIGHLIGHTS.default

  return icon, highlight, false
end

-- Format variable value with smart truncation and inlining
local function formatVariableValue(ref)
  if not ref then return "undefined" end

  local value = ref.value or ""
  local var_type = ref.type or "default"

  -- Handle multiline values by inlining
  if type(value) == "string" then
    -- Replace actual newlines and carriage returns
    value = value:gsub("[\r\n]+", " ")
    -- Replace literal \n, \r, \t characters (escaped sequences)
    value = value:gsub("\\[nrt]", " ")
    -- Replace multiple spaces with single spaces
    value = value:gsub("%s+", " ")
    -- Trim leading/trailing whitespace
    value = value:match("^%s*(.-)%s*$") or ""

    -- Smart truncation based on type
    local max_length = TRUNCATION_LENGTHS[var_type] or TRUNCATION_LENGTHS.default

    if #value > max_length then
      value = value:sub(1, max_length - 3) .. "..."
    end
  end

  -- Type-specific formatting
  if var_type == "string" then
    return string.format('"%s"', value)
  elseif var_type == "function" and value:match("^function") then
    -- Extract function signature only
    local signature = value:match("^function%s*([^{]*)")
    if signature then
      local max_sig = TRUNCATION_LENGTHS.signature
      return "ƒ " .. signature:gsub("%s+", " "):sub(1, max_sig) .. (signature:len() > max_sig and "..." or "")
    end
  elseif var_type == "object" and ref.variablesReference and ref.variablesReference > 0 then
    -- Show object preview instead of [object Object]
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

---@class (partial) api.Variable
---@field _node NuiTree.Node?
---@field asNode fun(self: Variable): NuiTree.Node
---@field variables fun(self: Variable): api.Variable[]?
function Variable:asNode()
  if self._node then return self._node end

  -- Add safety checks for variable structure
  if not self.ref then
    error("Variable:asNode() called on variable with no ref property")
  end

  if not self.ref.name then
    error("Variable:asNode() called on variable with no name in ref")
  end

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

  -- Generate hierarchical ID to handle recursive references
  -- Include parent context to ensure uniqueness
  local node_id
  if self._parent_var_ref then
    -- This is a nested variable: use parent's variablesReference as context (PRIORITY)
    node_id = string.format("var:%s:%s", self._parent_var_ref, self.ref.name)
  elseif self.scope and self.scope.ref and self.scope.ref.name then
    -- This is a scope-level variable: use scope name as context
    node_id = string.format("var:%s:%s", self.scope.ref.name, self.ref.name)
  else
    -- Fallback to simple ID (shouldn't happen in normal cases)
    node_id = string.format("var:%s", self.ref.name)
  end

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
  if not self.ref then
    error("Variable:variables() called on variable with no ref property")
  end

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
  -- Add variables method if not present (same fix as Variables3/Variables4)
  if not ScopeClass.variables and BaseScope.variables then
    ScopeClass.variables = BaseScope.variables
  end
end

for _, ScopeClass in ipairs(scope_classes) do
  -- Add method if not present (same fix as Variables3/Variables4)
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
-- HELPER METHODS
-- ========================================

function Variables4Plugin:requireActiveFrame(context_message)
  if not self.current_frame then
    print("No debug session active - " .. context_message)
    return false
  end
  return true
end

function Variables4Plugin:getCurrentScopesAndVariables()
  if not self:requireActiveFrame("cannot access variables") then
    return nil
  end

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
end

-- ========================================
-- FOCUS MODE HELPER METHODS
-- ========================================

-- Find the n-2 parent of the current node (or appropriate ancestor)
function Variables4Plugin:findNMinus2Parent(tree, current_node)
  if not current_node then
    return nil
  end

  -- Walk up the parent chain to find n-2 parent
  local target_node = current_node
  local levels_up = 0
  local max_levels = 2 -- n-2 means go up 2 levels

  while target_node and levels_up < max_levels do
    local parent_id = target_node:get_parent_id()
    if not parent_id then
      break -- Reached root
    end
    
    local parent_node = tree.nodes.by_id[parent_id]
    if not parent_node then
      break -- Parent not found
    end
    
    target_node = parent_node
    levels_up = levels_up + 1
  end

  -- If we couldn't go up 2 levels, use whatever we found
  -- This handles cases where we're close to the root
  return target_node
end

-- Get a human-readable breadcrumb path for the focus node
function Variables4Plugin:getFocusBreadcrumb(tree, focus_node)
  if not focus_node then
    return "Full Tree"
  end

  local breadcrumb_parts = {}
  local current = focus_node

  -- Build breadcrumb by walking up the tree
  while current do
    -- Extract the display name from the node text
    local display_name = "unknown"
    if current.text then
      -- For variables: "icon name: value" format, extract name
      local colon_pos = current.text:find(": ")
      if colon_pos then
        local name_part = current.text:sub(1, colon_pos - 1)
        local space_pos = name_part:find(" ")
        if space_pos then
          display_name = name_part:sub(space_pos + 1)
        else
          display_name = name_part
        end
      else
        -- For scopes: "📁 ScopeName" format, extract name
        if current.text:sub(1, 2) == "📁" then
          display_name = current.text:sub(3):gsub("^%s+", "") -- Remove leading spaces
        else
          display_name = current.text
        end
      end
    end

    table.insert(breadcrumb_parts, 1, display_name) -- Insert at beginning

    -- Move to parent
    local parent_id = current:get_parent_id()
    if not parent_id then
      break
    end
    current = tree.nodes.by_id[parent_id]
  end

  return "Focus: " .. table.concat(breadcrumb_parts, ".")
end

-- Store original tree state for focus mode restoration  
function Variables4Plugin:storeOriginalTreeState(tree)
  return {
    root_ids = vim.deepcopy(tree.nodes.root_ids)
  }
end

-- Restore original tree state from stored data
function Variables4Plugin:restoreOriginalTreeState(tree, stored_state)
  tree.nodes.root_ids = stored_state.root_ids
end

-- Enter focus mode: change tree root to n-2 parent while preserving all node state
function Variables4Plugin:enterFocusMode(tree, popup)
  local current_node = tree:get_node()
  if not current_node then
    print("No node selected for focus mode")
    return false
  end

  -- Find the n-2 parent (or appropriate ancestor)
  local focus_node = self:findNMinus2Parent(tree, current_node)
  if not focus_node then
    print("Cannot determine focus node")
    return false
  end

  -- Don't focus if we're already at root level
  if focus_node:get_id() == current_node:get_id() then
    print("Already at top level - cannot focus further")
    return false
  end

  -- Store current state for restoration (only if not already in focus mode)
  local was_already_focused = self.focus_mode_active
  if not self.focus_mode_active then
    self.original_tree_state = self:storeOriginalTreeState(tree)
    self.focus_mode_active = true
  end
  
  -- Update focus node ID
  self.focus_node_id = current_node:get_id()

  -- Change tree root to focus node (preserves all node state and children)
  tree.nodes.root_ids = { focus_node:get_id() }

  -- Update popup title with breadcrumb
  if popup and popup.border and popup.border.text then
    local breadcrumb = self:getFocusBreadcrumb(tree, focus_node)
    popup.border.text.top = " " .. breadcrumb .. " "
    popup:update_layout() -- Refresh the popup to show new title
  end

  -- Re-render the tree
  tree:render()

  local action = was_already_focused and "Re-focused" or "Focused"
  print(action .. " on: " .. (focus_node.text or "unknown"))
  self.logger:debug(action .. " focus mode with root: " .. (focus_node.text or "unknown"))
  return true
end

-- Exit focus mode: restore original tree root nodes
function Variables4Plugin:exitFocusMode(tree, popup)
  if not self.focus_mode_active then
    print("Not in focus mode - nothing to reset")
    return false
  end

  -- Restore original tree state
  if self.original_tree_state then
    self:restoreOriginalTreeState(tree, self.original_tree_state)
  else
    print("Cannot restore tree - no original state saved")
    return false
  end

  -- Restore popup title
  if popup and popup.border and popup.border.text then
    popup.border.text.top = " Variables4 Debug Tree "
    popup:update_layout()
  end

  -- Clear focus mode state
  self.focus_mode_active = false
  self.focus_node_id = nil
  self.original_tree_state = nil
  self.focus_history = {} -- Clear focus history

  -- Re-render the tree
  tree:render()

  print("Reset to full tree view")
  self.logger:debug("Exited focus mode - restored original tree")
  return true
end

-- Toggle focus mode on/off
function Variables4Plugin:toggleFocusMode(tree, popup)
  if self.focus_mode_active then
    return self:exitFocusMode(tree, popup)
  else
    return self:enterFocusMode(tree, popup)
  end
end

-- Auto-focus on expanded node during focus mode navigation
function Variables4Plugin:autoFocusOnExpansion(tree, expanded_node, popup)
  if not self.focus_mode_active or not expanded_node then
    return
  end

  -- Don't auto-focus if the expanded node has no children
  if not expanded_node:has_children() then
    return
  end

  -- Track the current focus in history before drilling down
  local current_focus_id = self.focus_node_id or tree.nodes.root_ids[1]
  if current_focus_id then
    table.insert(self.focus_history, current_focus_id)
  end

  -- Update focus node ID to the expanded node
  self.focus_node_id = expanded_node:get_id()

  -- Change tree root to the expanded node (seamless drill-down)
  tree.nodes.root_ids = { expanded_node:get_id() }

  -- Update popup title with breadcrumb
  if popup and popup.border and popup.border.text then
    local breadcrumb = self:getFocusBreadcrumb(tree, expanded_node)
    popup.border.text.top = " " .. breadcrumb .. " "
    popup:update_layout() -- Refresh the popup to show new title
  end

  -- Re-render the tree
  tree:render()

  self.logger:debug("Auto-focused on expanded node: " .. (expanded_node.text or "unknown") .. 
                   " (history depth: " .. #self.focus_history .. ")")
end

-- Auto-defocus when collapsing or moving to parent in focus mode
function Variables4Plugin:autoDefocusOnCollapse(tree, collapsed_node, popup)
  if not self.focus_mode_active then
    return
  end

  -- Use focus history to defocus intelligently
  if #self.focus_history > 0 then
    -- Pop the previous focus level from history
    local previous_focus_id = table.remove(self.focus_history)
    local previous_focus_node = tree.nodes.by_id[previous_focus_id]
    
    if previous_focus_node then
      -- Defocus to the previous level in history
      self.focus_node_id = previous_focus_id
      tree.nodes.root_ids = { previous_focus_id }

      -- Update popup title with breadcrumb
      if popup and popup.border and popup.border.text then
        local breadcrumb = self:getFocusBreadcrumb(tree, previous_focus_node)
        popup.border.text.top = " " .. breadcrumb .. " "
        popup:update_layout()
      end

      -- Re-render the tree
      tree:render()

      self.logger:debug("Auto-defocused to previous focus level: " .. (previous_focus_node.text or "unknown") .. 
                       " (history depth: " .. #self.focus_history .. ")")
      return
    end
  end

  -- Fallback: try to find parent of current focus root
  local current_focus_id = self.focus_node_id or tree.nodes.root_ids[1]
  local current_focus_node = tree.nodes.by_id[current_focus_id]
  
  if current_focus_node then
    local parent_id = current_focus_node:get_parent_id()
    if parent_id then
      local parent_node = tree.nodes.by_id[parent_id]
      if parent_node then
        -- Defocus to parent level
        self.focus_node_id = parent_id
        tree.nodes.root_ids = { parent_id }

        -- Update popup title with breadcrumb
        if popup and popup.border and popup.border.text then
          local breadcrumb = self:getFocusBreadcrumb(tree, parent_node)
          popup.border.text.top = " " .. breadcrumb .. " "
          popup:update_layout()
        end

        -- Re-render the tree
        tree:render()

        self.logger:debug("Auto-defocused to parent node: " .. (parent_node.text or "unknown"))
        return
      end
    end
  end

  -- Last resort: exit focus mode entirely
  self:exitFocusMode(tree, popup)
end

-- ========================================
-- TREE NAVIGATION HELPERS
-- ========================================

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

-- Helper to set cursor to a specific node using vim API
function Variables4Plugin:setCursorToNode(tree, node_id)
  local node, linenr_start, linenr_end = tree:get_node(node_id)
  if node and linenr_start then
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(winid, { linenr_start, 0 })
  end
end

-- Navigate to the first child of current node (l key behavior)
function Variables4Plugin:navigateToFirstChild(tree, popup)
  local current_node = tree:get_node()
  if not current_node then return end

  -- Check if this is a lazy variable that needs resolution
  if current_node._variable and current_node._variable.ref and current_node._variable.ref.presentationHint then
    local hint = current_node._variable.ref.presentationHint
    if hint.lazy and not current_node._lazy_resolved then
      -- This is an unresolved lazy variable - resolve it
      self:resolveLazyVariable(tree, current_node, popup)
      return
    end
  end

  -- If node is collapsed and expandable, expand it first
  if not current_node:is_expanded() and current_node.expandable then
    if not current_node._children_loaded then
      -- Async expansion - set up callback to move to first child after loading
      self:ExpandNodeWithCallback(tree, current_node, popup, function()
        self:moveToFirstChild(tree, current_node)
      end)
      return
    else
      -- Sync expansion - expand and immediately move to first child
      current_node:expand()
      tree:render()
      self:moveToFirstChild(tree, current_node)
    end
  elseif current_node:is_expanded() and current_node:has_children() then
    -- Already expanded - just move to first child
    self:moveToFirstChild(tree, current_node)
  end
end

-- Helper to move cursor to first child of a node
function Variables4Plugin:moveToFirstChild(tree, node)
  if node:is_expanded() and node:has_children() then
    local child_ids = node:get_child_ids()
    if child_ids and #child_ids > 0 then
      local first_child_id = child_ids[1]
      self:setCursorToNode(tree, first_child_id)
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
      -- Create child nodes and add them to the tree
      for _, child in ipairs(children) do
        local variable_instance = self:ensureVariableWrapper(child, data_object, node)
        local child_node = variable_instance:asNode()
        child_node._variable = variable_instance
        tree:add_node(child_node, node:get_id())
      end

      node._children_loaded = true

      self.logger:debug("Loaded " .. #children .. " children for: " .. (node.text or "unknown"))

      -- Expand the node now that children are loaded
      node:expand()

      -- Re-render the tree
      tree:render()
      
      -- Execute callback (e.g., move to first child)
      if callback then
        callback()
      end
      
      -- In focus mode, auto-drill down to expanded node
      if self.focus_mode_active then
        self:autoFocusOnExpansion(tree, node, popup)
      end
    else
      -- Mark as loaded even if no children, to avoid repeated attempts
      node._children_loaded = true
      self.logger:debug("No children found for: " .. (node.text or "unknown"))
    end
  end)
end

-- Navigate to parent of current node (h key behavior)
function Variables4Plugin:navigateToParent(tree, popup)
  local current_node = tree:get_node()
  if not current_node then return end

  local parent_id = current_node:get_parent_id()
  if parent_id then
    -- If current node is expanded, collapse it
    if current_node:is_expanded() then
      current_node:collapse()
      tree:render()
      
      -- In focus mode, trigger defocus when collapsing
      if self.focus_mode_active then
        self:autoDefocusOnCollapse(tree, current_node, popup)
      end
    else
      -- Move to parent node
      self:setCursorToNode(tree, parent_id)
      
      -- In focus mode, also trigger defocus when moving to parent
      if self.focus_mode_active then
        self:autoDefocusOnCollapse(tree, current_node, popup)
      end
    end
  end
end

-- Navigate down through siblings or into children (j key behavior)
function Variables4Plugin:navigateDown(tree)
  local current_node = tree:get_node()
  if not current_node then return end
  
  local next_node_id = self:getNextVisibleNode(tree, current_node)
  if next_node_id then
    self:setCursorToNode(tree, next_node_id)
  end
end

-- Navigate up through siblings or to parent level (k key behavior)  
function Variables4Plugin:navigateUp(tree)
  local current_node = tree:get_node()
  if not current_node then return end
  
  local prev_node_id = self:getPreviousVisibleNode(tree, current_node)
  if prev_node_id then
    self:setCursorToNode(tree, prev_node_id)
  end
end


-- ========================================
-- COMMAND IMPLEMENTATIONS
-- ========================================

function Variables4Plugin:UpdateFrameCommand()
  if not self:requireActiveFrame("cannot update frame") then
    return
  end

  local frame = self.current_frame

  if not frame then
    print("No current frame available")
    return
  end

  -- Get the current thread's stack and update to top frame
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
      
      -- In focus mode, auto-drill down after resolution if the node becomes expandable
      if self.focus_mode_active and node.expandable then
        self:autoFocusOnExpansion(tree, node, popup)
      end
      
      -- After successful resolution, continue with expansion if the variable is expandable
      if node.expandable and not node._children_loaded then
        self:ExpandNodeWithCallback(tree, node, popup, function()
          self:moveToFirstChild(tree, node)
        end)
      elseif node.expandable and node:has_children() then
        -- If already has children, just move to first child
        self:moveToFirstChild(tree, node)
      end
    else
      self.logger:debug("Failed to resolve lazy variable: " .. variable_name)
    end
    
    -- Re-render the tree to show the updated values
    tree:render()
  end)
end

-- ========================================
-- TREE INTERFACE
-- ========================================

function Variables4Plugin:OpenVariablesTree()
  local scopes = self:getCurrentScopesAndVariables()
  if not scopes then return end

  -- Create tree nodes from our cached nodes
  local tree_nodes = {}

  for _, scope in ipairs(scopes) do
    local scope_node = scope:asNode()

    -- Create scope node WITHOUT pre-loaded children
    -- Children will be loaded dynamically when expanded
    -- local scope_tree_node = NuiTree.Node({
    --   id = scope_node.id,
    --   text = scope_node.text,
    --   type = "scope",
    --   expandable = true, -- Mark as expandable even without children
    --   _scope = scope,    -- Store reference to original scope
    -- }, {})               -- Start with empty children array

    table.insert(tree_nodes, scope_node)
  end

  -- Create NUI Popup with Tree
  local Popup = require("nui.popup")

  local popup = Popup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " Variables4 Debug Tree ",
        top_align = "center",
      },
    },
    position = "50%",
    size = {
      width = "80%",
      height = "70%",
    },
    buf_options = {
      modifiable = false,
      readonly = true,
    },
    win_options = {
      wrap = false, -- Prevent line wrapping
    },
  })

  -- Mount the popup first
  popup:mount()

  -- Create the actual NUI Tree after mounting
  local NuiLine = require("nui.line")

  local tree = NuiTree({
    bufnr = popup.bufnr,
    nodes = tree_nodes,
  })

  -- Create a custom prepare_node function that calculates relative indentation
  local function prepare_node_with_relative_indent(node)
    local line = NuiLine()

    -- Calculate relative indentation for focus mode
    -- Find minimum depth of current root nodes to normalize indentation
    local min_depth = math.huge
    for _, root_id in ipairs(tree.nodes.root_ids) do
      local root_node = tree.nodes.by_id[root_id]
      if root_node then
        min_depth = math.min(min_depth, root_node:get_depth())
      end
    end
    
    -- Use relative depth so focused subtrees start at left edge
    local relative_depth = math.max(0, node:get_depth() - min_depth)
    line:append(string.rep("  ", relative_depth))

    -- Add expand/collapse indicator with subtle highlight
    if node:has_children() or node.expandable then
      if node:is_expanded() then
        line:append("▼ ", "Comment") -- Subtle color for indicators
      else
        line:append("▶ ", "Comment") -- Subtle color for indicators
      end
    else
      line:append("  ")
    end

    -- Parse the node text to extract icon, name, and value for highlighting
    local text = node.text or ""

    if node.type == "scope" then
      -- Scope nodes: highlight the folder icon and name
      line:append("📁 ", "Directory") -- Folder icon
      line:append(text:sub(3), "Directory") -- Scope name (removing the icon)
    else
      -- Variable nodes: parse "icon name: value" format
      local icon_pos = text:find(" ")
      local colon_pos = text:find(": ")

      if icon_pos and colon_pos and icon_pos < colon_pos then
        local icon = text:sub(1, icon_pos - 1)
        local name = text:sub(icon_pos + 1, colon_pos - 1)
        local value = text:sub(colon_pos + 2)

        -- Add icon with subtle highlight
        line:append(icon .. " ", "Comment")

        -- Add variable name with normal highlight
        line:append(name .. ": ", "Identifier")

        -- Add value with type-specific highlight
        local highlight = node._highlight or "Normal"
        line:append(value, highlight)
      else
        -- Fallback: just append the text normally
        line:append(text)
      end
    end

    return line
  end

  -- Override the tree's prepare_node function
  tree._.prepare_node = prepare_node_with_relative_indent

  -- Render the tree
  tree:render()

  -- Set up keymaps for tree interaction
  local map_options = { noremap = true, silent = true }

  -- Tree-aware navigation with hjkl (primary navigation method)
  popup:map("n", "h", function()
    self:navigateToParent(tree, popup)
  end, map_options)

  popup:map("n", "j", function()
    self:navigateDown(tree)
  end, map_options)

  popup:map("n", "k", function()
    self:navigateUp(tree)
  end, map_options)

  popup:map("n", "l", function()
    self:navigateToFirstChild(tree, popup)
  end, map_options)

  -- Quit with q or Escape
  popup:map("n", "q", function()
    popup:unmount()
  end, map_options)

  popup:map("n", "<Esc>", function()
    popup:unmount()
  end, map_options)

  -- Focus mode controls
  popup:map("n", "f", function()
    self:enterFocusMode(tree, popup)
  end, map_options)

  popup:map("n", "r", function()
    self:exitFocusMode(tree, popup)
  end, map_options)

  -- Show help
  popup:map("n", "?", function()
    print("Variables4 Tree Controls (hjkl navigation):")
    print("  h: Collapse node or move to parent (triggers defocus in focus mode)")
    print("  j: Navigate down through visible nodes") 
    print("  k: Navigate up through visible nodes")
    print("  l: Expand node and move to first child (triggers auto-focus in focus mode)")
    print("  f: Enter focus mode on current selection")
    print("  r: Exit focus mode and return to full tree")
    print("  q/Esc: Close popup")
    print("")
    print("Focus mode: Navigate with hjkl for seamless drill-down/up experience")
  end, map_options)

  -- Tree popup is now open and interactive
end

-- ========================================
-- MODULE EXPORTS
-- ========================================

return Variables4Plugin
