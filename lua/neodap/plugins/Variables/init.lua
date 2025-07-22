local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')
local renderer = require("neo-tree.ui.renderer")
local IdGenerator = require('neodap.plugins.Variables.id_generator')


local ICONS = {
  fn = "󰊕",
  var = "󰀫",
  scope = "󰅩",
  global = "󰇧",
  scope_expanded = "{",
  scope_collapsed = "󰅩",
}


---@class neodap.plugins.VariablesProps
---@field api Api
---@field logger Logger
---@field current_frame? Frame

---@class neodap.plugins.Variables: neodap.plugins.VariablesProps, neotree.Source
---@field new Constructor<neodap.plugins.VariablesProps>
local VariablesPlugin = Class()
VariablesPlugin.instance = nil

---@return neodap.plugins.Variables
function VariablesPlugin.get()
  if not VariablesPlugin.instance then
    error("Variables plugin not initialized. Call Variables.plugin(api) first.")
  end
  return VariablesPlugin.instance
end

---@param api Api
function VariablesPlugin.plugin(api)
  local instance = VariablesPlugin:new({
    api = api,
    logger = Logger.get("Variables"),
    current_frame = nil
  })

  VariablesPlugin.instance = instance

  instance:init()

  return instance
end

---Format variable display name
---@param var_ref table DAP variable reference
---@return string display_name Formatted name for display
local function formatVariableDisplay(var_ref)
  local name = var_ref.name or "<anonymous>"
  local value = var_ref.value or ""
  local type_hint = var_ref.type and (" (" .. var_ref.type .. ")") or ""

  -- For expandable items, just show name and type
  if var_ref.variablesReference and var_ref.variablesReference > 0 then
    return name .. type_hint .. ": " .. "value"
  end

  -- For leaf items, show name: value
  return name .. ": " .. "value"
end

---Convert a DAP variable to a Neo-tree node
---@param var_ref table DAP variable reference
---@param parent_id string Parent node ID for building hierarchical IDs
---@param index? number Optional index for array elements
---@return table node Neo-tree node
local function variableToNode(var_ref, parent_id, index)
  local node_id = IdGenerator.forVariable(parent_id, var_ref, index)
  local is_expandable = var_ref.variablesReference and var_ref.variablesReference > 0

  return {
    id = node_id,
    name = formatVariableDisplay(var_ref),
    type = "variable",
    path = node_id,
    loaded = not is_expandable,
    has_children = is_expandable,
    extra = {
      is_expandable = is_expandable,
      variable_reference = var_ref.variablesReference,
      var_type = var_ref.type,
      var_value = var_ref.value,
      evaluate_name = var_ref.evaluateName,
      indexed_variables = var_ref.indexedVariables,
      named_variables = var_ref.namedVariables,
    },
  }
end

---Convert a scope to a Neo-tree node
---@param scope_ref table DAP scope reference
---@return table node Neo-tree node
local function scopeToNode(scope_ref)
  local node_id = IdGenerator.forScope(scope_ref)
  return {
    id = node_id,
    name = scope_ref.name,
    type = "scope",
    path = node_id,
    loaded = false,
    has_children = true,
    extra = {
      is_expandable = true,
      variables_reference = scope_ref.variablesReference,
      expensive = scope_ref.expensive,
      scope_name = scope_ref.name,
    },
  }
end


function VariablesPlugin:init()
  self:setupCommands()

  self.api:onSession(function(session)
    session:onThread(function(thread)
      thread:onStopped(function()
        local stack = thread:stack()
        self.current_frame = stack and stack:top() or nil

        -- Simply update the frame reference
        -- The Variables window will refresh when navigated to
      end)

      thread:onContinued(function()
        self.current_frame = nil

        -- Clear the frame reference when execution continues
      end)
    end)
  end)
end

---Setup user commands for Variables window
function VariablesPlugin:setupCommands()
  vim.api.nvim_create_user_command("NeodapVariablesShow", function()
    vim.cmd("Neotree variables show")
  end, { desc = "Show Neodap variables window" })

  vim.api.nvim_create_user_command("NeodapVariablesClose", function()
    vim.cmd("Neotree variables close")
  end, { desc = "Close Neodap variables window" })

  vim.api.nvim_create_user_command("NeodapVariablesToggle", function()
    vim.cmd("Neotree variables toggle")
  end, { desc = "Toggle Neodap variables window" })

  vim.api.nvim_create_user_command("NeodapVariablesFocus", function()
    vim.cmd("Neotree variables focus")
  end, { desc = "Focus Neodap variables window" })
end

---Convert variables to nodes
---@param variables table[] Array of DAP variables
---@param parent_id string Parent node ID
---@return table[] nodes Array of Neo-tree nodes
function VariablesPlugin:variablesToNodes(variables, parent_id)
  local nodes = {}
  if variables then
    for _, var_ref in ipairs(variables) do
      -- We add a 0 to make sure tonumber dont interpret words numbers such as infinity
      local index = tonumber("0" .. var_ref.name)
      local node = variableToNode(var_ref, parent_id, index)
      table.insert(nodes, node)
    end
  end
  return nodes
end

