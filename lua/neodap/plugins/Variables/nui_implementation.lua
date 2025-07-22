-- Direct NUI Implementation for Variables Plugin
-- This is a proof of concept showing how simple it would be

local Class = require('neodap.tools.class')
local NuiSplit = require("nui.split")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local IdGenerator = require('neodap.plugins.Variables.id_generator')

---@class VariablesTreeNui
---@field api Api
---@field current_frame? Frame
---@field windows table<number, {split: NuiSplit, tree: NuiTree}>
local VariablesTreeNui = Class()

function VariablesTreeNui:new(props)
  self.api = props.api
  self.current_frame = nil
  self.windows = {}

  -- Setup DAP event handlers
  self:setupEventHandlers()

  -- Create user commands
  self:setupCommands()
end

function VariablesTreeNui:setupEventHandlers()
  self.api:onSession(function(session)
    session:onThread(function(thread)
      thread:onStopped(function()
        local stack = thread:stack()
        self.current_frame = stack and stack:top() or nil
        self:refreshAllWindows()
      end)

      thread:onContinued(function()
        self.current_frame = nil
        self:refreshAllWindows()
      end)
    end)
  end)
end

function VariablesTreeNui:setupCommands()
  vim.api.nvim_create_user_command("VariablesShow", function()
    self:show()
  end, { desc = "Show variables window" })

  vim.api.nvim_create_user_command("VariablesClose", function()
    self:close()
  end, { desc = "Close variables window" })

  vim.api.nvim_create_user_command("VariablesToggle", function()
    self:toggle()
  end, { desc = "Toggle variables window" })
end

function VariablesTreeNui:show()
  local tabpage = vim.api.nvim_get_current_tabpage()

  -- Check if already open
  local win = self.windows[tabpage]
  if win and vim.api.nvim_win_is_valid(win.split.winid) then
    vim.api.nvim_set_current_win(win.split.winid)
    return
  end

  -- Create split window
  local split = NuiSplit({
    relative = "editor",
    position = "left",
    size = "30%",
    buf_options = {
      buftype = "nofile",
      bufhidden = "hide",
      swapfile = false,
      modifiable = false,
    },
  })

  split:mount()

  -- Create tree
  local tree = NuiTree({
    bufnr = split.bufnr,
    nodes = self:getRootNodes(),
    get_node_id = function(node) return node.id end,
    prepare_node = function(node)
      return self:prepareNodeLine(node)
    end,
  })

  -- Setup keybindings
  self:setupKeybindings(split, tree)

  -- Store reference
  self.windows[tabpage] = {
    split = split,
    tree = tree,
  }

  -- Initial render
  tree:render()

  -- Set buffer name for display
  vim.api.nvim_buf_set_name(split.bufnr, "Variables")
end

function VariablesTreeNui:setupKeybindings(split, tree)
  local map = function(key, fn)
    vim.keymap.set("n", key, fn, {
      buffer = split.bufnr,
      nowait = true,
      silent = true,
    })
  end

  -- Toggle expansion
  map("<CR>", function() self:toggleNode(tree) end)
  map("o", function() self:toggleNode(tree) end)
  map("<Space>", function() self:toggleNode(tree) end)

  -- Close window
  map("q", function() self:close() end)

  -- Auto-close on leave
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = split.bufnr,
    callback = function()
      -- Optional: auto-close on leave
      -- self:close()
    end,
  })
end

function VariablesTreeNui:prepareNodeLine(node)
  local line = NuiLine()

  -- Indentation
  local indent = string.rep("  ", node:get_depth() - 1)
  line:append(indent)

  -- Expand indicator
  if node:has_children() then
    local indicator = node:is_expanded() and "▾ " or "▸ "
    line:append(indicator, "NeoTreeExpander")
  else
    line:append("  ")
  end

  -- Icon based on type
  if node.type == "scope" then
    line:append("󰅩 ", "NeoTreeDirectoryIcon")
  elseif node.type == "variable" then
    if node.is_expandable then
      line:append("󰅩 ", "NeoTreeDirectoryIcon")
    else
      line:append("󰀫 ", "NeoTreeFileIcon")
    end
  end

  -- Text
  line:append(node.name or node.text)

  return line
