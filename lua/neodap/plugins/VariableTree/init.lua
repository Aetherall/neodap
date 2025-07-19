---@diagnostic disable: access-invisible
-- lua/neodap/plugins/VariableTree/init.lua
local Class = require("neodap.tools.class")
local Logger = require("neodap.tools.logger")
local VariableCore = require("neodap.plugins.VariableCore")

local Popup = require('nui.popup')
local Neotree = require("neo-tree")
local NeotreeSourcesManager = require("neo-tree.sources.manager")

---@class VariableTreePlugin
---@field ShowVariables fun(): nil
---@field HideVariables fun(): nil
---@field ToggleVariables fun(): nil
---@field RefreshNeotree fun(): nil
---@field tryRegisterNeotree fun(): nil
---@field destroy fun(): nil

---@class VariableTreeProps
---@field api Api
---@field logger Logger
---@field variableCore neodap.plugin.VariableCore

---@class VariableTree: VariableTreeProps
---@field new Constructor<VariableTreeProps>
local VariableTree = Class()

VariableTree.name = "VariableTree"
VariableTree.description = "Modern floating window variable tree with dual-pane navigation"

function VariableTree.plugin(api)
  local logger = Logger.get("Plugin:VariableTree")

  local instance = VariableTree:new({
    api = api,
    logger = logger,
    variableCore = api:getPluginInstance(VariableCore)
  })


  instance:init()
  return instance
end

function VariableTree:init()
  -- Initialize instance state
  self.current_frame = nil
  self.cleanup_functions = {}
  self.plugin_destroyed = false
  self.neotree_available = false
  self.source_registered = false
  self.resize_autocmd = nil -- autocmd for VimResized events
  -- Note: Expansion state now managed by Neo-tree internally

  -- Set up Neo-tree source
  self:setupNeotreeSource()

  -- Set up debugging session hooks
  self:setupSessionHooks()

  -- Register vim commands
  self:registerCommands()

  -- Try to register Neo-tree on load
  self:tryRegisterNeotree()
end

function VariableTree:setupNeotreeSource()
  -- Use the separate neo-tree source module
  self.source = require("neodap.plugins.VariableTree.neotree_source")
end

function VariableTree:setupSessionHooks()
  local cleanup_session = self.api:onSession(function(session)
    local cleanup_thread = session:onThread(function(thread)
      local cleanup_stopped = thread:onStopped(function()
        local stack = thread:stack()
        if stack then
          self.current_frame = stack:top()
          -- Update the neo-tree source with current context
          self.source.set_context(self.current_frame, self.variableCore)
          self:RefreshNeotree()


          -- Update popup content if it's open
          if self.popup and self.popup._.mounted then
            self:updateFloatingWindowContent()
          end
        end
      end, { name = self.name .. ".onStopped" })

      local cleanup_continued = thread:onContinued(function()
        self.current_frame = nil
        -- Update the neo-tree source with nil context
        self.source.set_context(nil, self.variableCore)
        self:RefreshNeotree()
      end, { name = self.name .. ".onContinued" })

      table.insert(self.cleanup_functions, cleanup_stopped)
      table.insert(self.cleanup_functions, cleanup_continued)
    end, { name = self.name .. ".onThread" })

    local cleanup_terminated = session:onTerminated(function()
      self.current_frame = nil
      self.source.set_context(nil, self.variableCore)
      self:RefreshNeotree()
    end, { name = self.name .. ".onTerminated" })

    table.insert(self.cleanup_functions, cleanup_thread)
    table.insert(self.cleanup_functions, cleanup_terminated)
  end, { name = self.name .. ".onSession" })

  table.insert(self.cleanup_functions, cleanup_session)
end

function VariableTree:registerCommands()
  -- Clean up existing commands
  local commands = {
    "NeodapVariableTreeShow",
    "NeodapVariableTreeHide",
    "NeodapVariableTreeToggle",
    "NeodapVariableTreeStatus"
  }

  for _, cmd in ipairs(commands) do
    if vim.api.nvim_get_commands({})[cmd] then
      vim.api.nvim_del_user_command(cmd)
    end
  end

  -- Register new commands
  vim.api.nvim_create_user_command("NeodapVariableTreeShow", function()
    self:ShowVariables()
  end, {})

  vim.api.nvim_create_user_command("NeodapVariableTreeHide", function()
    self:HideVariables()
  end, {})

  vim.api.nvim_create_user_command("NeodapVariableTreeToggle", function()
    self:ToggleVariables()
  end, {})

  vim.api.nvim_create_user_command("NeodapVariableTreeStatus", function()
    self:showStatus()
  end, {})
