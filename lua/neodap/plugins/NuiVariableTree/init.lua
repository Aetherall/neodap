local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local NuiTree = require("nui.tree")
local NuiPopup = require("nui.popup")

local M = {}

---@class neodap.plugin.NuiVariableTreeProps
---@field api Api
---@field logger Logger

---@class neodap.plugin.NuiVariableTree: neodap.plugin.NuiVariableTreeProps
---@field new Constructor<neodap.plugin.NuiVariableTreeProps>
---@field tree_instance NuiTree
---@field tree_popup NuiPopup
local NuiVariableTree = Class()

NuiVariableTree.name = "NuiVariableTree"
NuiVariableTree.description = "Plugin to display variables in a NUI tree"

function M.plugin(api)
  local logger = Logger.get("Plugin:NuiVariableTree")

  M.instance = NuiVariableTree:new({
    api = api,
    logger = logger,
  })

  vim.api.nvim_create_user_command("NuiVariableTreeToggle", function()
    M.instance:Toggle()
  end, {
    desc = "Toggle the variable tree",
  })
  vim.api.nvim_create_user_command("NuiVariableTreeShow", function()
    M.instance:Show()
  end, {
    desc = "Show the variable tree",
  })
  vim.api.nvim_create_user_command("NuiVariableTreeHide", function()
    M.instance:Hide()
  end, {
    desc = "Hide the variable tree",
  })

  return M.instance
end

function NuiVariableTree:new(props)
  self.api = props.api
  self.logger = props.logger
  self.tree_instance = nil
  self.tree_popup = nil
end

function NuiVariableTree:init_ui()
  local bufnr = vim.api.nvim_create_buf(false, true)

  local tree_instance = NuiTree({
    bufnr = bufnr,
    nodes = {},
  })

  local tree_popup = NuiPopup({
    border = {
      style = "single",
      text = {
        top = "Variables",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:Normal",
    },
    content = tree_instance,
    relative = "editor",
    position = { row = 0, col = 0 },
    size = { width = 80, height = 24 },
  })
  return tree_instance, tree_popup
end

function NuiVariableTree:Toggle()
  if self.tree_popup and self.tree_popup:is_mounted() then
    self:Hide()
  else
    self:Show()
  end
end

function NuiVariableTree:Show()
  if not self.tree_popup then
    self.tree_instance, self.tree_popup = self:init_ui()
  end

  self.logger:info("self before mount:", self)
  self.logger:info("self.tree_popup before mount:", self.tree_popup)

  self.tree_popup:mount()

  local session = nil
  for s in self.api:eachSession() do
    session = s -- Assuming the last session is the active one
  end

  if session then
    self:Update(session)
  else
    self.logger:warn("No active session found to update variable tree.")
  end
end

function NuiVariableTree:Hide()
  if self.tree_popup then
    self.tree_popup:unmount()
  end
end

function NuiVariableTree:Clear()
  self.logger:info("Clearing variable tree")
  if self.tree_popup then
    self.tree_instance:set_nodes({}) -- Use the stored NuiTree instance
  end
end

function NuiVariableTree:Update(session)
  self.logger:info("Updating variable tree for session:", session)
  if not session then
    self.logger:error("Update called with a nil session!")
    return
  end

  local thread = session:getPrimaryThread()
  if not thread then
    self.logger:warn("No primary thread found in session")
    return
  end

  local scopes = thread:getScopes()
  self.logger:info("Found scopes:", scopes)
  local function create_variable_nodes(variable)
    local name = variable.name
    local value = variable.value or ""
    local display_value = string.format("%s = %s", name, value)

    local children = {}
    if variable.variablesReference and variable.variablesReference > 0 then
      local variables = variable:getVariables()
      for _, child_var in ipairs(variables) do
        table.insert(children, create_variable_nodes(child_var))
      end
    end

    return NuiTree.Node(display_value, {
      id = variable.id,
      children = children,
      expandable = #children > 0,
    })
  end

  local nodes = {}
  for _, scope in ipairs(scopes) do
    local scope_nodes = {}
    local variables = scope:getVariables()
    for _, variable in ipairs(variables) do
      table.insert(scope_nodes, create_variable_nodes(variable))
    end
    table.insert(nodes, NuiTree.Node(scope.name, {
      id = scope.id,
      children = scope_nodes,
      expandable = #scope_nodes > 0,
    }))
  end

  self.logger:info("Setting nodes in the tree")
  self.tree_instance:set_nodes(nodes)
end

function NuiVariableTree:destroy()
  self.logger:info("Destroying NuiVariableTree plugin")
  vim.api.nvim_del_user_command("NuiVariableTreeToggle")
  vim.api.nvim_del_user_command("NuiVariableTreeShow")
  vim.api.nvim_del_user_command("NuiVariableTreeHide")
end

return M

  


