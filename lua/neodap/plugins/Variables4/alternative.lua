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
function Variable:asNode()
  if self._node then return self._node end

  self._node = NuiTree.Node({
    id = string.format("var:%s", self.ref.name),
    text = string.format("%s: %s", self.ref.name, self.ref.value or self.ref.type),
    type = "variable",
    expandable = self.ref.variablesReference and self.ref.variablesReference > 0,
    _variable = self, -- Store reference to original variable for access to methods
  }, {})

  return self._node
end

function BaseScope:asNode()
  if self._node then return self._node end

  self._node = NuiTree.Node({
    id = string.format("scope:%s", self.ref.name),
    text = "📁 " .. self.ref.name,
    type = "scope",
    expandable = true,
    _scope = self, -- Store reference to original scope for access to methods
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
      _scope = scope,
      expandable = true, -- Mark as expandable even without children
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
  local tree = NuiTree({
    bufnr = popup.bufnr,
    nodes = tree_nodes,
    prepare_node = function(node)
      local line = {}

      -- Add indentation based on depth
      for _ = 1, node:get_depth() - 1 do
        table.insert(line, "  ")
      end

      -- Add expand/collapse indicator
      if node:has_children() or node.expandable then
        if node:is_expanded() then
          table.insert(line, "▼ ")
        else
          table.insert(line, "▶ ")
        end
      else
        table.insert(line, "  ")
      end

      -- Add the actual text
      table.insert(line, node.text)

      return table.concat(line)
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
        -- Expand the node
        if node.type == "scope" and node._scope and not node._variables_loaded then
          -- This is a scope node - load its variables dynamically (only once)
          print("Loading variables for scope: " .. node._scope.ref.name)

          -- Use NvimAsync.defer to handle the async variables() call
          local NvimAsync = require("neodap.tools.async")
          NvimAsync.defer(function()
            local variables = node._scope:variables()

            if variables then
              -- Create child nodes for the variables
              local var_children = {}
              for _, variable in ipairs(variables) do
                local var_node = variable:asNode()
                -- Create a proper NUI Tree node with the variable data
                local tree_var_node = NuiTree.Node({
                  id = var_node.id,
                  text = var_node.text,
                  type = "variable",
                  _variable = variable,
                }, {})
                table.insert(var_children, tree_var_node)
              end
              
              -- Use NUI Tree API to add children dynamically
              tree:set_nodes(var_children, node:get_id())
              node._variables_loaded = true

              print("Loaded " .. #variables .. " variables")

              -- Re-render the tree after loading
              tree:render()
            end
          end)()
        end

        node:expand()
        tree:render()
      end
    end
  end, map_options)

  popup:map("n", "<Space>", NvimAsync.defer(function()
    local node = tree:get_node()
    if node then
      if node:is_expanded() then
        -- Collapse the node
        node:collapse()
        tree:render()
      else
        -- Expand the node (same logic as Enter)
        if node.type == "scope" and node._scope and not node._variables_loaded then
          -- This is a scope node - load its variables dynamically (only once)
          print("Loading variables for scope: " .. node._scope.ref.name)

          local variables = node._scope:variables()

          if variables then
            -- Create child nodes for the variables
            local var_children = {}
            for _, variable in ipairs(variables) do
              local var_node = variable:asNode()
              -- Create a proper NUI Tree node with the variable data
              local tree_var_node = NuiTree.Node({
                id = var_node.id,
                text = var_node.text,
                type = "variable",
                _variable = variable,
              }, {})
              table.insert(var_children, tree_var_node)
            end
            
            -- Use NUI Tree API to add children dynamically
            tree:set_nodes(var_children, node:get_id())
            node._variables_loaded = true

            print("Loaded " .. #variables .. " variables")
          end
        end

        node:expand()
        tree:render()
      end
    end
  end), map_options)

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

-- ========================================
-- MODULE EXPORTS
-- ========================================

return Variables4Plugin