end

-- PascalCase method for auto-wrapping (expensive UI operation)
function VariableTree:ShowVariables()
  if not self.current_frame then
    vim.notify("No active debugging frame", vim.log.levels.INFO)
    return
  end

  -- Use Neo-tree floating window (which uses nui internally)
  if self.neotree_available then
    local ok, err = pcall(vim.cmd, "Neotree float neodap-variable-tree")
    if ok then
      self.logger:debug("Neo-tree variable window opened in floating mode")
      return
    else
      self.logger:debug("Neo-tree failed, falling back to popup:", err)
    end
  end

  -- Fallback to floating window implementation
  self:createFloatingVariableWindow()
end

function VariableTree:HideVariables()
  -- Try to close Neo-tree first
  if self.neotree_available then
    pcall(vim.cmd, "Neotree close")
  end

  -- Close popup if it exists
  if self.popup and self.popup._.mounted then
    self.popup:unmount()
  end

  -- Clean up resize handlers
  if self.resize_autocmd then
    vim.api.nvim_del_autocmd(self.resize_autocmd)
    self.resize_autocmd = nil
  end
end

function VariableTree:ToggleVariables()
  if not self.current_frame then
    vim.notify("No active debugging frame", vim.log.levels.INFO)
    return
  end

  -- Check if we have any variable windows open
  local has_neotree_open = false
  local has_popup_open = (self.popup and self.popup._.mounted) or false


  if self.neotree_available then
    -- Try to check if neo-tree is open (this is a simplified check)
    local ok, _ = pcall(vim.cmd, "Neotree show neodap-variable-tree")
    if ok then
      has_neotree_open = true
      pcall(vim.cmd, "Neotree close")
    end
  end

  -- If any variable window is open, close all; otherwise open
  if has_neotree_open or has_popup_open then
    self:HideVariables()
  else
    self:ShowVariables()
  end
end

function VariableTree:showStatus()
  if not self.current_frame then
    vim.notify("VariableTree: No active debugging frame", vim.log.levels.INFO)
    return
  end

  local scopes = self.current_frame:scopes()
  local scope_count = scopes and #scopes or 0
  vim.notify("VariableTree: Active frame with " .. scope_count .. " scopes", vim.log.levels.INFO)
end

function VariableTree:tryRegisterNeotree()
  if self.source_registered then return end

  local ok, neotree = pcall(require, "neo-tree")
  if ok then
    self.neotree_available = true

    -- Register our source first - this creates the module that neo-tree expects
    local manager_ok, manager = pcall(require, "neo-tree.sources.manager")
    if manager_ok and manager.register then
      manager.register(self.source)
      self.source_registered = true

      -- Now setup neo-tree with our source included
      local current_sources = vim.g.neo_tree_sources or { "filesystem", "buffers", "git_status" }
      if not vim.tbl_contains(current_sources, "neodap-variable-tree") then
        table.insert(current_sources, "neodap-variable-tree")
      end

      neotree.setup({
        sources = current_sources,
        ["neodap-variable-tree"] = {
          window = {
            position = "float", -- Use floating window (nui popup)
            mappings = {
              ["<cr>"] = "toggle_node",
              ["<space>"] = "toggle_node",
              ["o"] = "toggle_node",
            },
          },
          popup = {
            size = {
              height = "60%",
              width = "50%",
            },
            position = "50%", -- center the popup
          },
        },
      })
    end
  end
end

-- PascalCase method for auto-wrapping (expensive UI operation)
function VariableTree:RefreshNeotree()
  if not self.neotree_available then return end

  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if ok and manager then
    local state = manager.get_state("neodap-variable-tree")
    if state and state.tree then
      -- Refresh the tree
      manager.refresh("neodap-variable-tree")
    end
  end
end

-- Simplified: Neo-tree handles the nui popup internally
-- We just need to configure it properly in the setup

