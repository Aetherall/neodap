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
  print("=== Variables4Plugin:initialize() called ===")
  self.logger:info("Initializing Variables4 plugin - asNode() caching strategy")

  -- Set up event handlers
  self:setupEventHandlers()

  -- Create commands
  self:setupCommands()

  print("=== Variables4Plugin:initialize() completed ===")
  self.logger:info("Variables4 plugin initialized - will add asNode() methods on first session")
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

  -- Debug: Check for presentationHint to understand DAP structure
  if self.ref.presentationHint and self.ref.presentationHint.lazy then
    -- print("DEBUG: Found lazy variable: " .. self.ref.name .. " with hint: " .. vim.inspect(self.ref.presentationHint))
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

-- Helper for node toggle logic (eliminates duplication between Enter/Space handlers)
function Variables4Plugin:toggleTreeNode(tree)
  local node = tree:get_node()
  if node then
    if node:is_expanded() then
      -- Collapse the node
      node:collapse()
      tree:render()
    else
      -- Expand the node - use unified expansion logic
      if node.expandable and not node._children_loaded then
        self:ExpandNode(tree, node)
      else
        -- For already loaded nodes, just expand and render
        node:expand()
        tree:render()
      end
    end
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

-- Unified function to expand any expandable node (scope or variable)
function Variables4Plugin:ExpandNode(tree, node)
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
    -- Check for lazy variables that need resolution instead of expansion
    if node._variable and node._variable.ref and node._variable.ref.presentationHint then
      local hint = node._variable.ref.presentationHint
      if hint.lazy then
        -- This is a lazy variable - resolve it instead of expanding children
        self:resolveLazyVariable(tree, node)
        return
      end
    end

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
    else
      -- Mark as loaded even if no children, to avoid repeated attempts
      node._children_loaded = true
      self.logger:debug("No children found for: " .. (node.text or "unknown"))
    end
  end)
end

-- ========================================
-- LAZY VARIABLE RESOLUTION
-- ========================================

-- Resolve a lazy variable by evaluating it and replacing the node
---@param tree NuiTree
---@param node NuiTreeNode
function Variables4Plugin:resolveLazyVariable(tree, node)
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

  -- Use the DAP evaluate request to resolve the lazy variable
  -- This will trigger the getter and return the actual value
  NvimAsync.defer(function()
    print("Resolving lazy variable: " .. variable_name)
    variable:resolve()
    print("Resolved lazy variable1: " .. variable_name)
    variable._node = nil;
    node._lazy_resolved = true -- Reset lazy resolution state
    local newnode = variable:asNode()
    print("Resolved lazy variable: " .. variable_name, vim.inspect(newnode))
    vim.tbl_extend("force", node, newnode)
    -- tree:render()
    -- -- Call evaluate on the variable name in the current frame context
    -- local result = frame:evaluate(variable_name)

    -- if result then
    --   -- Create a new Variable instance from the evaluated result
    --   local resolved_variable = Variable.instanciate(variable.scope, result)

    --   -- Apply the asNode method
    --   resolved_variable.asNode = Variable.asNode
    --   if not resolved_variable.variables then
    --     resolved_variable.variables = Variable.variables
    --   end

    --   -- Create the new resolved node
    --   local resolved_node = resolved_variable:asNode()
    --   resolved_node._variable = resolved_variable

    --   -- Replace the original node with the resolved one
    --   -- We need to update the tree structure
    --   local parent_id = node:get_parent_id()

    --   -- Remove the old lazy node
    --   tree:remove_node(node:get_id())

    --   -- Add the resolved node in its place
    --   if parent_id then
    --     tree:add_node(resolved_node, parent_id)
    --   else
    --     -- This is a root node, we need to update the tree structure differently
    --     -- For now, just re-render with the resolved node
    --     tree:add_node(resolved_node)
    --   end

    -- Mark as resolved so we don't re-resolve it
    -- node._lazy_resolved = true

    -- self.logger:debug("Resolved lazy variable: " .. variable_name)

    --     -- Re-render the tree
    --     tree:render()
    --   else
    --     self.logger:warn("Failed to resolve lazy variable: " .. variable_name)
    --     -- Mark as loaded to prevent re-attempts
    --     node._children_loaded = true
    --   end
    -- end)()
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
    prepare_node = function(node)
      local line = NuiLine()

      -- Add indentation based on depth
      line:append(string.rep("  ", node:get_depth() - 1))

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
    end,
  })

  -- Render the tree
  tree:render()

  -- Set up keymaps for tree interaction
  local map_options = { noremap = true, silent = true }

  -- Expand/collapse with Enter or Space (uses unified toggle logic)
  popup:map("n", "<CR>", function()
    self:toggleTreeNode(tree)
  end, map_options)

  popup:map("n", "<Space>", function()
    self:toggleTreeNode(tree)
  end, map_options)

  -- Navigation - using standard vim movement
  popup:map("n", "j", function()
    vim.cmd("normal! j")
  end, map_options)

  popup:map("n", "k", function()
    vim.cmd("normal! k")
  end, map_options)

  -- Quit with q or Escape
  popup:map("n", "q", function()
    popup:unmount()
  end, map_options)

  popup:map("n", "<Esc>", function()
    popup:unmount()
  end, map_options)

  -- Show help
  popup:map("n", "?", function()
    print("Variables4 Tree Controls:")
    print("  Enter/Space: Expand/collapse node")
    print("  j/k: Navigate up/down")
    print("  q/Esc: Close popup")
  end, map_options)

  -- Tree popup is now open and interactive
end

-- All demonstration methods removed - functionality is now tested via snapshot tests

-- ========================================
-- MODULE EXPORTS
-- ========================================

return Variables4Plugin
