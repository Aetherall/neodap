-- VariablesBuffer Service Plugin
-- Provides fully functional buffers with variables tree rendering and navigation

local BasePlugin = require('neodap.plugins.BasePlugin')
local Logger = require('neodap.tools.logger')
local NuiTree = require("nui.tree")

-- ========================================
-- PLUGIN CLASS
-- ========================================

---@class VariablesBuffer: BasePlugin
local VariablesBuffer = BasePlugin:extend()

VariablesBuffer.name = "VariablesBuffer"

-- ========================================
-- PLUGIN INITIALIZATION
-- ========================================

function VariablesBuffer.plugin(api)
  return BasePlugin.createPlugin(api, VariablesBuffer)
end

function VariablesBuffer:listen()
  self.logger:info("Initializing VariablesBuffer service plugin")
  -- Service plugin - no event handlers needed
  self.logger:info("VariablesBuffer service plugin initialized")
end

-- ========================================
-- VARIABLE PRESENTATION STRATEGY
-- ========================================

local VariablePresentation = {
  -- Visual representation (icon + highlight + truncation)
  styles = {
    -- JavaScript primitives
    string = { icon = "󰉿", highlight = "String", truncate = 35 },
    number = { icon = "󰎠", highlight = "Number", truncate = 40 },
    boolean = { icon = "◐", highlight = "Boolean", truncate = 40 },
    undefined = { icon = "󰟢", highlight = "Constant", truncate = 40 },
    null = { icon = "󰟢", highlight = "Constant", truncate = 40 },

    -- JavaScript objects/collections
    object = { icon = "󰅩", highlight = "Structure", truncate = 30 },
    array = { icon = "󰅪", highlight = "Structure", truncate = 30 },
    function_js = { icon = "󰊕", highlight = "Function", truncate = 25 },

    -- Generic fallbacks
    default = { icon = "󰀘", highlight = "Normal", truncate = 40 },
    scope = { icon = "📁", highlight = "Directory", truncate = 50 }
  }
}

function VariablePresentation.formatVariable(variable)
  local type_key = variable.ref.type or "default"
  local style = VariablePresentation.styles[type_key] or VariablePresentation.styles.default
  
  local name = variable.ref.name or "unnamed"
  local value = variable.ref.value or ""
  
  -- Truncate value if too long
  if #value > style.truncate then
    value = string.sub(value, 1, style.truncate - 3) .. "..."
  end
  
  -- Format: icon name = value
  local text = string.format("%s %s = %s", style.icon, name, value)
  
  return {
    text = text,
    highlight = style.highlight,
    expandable = variable.ref.variablesReference and variable.ref.variablesReference > 0
  }
end

function VariablePresentation.formatScope(scope)
  local style = VariablePresentation.styles.scope
  local name = scope.ref.name or "unnamed scope"
  
  return {
    text = string.format("%s %s", style.icon, name),
    highlight = style.highlight,
    expandable = not scope.ref.expensive  -- Auto-expand non-expensive scopes
  }
end

-- ========================================
-- BUFFER CONTRACT IMPLEMENTATION
-- ========================================

---Create a fully functional variables buffer with navigation
---@param frame api.Frame The frame to show variables for
---@param options table? Optional configuration
---@return table buffer_handle Buffer contract implementation
function VariablesBuffer:createBuffer(frame, options)
  local opts = vim.tbl_extend("force", {
    compact = false,      -- Compact rendering for small spaces
    auto_refresh = false, -- Auto-refresh on frame changes
  }, options or {})
  
  self.logger:debug("Creating variables buffer for frame " .. (frame.ref.id or "unknown"))
  
  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
  vim.api.nvim_buf_set_name(bufnr, 'Variables[' .. (frame.ref.id or 'unknown') .. ']')
  
  -- Initialize buffer state
  local buffer_state = {
    frame = frame,
    options = opts,
    tree_data = {},
    cursor_line = 1,
    expanded_nodes = {}
  }
  
  -- Render initial content (async operation)
  self:RenderTreeToBuffer(bufnr, buffer_state)
  
  -- Setup navigation
  self:setupBufferNavigation(bufnr, buffer_state)
  
  -- Return buffer handle (contract implementation)
  return {
    bufnr = bufnr,
    refresh = function()
      self:RenderTreeToBuffer(bufnr, buffer_state)
    end,
    close = function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end,
    metadata = {
      frame_id = frame.ref.id,
      compact = opts.compact,
      auto_refresh = opts.auto_refresh
    }
  }
end

-- ========================================
-- TREE RENDERING
-- ========================================

