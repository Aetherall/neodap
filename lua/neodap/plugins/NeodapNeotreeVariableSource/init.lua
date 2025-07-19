local Class = require("neodap.tools.class")
local VariableCore = require("neodap.plugins.VariableCore")
local nio = require("nio")

---@class NeodapNeotreeVariableSourceProps
---@field api Api

---@class NeodapNeotreeVariableSource: NeodapNeotreeVariableSourceProps
---@field new Constructor<NeodapNeotreeVariableSourceProps>
local NeodapNeotreeVariableSource = Class()

-- Neo-tree source interface
NeodapNeotreeVariableSource.name = "neodap.plugins.NeodapNeotreeVariableSource"
NeodapNeotreeVariableSource.display_name = "🐛 Variables"

function NeodapNeotreeVariableSource.plugin(api)
  local instance = NeodapNeotreeVariableSource:new({ api = api })
  instance:init()
  return instance
end

-- Class variable to store current instance for static methods
NeodapNeotreeVariableSource._current_instance = nil

-- Neo-tree source interface methods (static)
function NeodapNeotreeVariableSource.navigate(state, path)
  local instance = NeodapNeotreeVariableSource._current_instance
  if not instance or not instance.current_frame then
    local renderer = require("neo-tree.ui.renderer")
    renderer.show_nodes({}, state)
    return
  end

  -- Build nodes for scopes
  local nodes = {}
  for _, scope in ipairs(instance.current_frame:scopes()) do
    table.insert(nodes, {
      id = "scope_" .. scope.ref.variablesReference,
      name = scope.ref.name,
      type = "scope",
      has_children = true,
      loaded = instance.variableCore:shouldAutoExpand(scope.ref)
    })
  end

  local renderer = require("neo-tree.ui.renderer")
  renderer.show_nodes(nodes, state)
end

-- Get items method for async loading (static)
NeodapNeotreeVariableSource.get_items = nio.create(function(state, parent_id, callback)
  local instance = NeodapNeotreeVariableSource._current_instance
  if not instance or not instance.current_frame then return callback({}) end

  if not parent_id then
    -- Scopes (root level)
    local nodes = {}
    for _, scope in ipairs(instance.current_frame:scopes()) do
      table.insert(nodes, {
        id = "scope_" .. scope.ref.variablesReference,
        name = scope.ref.name,
        type = "scope",
        has_children = true,
        loaded = instance.variableCore:shouldAutoExpand(scope.ref)
      })
    end
    callback(nodes)
  else
    -- Variables for a scope
    local ref = tonumber(parent_id:match("scope_(%d+)"))
    if ref then
      local nodes = {}
      for _, var in ipairs(instance.current_frame:variables(ref)) do
        local formatted_name = var.name
        if var.value then
          local formatted_value = instance.variableCore:formatVariableValue(var)
          formatted_name = var.name .. " = " .. formatted_value
          if var.type then
            formatted_name = formatted_name .. " : " .. var.type
          end
        end
        table.insert(nodes, {
          id = parent_id .. "." .. var.name,
          name = formatted_name,
          type = "variable",
          has_children = var.variablesReference and var.variablesReference > 0
        })
      end
      callback(nodes)
    else
      callback({})
    end
  end
end, 1)

-- Setup method for Neo-tree source (static)
function NeodapNeotreeVariableSource.setup(config, global_config)
  -- Optional setup logic
end

-- Setup Neo-tree integration via NeotreeAutoIntegration service
function NeodapNeotreeVariableSource:setupNeotreeIntegration()
  local NeotreeAutoIntegration = require("neodap.plugins.NeotreeAutoIntegration")
  local integration_service = self.api:getPluginInstance(NeotreeAutoIntegration)
  
  -- Register ourselves with the hybrid auto-integration service
  local options = {
    default_config = {
      window = {
        position = "float",
        mappings = {
          ["<cr>"] = "toggle_node",
          ["<space>"] = "toggle_node", 
          ["o"] = "toggle_node",
          ["q"] = "close_window",
          ["<esc>"] = "close_window",
        },
      },
      popup = {
        size = { height = "60%", width = "50%" },
        position = "50%", -- center
      },
    },
    silent = false -- Show user feedback about auto-registration
  }
  
  local success = integration_service:registerSource(NeodapNeotreeVariableSource, options)
  if success then
    self.neotree_registered = true
  end
end

function NeodapNeotreeVariableSource:init()
  self.current_frame = nil
  self.variableCore = self.api:getPluginInstance(VariableCore)
  self.neotree_registered = false

  -- Set this instance as the current one for static methods
  NeodapNeotreeVariableSource._current_instance = self

  -- Smart hybrid self-registration
  self:setupNeotreeIntegration()

  -- Hook into DAP events
  self.api:onSession(function(session)
    session:onThread(function(thread)
      thread:onStopped(function()
        local stack = thread:stack()
        if stack then
          self.current_frame = stack:top()
          -- Refresh Neo-tree
          local manager_ok, manager = pcall(require, "neo-tree.sources.manager")
          if manager_ok and manager then
            pcall(manager.refresh, self.name)
          end
        end
      end)
      thread:onContinued(function()
        self.current_frame = nil
        -- Refresh Neo-tree
        local manager_ok, manager = pcall(require, "neo-tree.sources.manager")
        if manager_ok and manager then
          pcall(manager.refresh, self.name)
        end
      end)
    end)
  end)
end

return NeodapNeotreeVariableSource