-- Calculate optimal window size based on content
function VariableTree:calculateContentSize(lines)
  if not lines or #lines == 0 then
    return { width = 40, height = 10 }
  end

  -- Calculate optimal width based on content
  local max_width = 0
  for _, line in ipairs(lines) do
    local display_width = vim.fn.strdisplaywidth(line)
    max_width = math.max(max_width, display_width)
  end

  -- Add padding for borders and some breathing room
  local content_width = max_width + 4
  local content_height = #lines + 2

  -- Apply constraints based on screen size
  local screen_width = vim.o.columns
  local screen_height = vim.o.lines

  local constraints = {
    min_width = 40,
    max_width = math.floor(screen_width * 0.8),
    min_height = 10,
    max_height = math.floor(screen_height * 0.7)
  }

  local optimal_width = math.max(constraints.min_width, math.min(content_width, constraints.max_width))
  local optimal_height = math.max(constraints.min_height, math.min(content_height, constraints.max_height))

  self.logger:debug("Calculated content size:", {
    content = { width = content_width, height = content_height },
    constraints = constraints,
    optimal = { width = optimal_width, height = optimal_height }
  })

  return { width = optimal_width, height = optimal_height }
end

-- nui.popup-based window implementation (replaces manual floating window)
function VariableTree:createFloatingVariableWindow()
  if not self.current_frame then
    return
  end

  -- Close existing popup if open
  if self.popup and self.popup._.mounted then
    self.popup:unmount()
  end

  -- Generate content and calculate optimal size
  local lines = self:generateVariableTreeContent()
  local optimal_size = self:calculateContentSize(lines)

  -- Update the popup layout with the new size
  self.popup:update_layout({ size = optimal_size })

  -- Mount the popup
  self.popup:mount()

  -- Set up content
  self:setPopupContent(lines)

  -- Set up key mappings
  self:setupPopupKeymaps()

  -- Set up VimResized autocmd for dynamic resizing
  self:setupResizeHandler()

  self.logger:debug("Created nui.popup with size:", optimal_size)
end

-- Set content in the nui.popup
function VariableTree:setPopupContent(lines)
  if not self.popup or not self.popup.bufnr then
    return
  end

  -- Make buffer temporarily modifiable
  vim.bo[self.popup.bufnr].modifiable = true

  -- Set content
  vim.api.nvim_buf_set_lines(self.popup.bufnr, 0, -1, false, lines)

  -- Make buffer read-only again
  vim.bo[self.popup.bufnr].modifiable = false
end

-- Set up key mappings for the popup
function VariableTree:setupPopupKeymaps()
  if not self.popup then
    return
  end

  -- Toggle scope/variable expansion - simplified to use Neo-tree patterns when possible
  self.popup:map("n", "<CR>", function()
    self.logger:debug("=== CR keymap triggered ===")
    -- For now, keep existing logic but this should be simplified in next iteration
    self:ToggleScopeAtCursor()
  end, { noremap = true, silent = true })

  -- Close window
  self.popup:map("n", "q", function()
    self:HideVariables()
  end, { noremap = true, silent = true })

  self.popup:map("n", "<Esc>", function()
    self:HideVariables()
  end, { noremap = true, silent = true })
end

-- Set up VimResized autocmd for dynamic resizing
function VariableTree:setupResizeHandler()
  if self.resize_autocmd then
    vim.api.nvim_del_autocmd(self.resize_autocmd)
  end

  self.resize_autocmd = vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      if self.popup and self.popup._.mounted then
        self:resizePopupToContent()
      end
    end,
    group = vim.api.nvim_create_augroup("NeodapVariableTreeResize", { clear = false }),
    desc = "VariableTree: Handle terminal resize"
  })
end

-- Resize popup based on current content
function VariableTree:resizePopupToContent()
  if not self.popup or not self.popup._.mounted then
    return
  end

  local lines = self:generateVariableTreeContent()
  local new_size = self:calculateContentSize(lines)

  self.popup:update_layout({ size = new_size })

  self.logger:debug("Resized popup to:", new_size)
end

