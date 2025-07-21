local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')
local renderer = require("neo-tree.ui.renderer")

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

---Convert a DAP variable to a Neo-tree node
---@param var_ref table DAP variable reference
---@param parent_id? string Parent node ID for building hierarchical IDs
---@return table node Neo-tree node
local function variableToNode(var_ref, parent_id)
  -- Use reference-based ID for uniqueness, or generate one for leaf nodes
  local node_id
  if var_ref.variablesReference and var_ref.variablesReference > 0 then
    node_id = "var_" .. var_ref.variablesReference
  else
    -- For leaf nodes without reference, create unique ID
    node_id = "leaf_" .. (parent_id or "") .. "_" .. var_ref.name .. "_" .. tostring(var_ref):match("0x%x+")
  end

  local is_expandable = var_ref.variablesReference and var_ref.variablesReference > 0

  return {
    id = node_id,
    name = var_ref.name .. ": " .. (var_ref.value or ""),
    type = is_expandable and "directory" or "file",
    path = node_id,
    loaded = not is_expandable,
    has_children = is_expandable,
    extra = {
      variable_reference = var_ref.variablesReference,
      var_type = var_ref.type,
      var_value = var_ref.value,
    },
  }
end

---Convert a scope to a Neo-tree node
---@param scope_ref table DAP scope reference
---@return table node Neo-tree node
local function scopeToNode(scope_ref)
  local node_id = "scope_" .. scope_ref.variablesReference
  return {
    id = node_id,
    name = scope_ref.name,
    type = "directory",
    path = node_id,
    loaded = false,
    has_children = true,
    extra = {
      variables_reference = scope_ref.variablesReference,
      expensive = scope_ref.expensive,
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

        -- Trigger Neo-tree refresh
        vim.schedule(function()
          local ok, mgr = pcall(require, "neo-tree.sources.manager")
          if ok and mgr then
            mgr.refresh("variables")
          end
        end)
      end)

      thread:onContinued(function()
        self.current_frame = nil

        -- Trigger Neo-tree refresh
        vim.schedule(function()
          local ok, mgr = pcall(require, "neo-tree.sources.manager")
          if ok and mgr then
            mgr.refresh("variables")
          end
        end)
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

---Load variables data for the tree
---@param state neotree.State
---@param parent_id? string Parent node ID for lazy loading
---@param callback? function Callback when loading is complete
function VariablesPlugin:LoadVariablesData(state, parent_id, callback)
  if not self.current_frame then
    renderer.show_nodes({}, state, nil, callback)
    return
  end

  local nodes = {}

  if not parent_id then
    -- Root level: show scopes
    local scopes = self.current_frame:scopes()
    if scopes then
      for i, scope in ipairs(scopes) do
        local node = scopeToNode(scope.ref)
        table.insert(nodes, node)
      end
    end
    renderer.show_nodes(nodes, state, nil, callback)
  elseif parent_id:match("^scope_") then
    -- Expanding a scope: load its variables
    local variables_reference = tonumber(parent_id:match("^scope_(%d+)"))

    if variables_reference then
      -- Use DAP call to get variables
      local response = self.current_frame.stack.thread.session.ref.calls:variables({
        variablesReference = variables_reference,
        threadId = self.current_frame.stack.thread.id,
      }):wait()

      if response and response.variables then
        for i, var_ref in ipairs(response.variables) do
          local node = variableToNode(var_ref, parent_id)
          table.insert(nodes, node)
        end
      end
    end
    renderer.show_nodes(nodes, state, parent_id, callback)
  else
    -- Expanding a variable: load its child properties
    -- Extract variable reference from the encoded ID
    local ref_str = parent_id:match("var_(%d+)$")
    if ref_str then
      local variables_reference = tonumber(ref_str)

      -- Use DAP call to get child variables
      local response = self.current_frame.stack.thread.session.ref.calls:variables({
        variablesReference = variables_reference,
        threadId = self.current_frame.stack.thread.id,
      }):wait()

      if response and response.variables then
        for _, var_ref in ipairs(response.variables) do
          table.insert(nodes, variableToNode(var_ref, parent_id))
        end
      end
    end
    renderer.show_nodes(nodes, state, parent_id, callback)
  end
end

---Navigate function for Neo-tree integration
---@type fun(state: neotree.State, path?: string, path_to_reveal?: string, callback?: function, async?: boolean)
function VariablesPlugin:Navigate(state, path, pathToReveal, callback, _async)
  -- Acquire window for display
  renderer.acquire_window(state)

  state.dirty = false

  -- Set position if specified
  if pathToReveal then
    renderer.position.set(state, pathToReveal)
  end

  -- Load and display the variables data
  self:LoadVariablesData(state, nil, callback)
end

local components = require("neo-tree.sources.common.components")

---@type neotree.Source & { plugin: fun(api: Api): neodap.plugins.Variables }
local VariablesSource = {
  name = "variables",
  display_name = "Variables",
  commands = {
    toggle_node = function(state)
      local tree = state.tree
      local node = tree:get_node()

      local commands = require("neo-tree.sources.common.commands")
      commands.toggle_node(state, function()
        -- After expansion, load children if needed
        local tree = state.tree
        local node = tree:get_node()

        if node and not node.loaded and node.has_children then
          local plugin = VariablesPlugin.get()
          if plugin then
            plugin:LoadVariablesData(state, node.id, function()
              -- Mark node as loaded after children are fetched
              node.loaded = true

              -- Force a redraw after loading
              local renderer = require("neo-tree.ui.renderer")
              renderer.redraw(state)
            end)
          end
        end
      end)
    end,
  },
  components = components,
  setup = function(opts, _config)
    -- Ensure we have proper renderers
    if not opts.renderers then
      opts.renderers = {}
    end

    -- Set default renderers if they don't exist
    if not opts.renderers.directory then
      opts.renderers.directory = {
        { "indent" },
        { "icon" },
        { "name",  use_git_status_colors = false },
      }
    end

    if not opts.renderers.file then
      opts.renderers.file = {
        { "indent" },
        { "icon" },
        { "name",  use_git_status_colors = false },
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

    plugin:Navigate(state, path, pathToReveal, callback, async)
  end,

  Plugin = VariablesPlugin,
  plugin = function(api)
    return VariablesPlugin.plugin(api)
  end,
}

return VariablesSource