end

function VariablesTreeNui:toggleNode(tree)
  local node = tree:get_node()
  if not node then return end

  if node:has_children() then
    if node:is_expanded() then
      node:collapse()
    else
      -- Load children if needed
      if not node.loaded then
        self:loadNodeChildren(tree, node)
        node.loaded = true
      end
      node:expand()
    end
    tree:render()
  end
end

function VariablesTreeNui:loadNodeChildren(tree, node)
  if not self.current_frame then
    return
  end

  local children = {}

  -- Load based on node type
  if node.type == "scope" then
    -- Load variables for scope
    local variables = self.current_frame:variables(node.variablesReference)
    if variables then
      for _, var in ipairs(variables) do
        table.insert(children, self:createVariableNode(var, node.id))
      end
    end
  elseif node.type == "variable" and node.variableReference then
    -- Load child variables
    local variables = self.current_frame:variables(node.variableReference)
    if variables then
      for _, var in ipairs(variables) do
        table.insert(children, self:createVariableNode(var, node.id))
      end
    end
  end

  -- Add children to tree
  tree:set_nodes(children, node.id)
end

function VariablesTreeNui:createVariableNode(var, parent_id)
  local id = IdGenerator.forVariable(parent_id, var, tonumber("0" .. var.name))
  local is_expandable = var.variablesReference and var.variablesReference > 0

  return NuiTree.Node({
    id = id,
    name = self:formatVariable(var),
    text = self:formatVariable(var),
    type = "variable",
    is_expandable = is_expandable,
    variableReference = var.variablesReference,
    loaded = false,
  }, is_expandable and {} or nil) -- Empty children if expandable
end

function VariablesTreeNui:formatVariable(var)
  local name = var.name or "<anonymous>"
  local value = var.value or ""
  local type_hint = var.type and (" (" .. var.type .. ")") or ""

  if var.variablesReference and var.variablesReference > 0 then
    return name .. type_hint
  end

  -- Truncate long values
  if #value > 50 then
    value = value:sub(1, 47) .. "..."
  end

  return name .. ": " .. value
end

function VariablesTreeNui:getRootNodes()
  if not self.current_frame then
    return {
      NuiTree.Node({
        id = "no-debug",
        name = "No active debug session",
        text = "No active debug session",
        type = "info",
      })
    }
  end

  local nodes = {}
  local scopes = self.current_frame:scopes()
  if scopes then
    for _, scope in ipairs(scopes) do
      local id = IdGenerator.forScope(scope.ref)
      table.insert(nodes, NuiTree.Node({
        id = id,
        name = scope.ref.name,
        text = scope.ref.name,
        type = "scope",
        variablesReference = scope.ref.variablesReference,
        expensive = scope.ref.expensive,
        loaded = false,
      }, {})) -- Empty children, will load on expand
    end
  end

  return nodes
end

function VariablesTreeNui:refreshAllWindows()
  for tabpage, win in pairs(self.windows) do
    if vim.api.nvim_tabpage_is_valid(tabpage) and
        vim.api.nvim_win_is_valid(win.split.winid) then
      -- Reset tree with new data
      local nodes = self:getRootNodes()
      win.tree = NuiTree({
        bufnr = win.split.bufnr,
        nodes = nodes,
        get_node_id = function(node) return node.id end,
        prepare_node = function(node)
          return self:prepareNodeLine(node)
        end,
      })
      win.tree:render()
    else
      -- Clean up invalid windows
      self.windows[tabpage] = nil
    end
  end
end

function VariablesTreeNui:close()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local win = self.windows[tabpage]

  if win then
    win.split:unmount()
    self.windows[tabpage] = nil
  end
end

function VariablesTreeNui:toggle()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local win = self.windows[tabpage]

  if win and vim.api.nvim_win_is_valid(win.split.winid) then
    self:close()
  else
    self:show()
  end
end

return VariablesTreeNui
