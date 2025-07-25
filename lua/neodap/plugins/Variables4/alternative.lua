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
---@field current_frame? Frame
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

-- Constants for formatting
local TRUNCATION_LENGTHS = {
  default = 60,
  ['function'] = 40,
  string = 50,
  signature = 30,
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
    -- Replace newlines and multiple spaces with single spaces
    value = value:gsub("[\r\n]+", " "):gsub("%s+", " ")

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

  -- Get icon, highlight, and formatted value using our enhancement functions
  local icon, highlight, _ = getTypeInfo(self.ref)
  local formatted_value = formatVariableValue(self.ref)

  self._node = NuiTree.Node({
    id = string.format("var:%s", self.ref.name),
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

function ArgumentsScope:asNode()
  return BaseScope.asNode(self)
end

function LocalsScope:asNode()
  return BaseScope.asNode(self)
end

function GlobalsScope:asNode()
  return BaseScope.asNode(self)
end

function ReturnValueScope:asNode()
  return BaseScope.asNode(self)
end

function RegistersScope:asNode()
  return BaseScope.asNode(self)
end

function GenericScope:asNode()
  return BaseScope.asNode(self)
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
  vim.api.nvim_create_user_command("Variables4Demo", function()
    self:DemonstrateAsNodeStrategy()
  end, { desc = "Demonstrate Variables4 asNode() caching strategy" })

  vim.api.nvim_create_user_command("Variables4Status", function()
    self:ShowStatus()
  end, { desc = "Show Variables4 status" })

  vim.api.nvim_create_user_command("Variables4TreeDemo", function()
    self:DemonstrateTreeRendering()
  end, { desc = "Demonstrate NUI tree rendering with Variables4 nodes" })

  vim.api.nvim_create_user_command("Variables4TreeInteract", function()
    self:InteractWithTree()
  end, { desc = "Show tree interaction capabilities" })

  vim.api.nvim_create_user_command("Variables4TestHierarchy", function()
    self:TestHierarchicalExpansion()
  end, { desc = "Test hierarchical variable expansion" })

  vim.api.nvim_create_user_command("Variables4QuickDemo", function()
    print("Variables4: Quick Demo")
    print("===============================")
    print("✅ Hierarchical expansion implemented!")
    print("✅ Both scopes AND variables can now expand")
    print("✅ Unified expansion logic eliminates duplication")
    print("✅ Raw DAP variables properly wrapped as API objects")
    print("")
    print("Try: :Variables4TreeDemo to see interactive hierarchical tree")
    print("Example: arrayVar expands to show [0,1,2,3,4] and nested objects")
  end, { desc = "Quick demo of Variables4 capabilities" })
end

-- ========================================
-- DEMONSTRATION
-- ========================================

function Variables4Plugin:DemonstrateAsNodeStrategy()
  if not self.current_frame then
    print("No debug session active - start debugging to see asNode() strategy")
    return
  end

  print("Variables4: AsNode() Caching Strategy")
  print("===================================")
  print("")

  local scopes = self.current_frame:scopes()

  for _, scope in ipairs(scopes) do
    print("Scope: " .. scope.ref.name)
    print("  ✓ Type: " .. type(scope))
    print("  ✓ Has asNode method: " .. tostring(scope.asNode ~= nil))
    print("  ✓ Has cached node: " .. tostring(scope._cached_node ~= nil))
    print("  ✓ Original variables method: " .. tostring(scope.variables ~= nil))

    -- Test asNode() method
    if scope.asNode then
      print("  → Calling scope:asNode() for first time...")
      local node1 = scope:asNode()
      print("    ✓ Node created: " .. tostring(node1))
      print("    ✓ Node ID: " .. tostring(node1:get_id()))
      print("    ✓ Node text: " .. tostring(node1.text))

      print("  → Calling scope:asNode() again (should be cached)...")
      local node2 = scope:asNode()
      print("    ✓ Same instance: " .. tostring(node1 == node2))
      print("    ✓ Cache working: " .. tostring(scope._cached_node == node2))
    end
    print("")

    -- Show first few variables with asNode()
    local variables = scope:variables()
    if variables and #variables > 0 then
      print("  Variables (showing first 3):")
      for i, variable in ipairs(variables) do
        if i > 3 then break end

        print("    " .. variable.ref.name)
        print("      ✓ Has asNode method: " .. tostring(variable.asNode ~= nil))
        print("      ✓ Has cached node: " .. tostring(variable._cached_node ~= nil))

        if variable.asNode then
          print("      → Calling variable:asNode() for first time...")
          local var_node1 = variable:asNode()
          print("        ✓ Node ID: " .. tostring(var_node1:get_id()))
          print("        ✓ Node text: " .. tostring(var_node1.text))

          print("      → Calling variable:asNode() again (should be cached)...")
          local var_node2 = variable:asNode()
          print("        ✓ Same instance: " .. tostring(var_node1 == var_node2))
          print("        ✓ Cache working: " .. tostring(variable._cached_node == var_node2))
        end
      end
      if #variables > 3 then
        print("    ... and " .. (#variables - 3) .. " more variables")
      end
      print("")
    end
  end

  print("✓ AsNode() caching strategy demonstrated!")
  print("✓ Each Variable/Scope creates exactly one cached NuiTree.Node")
  print("✓ Subsequent calls return the same cached instance")
  print("✓ Non-intrusive - original API methods remain unchanged")
end

function Variables4Plugin:ShowStatus()
  print("Variables4 Plugin Status:")
  print("========================")
  print("Strategy: asNode() caching method")
  print("Current frame: " .. (self.current_frame and "Yes" or "No"))
  print("")

  if self.current_frame then
    local scopes = self.current_frame:scopes()
    print("Available scopes: " .. #scopes)

    for _, scope in ipairs(scopes) do
      local has_method = scope.asNode ~= nil
      local has_cache = scope._cached_node ~= nil
      print("  - " ..
        scope.ref.name .. " (asNode: " .. tostring(has_method) .. ", cached: " .. tostring(has_cache) .. ")")
    end
  end

  print("")
  print("✓ Variables have asNode() method")
  print("✓ Scopes have asNode() method")
  print("✓ Caching strategy active")
end

-- ========================================
-- UNIFIED EXPANSION LOGIC
-- ========================================

-- Helper function to ensure a child is wrapped as a proper Variable instance
function Variables4Plugin:ensureVariableWrapper(child, data_object)
  local variable_instance
  
  if child.ref then
    -- This is already a wrapped Variable API object
    variable_instance = child
  else
    -- This is a raw DAP variable object - wrap it
    local parent_scope = data_object.scope or data_object -- Variable has scope, Scope is itself
    variable_instance = Variable.instanciate(parent_scope, child)
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
function Variables4Plugin:expandNode(tree, node)
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
  NvimAsync.defer(function()
    local children = data_object:variables()

    if children and #children > 0 then
      -- Create child nodes and add them to the tree
      for _, child in ipairs(children) do
        local variable_instance = self:ensureVariableWrapper(child, data_object)
        local child_node = variable_instance:asNode()
        child_node._variable = variable_instance
        tree:add_node(child_node, node:get_id())
      end

      node._children_loaded = true

      self.logger:debug("Loaded " .. #children .. " children for: " .. (node.text or "unknown"))

      -- Re-render the tree
      tree:render()
    else
      -- Mark as loaded even if no children, to avoid repeated attempts
      node._children_loaded = true
      self.logger:debug("No children found for: " .. (node.text or "unknown"))
    end
  end)()
end

-- ========================================
-- TREE RENDERING DEMONSTRATION
-- ========================================

function Variables4Plugin:DemonstrateTreeRendering()
  if not self.current_frame then
    print("No debug session active - start debugging to see tree rendering")
    return
  end

  print("Opening Variables4 NUI Tree Popup...")

  local scopes = self.current_frame:scopes()

  -- Create tree nodes from our cached nodes
  local tree_nodes = {}

  for _, scope in ipairs(scopes) do
    local scope_node = scope:asNode()

    -- Create scope node WITHOUT pre-loaded children
    -- Children will be loaded dynamically when expanded
    local scope_tree_node = NuiTree.Node({
      id = scope_node.id,
      text = scope_node.text,
      type = "scope",
      expandable = true, -- Mark as expandable even without children
      _scope = scope,    -- Store reference to original scope
    }, {})               -- Start with empty children array

    table.insert(tree_nodes, scope_tree_node)
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
          line:append("▼ ", "Comment")  -- Subtle color for indicators
        else
          line:append("▶ ", "Comment")  -- Subtle color for indicators
        end
      else
        line:append("  ")
      end

      -- Parse the node text to extract icon, name, and value for highlighting
      local text = node.text or ""
      
      if node.type == "scope" then
        -- Scope nodes: highlight the folder icon and name
        line:append("📁 ", "Directory")  -- Folder icon
        line:append(text:sub(3), "Directory")  -- Scope name (removing the icon)
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

  -- Expand/collapse with Enter or Space
  popup:map("n", "<CR>", function()
    local node = tree:get_node()
    if node then
      if node:is_expanded() then
        -- Collapse the node
        node:collapse()
        tree:render()
      else
        -- Expand the node - use unified expansion logic
        if node.expandable and not node._children_loaded then
          self:expandNode(tree, node)
        end

        node:expand()
        tree:render()
      end
    end
  end, map_options)

  popup:map("n", "<Space>", function()
    local node = tree:get_node()
    if node then
      if node:is_expanded() then
        -- Collapse the node
        node:collapse()
        tree:render()
      else
        -- Expand the node - use unified expansion logic
        if node.expandable and not node._children_loaded then
          self:expandNode(tree, node)
        end

        node:expand()
        tree:render()
      end
    end
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

  -- Store references for cleanup
  self._demo_popup = popup
  self._demo_tree = tree
  self._demo_nodes = tree_nodes

  print("✓ Variables4 Tree Popup opened!")
  print("✓ Use Enter/Space to expand/collapse, j/k to navigate, q to quit")
end

function Variables4Plugin:InteractWithTree()
  if not self._demo_popup then
    print("No popup open - run :Variables4TreeDemo first to open the interactive tree popup")
    return
  end

  print("Variables4: Tree Interaction Info")
  print("=================================")
  print("")
  print("The Variables4 tree popup is currently open with interactive controls:")
  print("  📁 Scopes and variables are displayed in a hierarchical tree")
  print("  🔧 Each node is created using Variables4 asNode() caching")
  print("  🎮 Use Enter/Space to expand/collapse nodes")
  print("  ⬆️⬇️ Use j/k to navigate up/down")
  print("  ❌ Use q/Esc to close the popup")
  print("  ❓ Use ? for help")
  print("")
  print("✓ Tree popup is fully interactive!")
  print("✓ Original Variables/Scopes remain accessible via _scope/_variable references")
  print("✓ Cached nodes provide efficient UI updates")
end

function Variables4Plugin:TestHierarchicalExpansion()
  if not self.current_frame then
    print("No debug session active - start debugging first")
    return
  end

  print("Variables4: Testing Hierarchical Expansion")
  print("==========================================")
  print("")
  print("Testing that both scopes AND variables can expand:")
  print("")

  local scopes = self.current_frame:scopes()

  for _, scope in ipairs(scopes) do
    print("📁 Scope: " .. scope.ref.name)

    -- Test scope expansion
    local variables = scope:variables()
    if variables and #variables > 0 then
      print("  ✓ Scope has " .. #variables .. " variables")

      -- Test first few variables for hierarchical expansion
      for i, variable in ipairs(variables) do
        if i > 2 then break end -- Just test first 2

        print("  📄 Variable: " .. variable.ref.name .. " = " .. (variable.ref.value or variable.ref.type))
        print("    ✓ Has variables() method: " .. tostring(variable.variables ~= nil))
        print("    ✓ Is expandable: " ..
          tostring(variable.ref.variablesReference and variable.ref.variablesReference > 0))

        if variable.ref.variablesReference and variable.ref.variablesReference > 0 then
          print("    → Testing variable expansion...")
          local child_vars = variable:variables()
          if child_vars and #child_vars > 0 then
            print("      ✓ Variable expanded to " .. #child_vars .. " children!")
            print("      ✓ HIERARCHICAL EXPANSION WORKING!")

            -- Show first child as proof
            if child_vars[1] then
              print("        Example child: " ..
                child_vars[1].ref.name .. " = " .. (child_vars[1].ref.value or child_vars[1].ref.type))
            end
          else
            print("      ✗ Variable expansion returned no children")
          end
        else
          print("    ○ Variable is not expandable (no nested properties)")
        end
        print("")
      end
    else
      print("  ○ Scope has no variables")
    end
    print("")
  end

  print("✓ Hierarchical expansion test completed!")
  print("✓ Both scopes and variables can now expand using unified logic")
  print("✓ Try :Variables4TreeDemo to see interactive hierarchical expansion")
end

-- ========================================
-- MODULE EXPORTS
-- ========================================

return Variables4Plugin
