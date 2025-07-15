local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local Location = require("neodap.api.Location")
local StackNavigation = require("neodap.plugins.StackNavigation")
local UI = require("neodap.ui")

---@class neodap.plugin.ScopeViewerProps
---@field api Api
---@field logger Logger
---@field stackNavigation neodap.plugin.StackNavigation
---@field window neodap.ui.Window | nil
---@field scopes table[]
---@field scope_map table<integer, api.Scope>
---@field current_frame api.Frame | nil
---@field highlight_namespace integer
---@field expanded_scopes table<integer, boolean>

---@class neodap.plugin.ScopeViewer: neodap.plugin.ScopeViewerProps
---@field new Constructor<neodap.plugin.ScopeViewerProps>
local ScopeViewer = Class()

ScopeViewer.name = "ScopeViewer"
ScopeViewer.description = "Visual scope viewer for debugging sessions"

function ScopeViewer.plugin(api)
  local logger = Logger.get()
  
  local instance = ScopeViewer:new({
    api = api,
    logger = logger,
    stackNavigation = api:getPluginInstance(StackNavigation),
    window = nil,
    scopes = {},
    scope_map = {},
    current_frame = nil,
    highlight_namespace = vim.api.nvim_create_namespace("neodap_scope_viewer"),
    expanded_scopes = {},
  })
  
  instance:listen()
  
  return instance
end

function ScopeViewer:get_current_frame()
  -- Get the smart closest frame for current cursor position
  local cursor = Location.fromCursor()
  if not cursor then
    return nil
  end
  
  return self.stackNavigation:getSmartClosestFrame(cursor)
end

function ScopeViewer:show()
  if self:is_window_open() then
    return
  end
  
  local frame = self:get_current_frame()
  if not frame then
    return
  end
  
  self:open_window()
  self:render(frame)
end

function ScopeViewer:hide()
  self:close_window()
end

function ScopeViewer:toggle()
  if self:is_window_open() then
    self:hide()
  else
    self:show()
  end
end

function ScopeViewer:listen()
  self.api:onSession(function(session)
    session:onThread(function(thread)
      thread:onStopped(function(stopped_event)
        -- Automatically show the window when debug session stops (breakpoint hit, etc.)
        if not self:is_window_open() then
          self:open_window()
        end
        
        local frame = self:get_current_frame()
        if frame then
          self:render(frame)
        end
      end)
      
      thread:onResumed(function()
        if self:is_window_open() then
          self:clear_window()
        end
      end)
    end)
    
    session:onTerminated(function()
      self:hide()
    end)
  end, { name = self.name .. ".onSession" })
  
  -- Listen for stack navigation events
  vim.api.nvim_create_autocmd("User", {
    pattern = "NeodapStackNavigationChanged",
    callback = function(event)
      self:onNavigationChanged(event.data)
    end,
    group = vim.api.nvim_create_augroup("NeodapScopeViewer", { clear = true }),
  })
  
  -- Listen for cursor movement to update ScopeViewer
  vim.api.nvim_create_autocmd("CursorMoved", {
    callback = function()
      self:onGlobalCursorMoved()
    end,
    group = vim.api.nvim_create_augroup("NeodapScopeViewer", { clear = false }),
  })
end

-- Event Handling Methods
function ScopeViewer:onNavigationChanged(event_data)
  -- Only update if window is open
  if not self:is_window_open() then
    return
  end
  
  -- Get the current frame and render its scopes
  local frame = self:get_current_frame()
  if frame then
    self:render(frame)
  end
end

function ScopeViewer:onGlobalCursorMoved()
  -- Only update if window is open
  if not self:is_window_open() then
    return
  end
  
  -- Skip if cursor is in the ScopeViewer window itself
  if vim.api.nvim_get_current_win() == self.window:get_winid() then
    return
  end
  
  -- Get the smart closest frame for current cursor position
  local frame = self:get_current_frame()
  if not frame then
    return
  end
  
  -- Update ScopeViewer to show scopes for the current frame
  if not self.current_frame or self.current_frame.ref.id ~= frame.ref.id then
    self:render(frame)
  end
end

-- Window Management Methods
function ScopeViewer:create_window()
  if not self.window then
    self.window = UI.Window:new({
      title = " Scopes ",
      size = { width = 50, height = 15 },
      position = { col = 5, row = 5 },
      enter = false, -- Don't take focus when showing
      win_options = {
        cursorline = true,
        wrap = false,
        number = false,
        relativenumber = false,
        signcolumn = "no",
      },
      keymaps = {
        ["q"] = function() self:hide() end,
        ["<Esc>"] = function() self:hide() end,
        ["<CR>"] = function() self:on_window_select() end,
        ["o"] = function() self:on_window_select() end,
        ["<Space>"] = function() self:toggle_scope() end,
      }
    })
    
    -- Set buffer options
    local bufnr = self.window:get_bufnr()
    if bufnr then
      vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
      vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
      vim.api.nvim_buf_set_option(bufnr, "filetype", "neodap-scopes")
      vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
      
      -- Set up cursor movement detection for scope expansion
      vim.api.nvim_create_autocmd("CursorMoved", {
        buffer = bufnr,
        callback = function()
          self:on_cursor_moved()
        end,
        desc = "ScopeViewer: Handle cursor movement in scopes window"
      })
    end
    
    self:setup_window_highlights()
  end
  return self.window
end

function ScopeViewer:open_window()
  if self:is_window_open() then
    return
  end
  
  self:create_window()
  self.window:show()
end

function ScopeViewer:close_window()
  if self.window then
    self.window:hide()
  end
end

