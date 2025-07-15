local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local Layout = require("nui.layout")
local Popup = require("nui.popup")

---@class neodap.plugin.DebugOverlayProps
---@field api Api
---@field logger Logger
---@field layout nui.layout | nil
---@field left_panel nui.popup | nil
---@field right_panel nui.popup | nil
---@field is_visible boolean
---@field panel_contents table<string, table>

---@class neodap.plugin.DebugOverlay: neodap.plugin.DebugOverlayProps
---@field new Constructor<neodap.plugin.DebugOverlayProps>
local DebugOverlay = Class()

DebugOverlay.name = "DebugOverlay"
DebugOverlay.description = "Layout manager for debug interface using nui.layout"

function DebugOverlay.plugin(api)
  local logger = Logger.get()
  
  local instance = DebugOverlay:new({
    api = api,
    logger = logger,
    layout = nil,
    left_panel = nil,
    right_panel = nil,
    is_visible = false,
    panel_contents = {
      left = { lines = {}, highlights = {} },
      right = { lines = {}, highlights = {} }
    }
  })
  
  instance:setup_commands()
  instance:listen()
  
  return instance
end

function DebugOverlay:setup_commands()
  vim.api.nvim_create_user_command("NeodapDebugOverlayShow", function()
    self:show()
  end, { desc = "Show debug overlay" })
  
  vim.api.nvim_create_user_command("NeodapDebugOverlayHide", function()
    self:hide()
  end, { desc = "Hide debug overlay" })
  
  vim.api.nvim_create_user_command("NeodapDebugOverlayToggle", function()
    self:toggle()
  end, { desc = "Toggle debug overlay" })
end

function DebugOverlay:listen()
  self.api:onSession(function(session)
    session:onTerminated(function()
      self:hide()
    end)
  end, { name = self.name .. ".onSession" })
end

function DebugOverlay:create_layout()
  if self.layout then
    return
  end
  
  -- Create left panel (for ScopeViewer)
  self.left_panel = Popup({
    border = {
      style = "rounded",
      text = {
        top = " Scopes ",
        top_align = "center",
      },
    },
    win_options = {
      cursorline = true,
      wrap = false,
      number = false,
      relativenumber = false,
      signcolumn = "no",
    },
    buf_options = {
      buftype = "nofile",
      bufhidden = "hide",
      filetype = "neodap-scopes",
      modifiable = false,
    },
  })
  
  -- Create right panel (for CallStackViewer)
  self.right_panel = Popup({
    border = {
      style = "rounded",
      text = {
        top = " Call Stack ",
        top_align = "center",
      },
    },
    win_options = {
      cursorline = true,
      wrap = false,
      number = false,
      relativenumber = false,
      signcolumn = "no",
    },
    buf_options = {
      buftype = "nofile",
      bufhidden = "hide",
      filetype = "neodap-callstack",
      modifiable = false,
    },
  })
  
  -- Create layout with side-by-side panels
  self.layout = Layout(
    {
      position = "50%",
      size = {
        width = 120,
        height = 25,
      },
    },
    Layout.Box({
      Layout.Box(self.left_panel, { size = "45%" }),
      Layout.Box(self.right_panel, { size = "55%" }),
    }, { dir = "row" })
  )
  
  -- Set up keymaps for both panels
  self:setup_panel_keymaps()
  
  self.logger:debug("DebugOverlay: Created layout with left and right panels")
end

function DebugOverlay:setup_panel_keymaps()
  local keymap_opts = { noremap = true, silent = true }
  
  -- Left panel keymaps
  if self.left_panel then
    self.left_panel:map("n", "q", function() self:hide() end, keymap_opts)
    self.left_panel:map("n", "<Esc>", function() self:hide() end, keymap_opts)
    self.left_panel:map("n", "<CR>", function() self:handle_left_panel_select() end, keymap_opts)
    self.left_panel:map("n", "<Space>", function() self:handle_left_panel_toggle() end, keymap_opts)
  end
  
  -- Right panel keymaps
  if self.right_panel then
    self.right_panel:map("n", "q", function() self:hide() end, keymap_opts)
    self.right_panel:map("n", "<Esc>", function() self:hide() end, keymap_opts)
    self.right_panel:map("n", "<CR>", function() self:handle_right_panel_select() end, keymap_opts)
    self.right_panel:map("n", "o", function() self:handle_right_panel_select() end, keymap_opts)
  end
end

function DebugOverlay:show()
  if self.is_visible then
    return
  end
  
  self:create_layout()
  self.layout:mount()
  self.is_visible = true
  
  self.logger:debug("DebugOverlay: Shown")
end

function DebugOverlay:hide()
  if not self.is_visible then
    return
  end
  
  if self.layout then
    self.layout:unmount()
  end
  self.is_visible = false
  
  self.logger:debug("DebugOverlay: Hidden")
end