function VariablesBuffer:RenderTreeToBuffer(bufnr, buffer_state)
  local frame = buffer_state.frame
  local opts = buffer_state.options
  
  self.logger:debug("Rendering variables tree to buffer")
  
  -- Get scopes from frame
  self.logger:debug("Getting scopes from frame: " .. (frame.ref.id or "unknown"))
  local scopes = frame:scopes()
  self.logger:debug("Scopes result: " .. vim.inspect(scopes))
  if not scopes or type(scopes) ~= "table" or #scopes == 0 then
    self.logger:warn("No scopes available from frame - scopes: " .. vim.inspect(scopes))
    self:renderEmptyBuffer(bufnr, "No variables available")
    return
  end
  
  -- Prepare tree data
  local tree_lines = {}
  local line_to_node = {}  -- Map line numbers to tree nodes for navigation
  
  for _, scope in ipairs(scopes) do
    if scope then
      local scope_info = VariablePresentation.formatScope(scope)
      table.insert(tree_lines, scope_info.text)
      line_to_node[#tree_lines] = {
        type = "scope",
        scope = scope,
        expandable = scope_info.expandable,
        expanded = buffer_state.expanded_nodes[scope.ref.name] or false
      }
      
      -- If scope is expanded, show its variables
      if buffer_state.expanded_nodes[scope.ref.name] then
        local variables = scope:variables()
        if variables and #variables > 0 then
          for _, variable in ipairs(variables) do
            if variable then
              local var_info = VariablePresentation.formatVariable(variable)
              table.insert(tree_lines, "  " .. var_info.text)  -- Indent variables
              line_to_node[#tree_lines] = {
                type = "variable",
                variable = variable,
                scope = scope,
                expandable = var_info.expandable,
                expanded = buffer_state.expanded_nodes[variable.ref.name] or false
              }
            end
          end
        end
      end
    end
  end
  
  -- Update buffer state
  buffer_state.tree_data = line_to_node
  
  -- Render to buffer
  if #tree_lines == 0 then
    self:renderEmptyBuffer(bufnr, "No variables found")
  else
    vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, tree_lines)
    vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
    
    -- Restore cursor position
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        local windows = vim.fn.win_findbuf(bufnr)
        if #windows > 0 then
          vim.api.nvim_win_set_cursor(windows[1], {buffer_state.cursor_line, 0})
        end
      end
    end)
  end
end

function VariablesBuffer:renderEmptyBuffer(bufnr, message)
  local lines = {
    "",
    "  " .. (message or "No content available"),
    "",
    "  Press 'q' to close"
  }
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
end

-- ========================================
-- BUFFER NAVIGATION
-- ========================================

function VariablesBuffer:setupBufferNavigation(bufnr, buffer_state)
  local map_opts = { buffer = bufnr, noremap = true, silent = true }
  
  -- Navigation
  vim.keymap.set('n', 'j', function() self:navigateNext(bufnr, buffer_state) end, map_opts)
  vim.keymap.set('n', 'k', function() self:navigatePrev(bufnr, buffer_state) end, map_opts)
  vim.keymap.set('n', '<Down>', function() self:navigateNext(bufnr, buffer_state) end, map_opts)
  vim.keymap.set('n', '<Up>', function() self:navigatePrev(bufnr, buffer_state) end, map_opts)
  
  -- Expansion/collapse
  vim.keymap.set('n', 'l', function() self:expandCurrent(bufnr, buffer_state) end, map_opts)
  vim.keymap.set('n', 'h', function() self:collapseCurrent(bufnr, buffer_state) end, map_opts)
  vim.keymap.set('n', '<CR>', function() self:expandCurrent(bufnr, buffer_state) end, map_opts)
  vim.keymap.set('n', '<Right>', function() self:expandCurrent(bufnr, buffer_state) end, map_opts)
  vim.keymap.set('n', '<Left>', function() self:collapseCurrent(bufnr, buffer_state) end, map_opts)
  
  -- Refresh
  vim.keymap.set('n', 'r', function() self:renderTreeToBuffer(bufnr, buffer_state) end, map_opts)
  vim.keymap.set('n', '<F5>', function() self:renderTreeToBuffer(bufnr, buffer_state) end, map_opts)
end

function VariablesBuffer:navigateNext(bufnr, buffer_state)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  
  if current_line < total_lines then
    local new_line = current_line + 1
    vim.api.nvim_win_set_cursor(0, {new_line, 0})
    buffer_state.cursor_line = new_line
  end
end

function VariablesBuffer:navigatePrev(bufnr, buffer_state)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  
  if current_line > 1 then
    local new_line = current_line - 1
    vim.api.nvim_win_set_cursor(0, {new_line, 0})
    buffer_state.cursor_line = new_line
  end
end

function VariablesBuffer:expandCurrent(bufnr, buffer_state)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local node = buffer_state.tree_data[current_line]
  
  if not node or not node.expandable then
    return
  end
  
  local node_key = nil
  if node.type == "scope" then
    node_key = node.scope.ref.name
  elseif node.type == "variable" then
    node_key = node.variable.ref.name
  end
  
  if node_key then
    buffer_state.expanded_nodes[node_key] = true
    buffer_state.cursor_line = current_line
    self:RenderTreeToBuffer(bufnr, buffer_state)
  end
end

function VariablesBuffer:collapseCurrent(bufnr, buffer_state)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local node = buffer_state.tree_data[current_line]
  
  if not node then
    return
  end
  
  local node_key = nil
  if node.type == "scope" then
    node_key = node.scope.ref.name
  elseif node.type == "variable" then
    node_key = node.variable.ref.name
  end
  
  if node_key then
    buffer_state.expanded_nodes[node_key] = false
    buffer_state.cursor_line = current_line
    self:RenderTreeToBuffer(bufnr, buffer_state)
  end
end

return VariablesBuffer