-- Simplified variable content generation - expansion state managed by Neo-tree
function VariableTree:addVariablesToLines(variables, lines, indent_level, scope_name)
  indent_level = indent_level or 1
  scope_name = scope_name or "unknown"
  local indent = string.rep("  ", indent_level)

  for _, var in ipairs(variables) do
    local formatted_value = self.variableCore:formatVariableValue(var)
    local has_children = var.variablesReference and var.variablesReference > 0

    if has_children then
      -- Variable with children - always show as expandable (collapsed by default)
      local prefix = "▶ "
      local var_line = string.format("%s%s%s = %s", indent, prefix, var.name, formatted_value)
      if var.type then
        var_line = var_line .. " : " .. var.type
      end
      table.insert(lines, var_line)
    else
      -- Leaf variable - no expansion
      local var_line = string.format("%s  %s = %s", indent, var.name, formatted_value)
      if var.type then
        var_line = var_line .. " : " .. var.type
      end
      table.insert(lines, var_line)
    end
  end
end

function VariableTree:generateVariableTreeContent()
  if not self.current_frame then
    return {}
  end

  local scopes = self.current_frame:scopes()
  local lines = {}

  for _, scope in ipairs(scopes) do
    -- Auto-expand non-expensive scopes, otherwise keep collapsed
    local should_expand = self.variableCore:shouldAutoExpand(scope.ref)
    local prefix = should_expand and "▼ " or "▶ "
    table.insert(lines, prefix .. scope.ref.name)

    -- Add variables if auto-expanded
    if should_expand then
      local variables = self.current_frame:variables(scope.ref.variablesReference)
      if variables then
        self:addVariablesToLines(variables, lines, 1, scope.ref.name)
      end
    end
  end

  return lines
end

-- Legacy method removed - now using setPopupContent instead

function VariableTree:updateFloatingWindowContent()
  if not self.popup or not self.popup._.mounted then
    return
  end

  -- Store current cursor position
  local cursor_pos = nil
  if self.popup.winid and vim.api.nvim_win_is_valid(self.popup.winid) then
    cursor_pos = vim.api.nvim_win_get_cursor(self.popup.winid)
  end

  -- Generate new content
  local lines = self:generateVariableTreeContent()

  -- Calculate new optimal size and resize if needed
  local new_size = self:calculateContentSize(lines)
  self.popup:update_layout({ size = new_size })

  -- Update content
  self:setPopupContent(lines)

  -- Restore cursor position if possible
  if cursor_pos and self.popup.winid and vim.api.nvim_win_is_valid(self.popup.winid) then
    -- Ensure cursor position is within valid range
    local line_count = #lines
    if cursor_pos[1] > line_count then
      cursor_pos[1] = line_count > 0 and line_count or 1
    end
    pcall(vim.api.nvim_win_set_cursor, self.popup.winid, cursor_pos)
  end

  self.logger:debug("Updated popup content with dynamic resize to:", new_size)
end

-- Simplified toggle function - primarily for popup fallback mode
function VariableTree:ToggleScopeAtCursor()
  self.logger:debug("=== ToggleScopeAtCursor called (simplified mode) ===")

  if not self.popup or not self.popup:is_mounted() or not self.popup.bufnr then
    self.logger:debug("No valid popup")
    return
  end

  local line_num = vim.api.nvim_win_get_cursor(self.popup.winid)[1]
  local line = vim.api.nvim_buf_get_lines(self.popup.bufnr, line_num - 1, line_num, false)[1]

  self.logger:debug("Line number:", line_num, "Line content:", vim.inspect(line))

  if not line then
    self.logger:debug("No line found")
    return
  end

  -- Inform user about Neo-tree recommendation
  vim.notify("Use Neo-tree for better variable navigation: :Neotree show neodap-variable-tree", vim.log.levels.INFO)
end

-- Legacy method for compatibility - now just delegates to ShowVariables
function VariableTree:createVariableWindow()
  self:ShowVariables()
end

function VariableTree:destroy()
  self.plugin_destroyed = true

  -- Clean up all event handlers
  for _, cleanup in ipairs(self.cleanup_functions) do
    if cleanup then
      cleanup()
    end
  end
  self.cleanup_functions = {}

  -- Close any open Neo-tree windows
  self:HideVariables()


  -- Clean up commands
  local commands = {
    "NeodapVariableTreeShow",
    "NeodapVariableTreeHide",
    "NeodapVariableTreeToggle",
    "NeodapVariableTreeStatus"
  }

  for _, cmd in ipairs(commands) do
    if vim.api.nvim_get_commands({})[cmd] then
      vim.api.nvim_del_user_command(cmd)
    end
  end
end

-- Legacy method for compatibility - now just delegates to ShowVariables
function VariableTree:createVariableWindow()
  self:ShowVariables()
end

return VariableTree