function DebugOverlay:toggle()
  if self.is_visible then
    self:hide()
  else
    self:show()
  end
end

function DebugOverlay:is_open()
  return self.is_visible
end

-- Panel content management methods
function DebugOverlay:set_left_panel_content(lines, highlights, metadata)
  self.panel_contents.left = {
    lines = lines or {},
    highlights = highlights or {},
    metadata = metadata or {}
  }
  
  if self.left_panel and self.is_visible then
    self:render_left_panel()
  end
end

function DebugOverlay:set_right_panel_content(lines, highlights, metadata)
  self.panel_contents.right = {
    lines = lines or {},
    highlights = highlights or {},
    metadata = metadata or {}
  }
  
  if self.right_panel and self.is_visible then
    self:render_right_panel()
  end
end

function DebugOverlay:render_left_panel()
  if not self.left_panel then
    return
  end
  
  local bufnr = self.left_panel.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  
  local content = self.panel_contents.left
  
  -- Set buffer as modifiable, update content, then set back to read-only
  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content.lines)
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  
  -- Apply highlights
  if content.highlights then
    local namespace = vim.api.nvim_create_namespace("neodap_debug_overlay_left")
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
    
    for i, hl_parts in ipairs(content.highlights) do
      if hl_parts then
        for _, hl in ipairs(hl_parts) do
          vim.api.nvim_buf_add_highlight(bufnr, namespace, hl[3], i - 1, hl[1], hl[2])
        end
      end
    end
  end
end

function DebugOverlay:render_right_panel()
  if not self.right_panel then
    return
  end
  
  local bufnr = self.right_panel.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  
  local content = self.panel_contents.right
  
  -- Set buffer as modifiable, update content, then set back to read-only
  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content.lines)
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  
  -- Apply highlights
  if content.highlights then
    local namespace = vim.api.nvim_create_namespace("neodap_debug_overlay_right")
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
    
    for i, hl_parts in ipairs(content.highlights) do
      if hl_parts then
        for _, hl in ipairs(hl_parts) do
          vim.api.nvim_buf_add_highlight(bufnr, namespace, hl[3], i - 1, hl[1], hl[2])
        end
      end
    end
  end
end

function DebugOverlay:clear_left_panel()
  self:set_left_panel_content({}, {}, {})
end

function DebugOverlay:clear_right_panel()
  self:set_right_panel_content({}, {}, {})
end

-- Panel interaction handlers (to be connected to actual plugins)
function DebugOverlay:handle_left_panel_select()
  if not self.left_panel then
    return
  end
  
  local line, _ = unpack(vim.api.nvim_win_get_cursor(self.left_panel.winid))
  
  -- Trigger custom event for left panel selection
  vim.api.nvim_exec_autocmds("User", {
    pattern = "NeodapDebugOverlayLeftSelect",
    data = { line = line, metadata = self.panel_contents.left.metadata }
  })
end

function DebugOverlay:handle_left_panel_toggle()
  if not self.left_panel then
    return
  end
  
  local line, _ = unpack(vim.api.nvim_win_get_cursor(self.left_panel.winid))
  
  -- Trigger custom event for left panel toggle
  vim.api.nvim_exec_autocmds("User", {
    pattern = "NeodapDebugOverlayLeftToggle",
    data = { line = line, metadata = self.panel_contents.left.metadata }
  })
end

function DebugOverlay:handle_right_panel_select()
  if not self.right_panel then
    return
  end
  
  local line, _ = unpack(vim.api.nvim_win_get_cursor(self.right_panel.winid))
  
  -- Trigger custom event for right panel selection
  vim.api.nvim_exec_autocmds("User", {
    pattern = "NeodapDebugOverlayRightSelect",
    data = { line = line, metadata = self.panel_contents.right.metadata }
  })
end

-- Window ID getters for cursor movement detection
function DebugOverlay:get_left_panel_winid()
  return self.left_panel and self.left_panel.winid
end

function DebugOverlay:get_right_panel_winid()
  return self.right_panel and self.right_panel.winid
end

function DebugOverlay:is_managed_window(winid)
  return winid == self:get_left_panel_winid() or winid == self:get_right_panel_winid()
end

function DebugOverlay:get_target_window_for_navigation()
  -- Find the first window that's not managed by our overlay
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not self:is_managed_window(win) then
      return win
    end
  end
  return nil
end

function DebugOverlay:destroy()
  self.logger:debug("DebugOverlay: Destroying plugin")
  
  if self.is_visible then
    self:hide()
  end
  
  -- Clean up user commands
  pcall(vim.api.nvim_del_user_command, "NeodapDebugOverlayShow")
  pcall(vim.api.nvim_del_user_command, "NeodapDebugOverlayHide")
  pcall(vim.api.nvim_del_user_command, "NeodapDebugOverlayToggle")
  
  self.logger:info("DebugOverlay: Plugin destroyed")
end

return DebugOverlay