---Load variables data for the tree
---@param state neotree.State
---@param parent_id? string Parent node ID for lazy loading
---@param parent_extra? table Extra data from parent node to avoid tree access
---@param callback? fun() Callback when loading is complete
function VariablesPlugin:LoadVariablesData(state, parent_id, parent_extra, callback)
  -- vim.notify(string.format("[Variables] LoadVariablesData called: parent_id=%s", tostring(parent_id)))
  if not parent_id then
    -- Root level: load scopes
    if not self.current_frame then
      renderer.show_nodes({}, state, nil, callback)
      return
    end

    local nodes = {}
    local scopes = self.current_frame:scopes()
    if scopes then
      for _, scope in ipairs(scopes) do
        table.insert(nodes, scopeToNode(scope.ref))
      end
    end
    renderer.show_nodes(nodes, state, nil, callback)
  else
    -- Child level: load variables using parent's reference
    local ref = parent_extra and (parent_extra.variables_reference or parent_extra.variable_reference)
    if not ref or not self.current_frame then
      renderer.show_nodes({}, state, parent_id, callback)
      return
    end

    local variables = self.current_frame:variables(ref)
    local nodes = self:variablesToNodes(variables, parent_id)
    renderer.show_nodes(nodes, state, parent_id, callback)
  end
end

---Navigate function for Neo-tree integration
---@type fun(state: neotree.State, path?: string, path_to_reveal?: string, callback?: function, async?: boolean)
function VariablesPlugin:Navigate(state, path, pathToReveal, callback, _async)
  -- Load and display the root-level scopes
  self:LoadVariablesData(state, nil, nil, callback)
end

local components = require("neo-tree.sources.common.components")

---@type neotree.Source & { plugin: fun(api: Api): neodap.plugins.Variables }
local VariablesSource = {
  name = "variables",
  display_name = "Variables",
  commands = {
    ---@param state neotree.State
    toggle_node = function(state)
      local commands = require("neo-tree.sources.common.commands")
      local plugin = VariablesPlugin.get()
      local renderer = require("neo-tree.ui.renderer")

      local node = state.tree and state.tree:get_node()
      if not node then return end

      if not node.loaded then
        -- If not loaded, we need to fetch data
        plugin:LoadVariablesData(state, node.id, node.extra)

        local loader = {
          id = node.id .. "/loading",
          name = "Loading...",
          type = "loading",
        }
        renderer.show_nodes({ loader }, state, node.id)
      elseif node.extra.is_expandable then
        local updated = false
        if node:is_expanded() then
          updated = node:collapse()
        else
          updated = node:expand()
        end
        if updated then
          renderer.redraw(state)
        end
      end


      -- -- Use the common toggle_node with our custom handler
      -- -- Neo-tree only calls this for expandable nodes needing data
      -- commands.toggle_node(state, function(node)
      --   -- vim.notify(string.format("[Variables] Toggle handler called for: %s, loaded=%s", node.id, tostring(node.loaded)))
      --   if plugin and not node.loaded then
      --     -- Only load if not already loaded
      --     plugin:LoadVariablesData(state, node.id, node.extra)
      --   end
      -- end)
    end,
  },
  components = components,
  ---@param opts neotree.SourceOptions
  ---@param config neotree.Config.Base
  setup = function(opts, config)
    local kinds = config.document_symbols.kinds
    -- Ensure we have proper renderers
    if not opts.renderers then
      opts.renderers = {}
    end

    local expanded = {
      "icon",
      ---@param node NuiTreeNode
      ---@param state neotree.State
      provider = function(icon, node, state)
        return {
          text = node:is_expanded() and "-" or "+",
          highlight = "NeoTreeScopeIcon",
        }
      end
    }

    -- Set default renderers if they don't exist
    if not opts.renderers.scope then
      opts.renderers.scope = {
        {
          "indent",
          indent_size = 2,
          padding = 1,
          -- indent guides
          with_markers = true,
          indent_marker = "│",
          last_indent_marker = "└",
          highlight = "NeoTreeIndentMarker",
          -- expander config, needed for nesting files
          with_expanders = nil, -- if nil and file nesting is enabled, will enable expanders
          expander_collapsed = "",
          expander_expanded = "",
          expander_highlight = "NeoTreeExpander",
        },
        expanded,
        { "name" }
      }
    end

    if not opts.renderers.variable then
      opts.renderers.variable = {
        { "indent" },
        expanded,
        {
          "icon",
          ---@param node NuiTreeNode
          provider = function(icon, node, state)
            local kind = kinds[node.extra.var_type or "Unknown"]
            if kind then
              return {
                text = kind.icon,
                highlight = kind.hl or "NeoTreeVariableIcon"
              }
            end
            return {
              text = ICONS.var,
              highlight = "NeoTreeVariableIcon"
            }
            -- config.document_symbols.kinds
            -- local extra = node.extra or {}
            -- if extra.var_type then
            --   return {
            --     text = " (" .. extra.var_type .. ")",
            --     highlight = "NeoTreeVariableType"
            --   }
            -- end
            -- return ""
          end
        },
        { "name" },
      }
    end

    -- Set up window mappings
    if not opts.window then
      opts.window = {}
    end
    if not opts.window.mappings then
      opts.window.mappings = {}
    end

    -- Override specific mappings for our source
    opts.window.mappings["<cr>"] = "toggle_node"
    opts.window.mappings["<space>"] = "toggle_node"
    opts.window.mappings["o"] = "toggle_node"
  end,
  navigate = function(state, path, pathToReveal, callback, _async)
    local plugin = VariablesPlugin.get()
    if not plugin then
      if callback then vim.schedule(callback) end
      return
    end

    plugin:Navigate(state, path, pathToReveal, callback, _async)
  end,

  Plugin = VariablesPlugin,
  plugin = function(api)
    return VariablesPlugin.plugin(api)
  end,
}

return VariablesSource