function ScopeViewer:is_window_open()
  return self.window and self.window:is_open()
end

function ScopeViewer:clear_window()
  if self.window then
    self.window:clear()
  end
end

function ScopeViewer:set_window_lines(lines)
  if self.window then
    self.window:set_lines(lines)
  end
end

function ScopeViewer:add_window_highlight(line, col_start, col_end, hl_group, namespace)
  if self.window then
    self.window:add_highlight(line, col_start, col_end, hl_group, namespace)
  end
end

function ScopeViewer:clear_window_namespace(ns_id)
  if self.window then
    self.window:clear_highlights(ns_id)
  end
end

function ScopeViewer:on_window_select()
  local line, _ = self.window:get_cursor()
  local scope = self.scope_map[line]
  if scope then
    self:toggle_scope_expansion(scope)
  end
end

function ScopeViewer:on_cursor_moved()
  -- Could add preview functionality here if needed
end

function ScopeViewer:toggle_scope()
  local line, _ = self.window:get_cursor()
  local scope = self.scope_map[line]
  if scope then
    self:toggle_scope_expansion(scope)
  end
end

function ScopeViewer:toggle_scope_expansion(scope)
  local ref = scope.ref.variablesReference
  if ref and ref > 0 then
    self.expanded_scopes[ref] = not self.expanded_scopes[ref]
    if self.current_frame then
      self:render(self.current_frame)
    end
  end
end

function ScopeViewer:setup_window_highlights()
  vim.cmd([[
    highlight default NeodapScopeExpanded guifg=#7aa2f7 gui=bold
    highlight default NeodapScopeCollapsed guifg=#9ece6a
    highlight default NeodapScopeVariable guifg=#e0af68
    highlight default NeodapScopeValue guifg=#f7768e
    highlight default NeodapScopeType guifg=#bb9af7
  ]])
end

-- Rendering Methods
function ScopeViewer:render(frame)
  if not frame then
    return
  end
  
  self.current_frame = frame
  local scopes = frame:scopes()
  
  if not scopes or #scopes == 0 then
    self:set_window_lines({"No scopes available"})
    return
  end
  
  local lines = {}
  local highlights = {}
  self.scope_map = {}
  
  for i, scope in ipairs(scopes) do
    local line_parts = {}
    local hl_parts = {}
    
    -- Add expand/collapse indicator
    local ref = scope.ref.variablesReference
    local is_expandable = ref and ref > 0
    local is_expanded = self.expanded_scopes[ref]
    
    if is_expandable then
      local indicator = is_expanded and "▼ " or "▶ "
      table.insert(line_parts, indicator)
      table.insert(hl_parts, {0, #indicator, is_expanded and "NeodapScopeExpanded" or "NeodapScopeCollapsed"})
    else
      table.insert(line_parts, "  ")
    end
    
    -- Add scope name
    local name = scope.ref.name or "Unknown"
    table.insert(line_parts, name)
    local name_start = #table.concat(line_parts, "") - #name
    table.insert(hl_parts, {name_start, name_start + #name, "NeodapScopeExpanded"})
    
    -- Add scope type if available
    if scope.ref.expensive then
      table.insert(line_parts, " (expensive)")
      local type_start = #table.concat(line_parts, "") - 11
      table.insert(hl_parts, {type_start, type_start + 11, "NeodapScopeType"})
    end
    
    local line = table.concat(line_parts, "")
    table.insert(lines, line)
    table.insert(highlights, hl_parts)
    self.scope_map[#lines] = scope
    
    -- Add variables if scope is expanded
    if is_expanded then
      local variables = scope:variables()
      if variables then
        for _, variable in ipairs(variables) do
          local var_line = self:format_variable(variable, 1)
          table.insert(lines, var_line.text)
          table.insert(highlights, var_line.highlights)
          self.scope_map[#lines] = scope -- Map to parent scope
        end
      end
    end
  end
  
  self:set_window_lines(lines)
  
  -- Apply highlights
  for i, hl_parts in ipairs(highlights) do
    for _, hl in ipairs(hl_parts) do
      self:add_window_highlight(i - 1, hl[1], hl[2], hl[3])
    end
  end
end

function ScopeViewer:format_variable(variable, indent)
  local line_parts = {}
  local hl_parts = {}
  
  -- Add indentation
  local indent_str = string.rep("  ", indent)
  table.insert(line_parts, indent_str)
  
  -- Add variable name
  local name = variable.name or "unknown"
  table.insert(line_parts, name)
  local name_start = #table.concat(line_parts, "") - #name
  table.insert(hl_parts, {name_start, name_start + #name, "NeodapScopeVariable"})
  
  -- Add value if available
  if variable.value then
    table.insert(line_parts, " = ")
    local value = tostring(variable.value)
    if #value > 40 then
      value = value:sub(1, 40) .. "..."
    end
    table.insert(line_parts, value)
    local value_start = #table.concat(line_parts, "") - #value
    table.insert(hl_parts, {value_start, value_start + #value, "NeodapScopeValue"})
  end
  
  -- Add type if available
  if variable.type then
    table.insert(line_parts, " : ")
    table.insert(line_parts, variable.type)
    local type_start = #table.concat(line_parts, "") - #variable.type
    table.insert(hl_parts, {type_start, type_start + #variable.type, "NeodapScopeType"})
  end
  
  return {
    text = table.concat(line_parts, ""),
    highlights = hl_parts
  }
end

function ScopeViewer:get_window_id()
  return self.window and self.window:get_winid()
end

function ScopeViewer:get_window_bufnr()
  return self.window and self.window:get_bufnr()
end

return ScopeViewer