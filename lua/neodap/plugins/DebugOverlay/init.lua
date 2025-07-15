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
---@field layout_config table

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
    },
    layout_config = {
      min_code_width = 80,     -- Minimum width for code visibility
      min_panel_width = 35,    -- Minimum width for debug panels
      max_panel_width = 60,    -- Maximum width for debug panels
      min_panel_height = 15,   -- Minimum height for debug panels
      max_panel_height_ratio = 0.8, -- Maximum 80% of screen height
      panel_width_ratio = 0.4, -- Default panel width as ratio of screen
      panel_height_ratio = 0.6, -- Default panel height as ratio of screen
      prefer_side_by_side = true, -- Prefer side-by-side over stacked
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
  
  vim.api.nvim_create_user_command("NeodapDebugOverlayConfig", function()
    self:show_config()
  end, { desc = "Show debug overlay configuration" })
end

function DebugOverlay:calculate_optimal_layout()
  local screen_width = vim.o.columns
  local screen_height = vim.o.lines
  local config = self.layout_config
  
  -- Reserve space for command line, status line, etc.
  local available_height = screen_height - 5
  local available_width = screen_width
  
  -- Use configurable constants
  local min_code_width = config.min_code_width
  local min_panel_width = config.min_panel_width
  local max_panel_width = config.max_panel_width
  local min_panel_height = config.min_panel_height
  local max_panel_height = math.floor(available_height * config.max_panel_height_ratio)
  
  -- Calculate optimal panel dimensions
  local total_panel_width = math.min(
    math.max(min_panel_width * 2, math.floor(available_width * config.panel_width_ratio)),
    max_panel_width * 2 -- But not more than max
  )
  
  local panel_height = math.min(
    math.max(min_panel_height, math.floor(available_height * config.panel_height_ratio)),
    max_panel_height
  )
  
  -- Check if we have enough space for side-by-side layout
  local remaining_width = available_width - total_panel_width
  local use_side_by_side = config.prefer_side_by_side and remaining_width >= min_code_width
  
  local layout_config = {}
  
  if use_side_by_side then
    -- Side-by-side layout (preferred) - panels on the right, code on the left
    layout_config = {
      direction = "row",
      layout_options = {
        position = {
          row = 2, -- Start below status line
          col = remaining_width + 1, -- Position after the code area
        },
        size = {
          width = total_panel_width,
          height = panel_height,
        },
      },
      left_panel_size = "45%",  -- Scopes panel
      right_panel_size = "55%", -- Call stack panel
    }
    
    self.logger:debug("DebugOverlay: Using side-by-side layout", {
      code_width = remaining_width,
      panel_width = total_panel_width,
      panel_height = panel_height
    })
  else
    -- Stacked layout for narrow screens - panels stacked vertically on the right
    local single_panel_width = math.min(
      math.max(min_panel_width, available_width - min_code_width),
      max_panel_width
    )
    local code_width = available_width - single_panel_width
    
    layout_config = {
      direction = "col",
      layout_options = {
        position = {
          row = 2,
          col = code_width + 1,
        },
        size = {
          width = single_panel_width,
          height = panel_height,
        },
      },
      left_panel_size = "45%",  -- Scopes panel (top)
      right_panel_size = "55%", -- Call stack panel (bottom)
    }
    
    self.logger:debug("DebugOverlay: Using stacked layout", {
      code_width = code_width,
      panel_width = single_panel_width,
      panel_height = panel_height
    })
  end
  
  return layout_config
end

function DebugOverlay:listen()
  self.api:onSession(function(session)
    session:onTerminated(function()
      self:hide()
    end)
  end, { name = self.name .. ".onSession" })
  
  -- Listen for terminal resize events to recalculate layout
  vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      self:handle_resize()
    end,
    group = vim.api.nvim_create_augroup("NeodapDebugOverlay", { clear = true }),
    desc = "DebugOverlay: Handle terminal resize"
  })
end

function DebugOverlay:create_layout()
  if self.layout then
    return
  end
  
  -- Calculate optimal positioning and sizing
  local layout_config = self:calculate_optimal_layout()
  
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
  
  -- Create layout with calculated positioning
  self.layout = Layout(
    layout_config.layout_options,
    Layout.Box({
      Layout.Box(self.left_panel, { size = layout_config.left_panel_size }),
      Layout.Box(self.right_panel, { size = layout_config.right_panel_size }),
    }, { dir = layout_config.direction })
  )
  
  -- Set up keymaps for both panels
  self:setup_panel_keymaps()
  
  self.logger:debug("DebugOverlay: Created layout with optimal positioning", layout_config)
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

function DebugOverlay:handle_resize()
  if not self.is_visible then
    return
  end
  
  self.logger:debug("DebugOverlay: Handling terminal resize")
  
  -- Hide current layout
  if self.layout then
    self.layout:unmount()
  end
  
  -- Clear layout to force recreation with new dimensions
  self.layout = nil
  self.left_panel = nil
  self.right_panel = nil
  
  -- Recreate and show with new dimensions
  self:create_layout()
  self.layout:mount()
  
  self.logger:debug("DebugOverlay: Resize complete")
end

function DebugOverlay:show_config()
  local config = self.layout_config
  local screen_width = vim.o.columns
  local screen_height = vim.o.lines
  
  local config_lines = {
    "=== Neodap Debug Overlay Configuration ===",
    "",
    "Current Screen: " .. screen_width .. "x" .. screen_height,
    "",
    "Layout Configuration:",
    "  min_code_width: " .. config.min_code_width .. " (minimum width for code visibility)",
    "  min_panel_width: " .. config.min_panel_width .. " (minimum width for debug panels)",
    "  max_panel_width: " .. config.max_panel_width .. " (maximum width for debug panels)",
    "  min_panel_height: " .. config.min_panel_height .. " (minimum height for debug panels)",
    "  max_panel_height_ratio: " .. config.max_panel_height_ratio .. " (maximum panel height as ratio of screen)",
    "  panel_width_ratio: " .. config.panel_width_ratio .. " (default panel width as ratio of screen)",
    "  panel_height_ratio: " .. config.panel_height_ratio .. " (default panel height as ratio of screen)",
    "  prefer_side_by_side: " .. tostring(config.prefer_side_by_side) .. " (prefer side-by-side over stacked)",
    "",
    "To modify these values, use:",
    "  require('neodap.plugins.DebugOverlay').configure({ min_code_width = 100 })",
    "",
    "Current Layout Analysis:",
  }
  
  -- Add current layout analysis
  if self.is_visible then
    local layout_analysis = self:calculate_optimal_layout()
    table.insert(config_lines, "  Layout: " .. layout_analysis.direction .. " (side-by-side: " .. (layout_analysis.direction == "row" and "yes" or "no") .. ")")
    table.insert(config_lines, "  Size: " .. layout_analysis.layout_options.size.width .. "x" .. layout_analysis.layout_options.size.height)
    table.insert(config_lines, "  Position: row=" .. layout_analysis.layout_options.position.row .. ", col=" .. layout_analysis.layout_options.position.col)
  else
    table.insert(config_lines, "  Overlay is currently hidden")
  end
  
  vim.api.nvim_echo(vim.tbl_map(function(line) return { line, "Normal" } end, config_lines), false, {})
end

function DebugOverlay:configure(new_config)
  -- Update configuration
  for key, value in pairs(new_config) do
    if self.layout_config[key] ~= nil then
      self.layout_config[key] = value
      self.logger:debug("DebugOverlay: Updated config", key, "=", value)
    else
      self.logger:warn("DebugOverlay: Unknown config key", key)
    end
  end
  
  -- If overlay is visible, recreate it with new configuration
  if self.is_visible then
    self:handle_resize()
  end
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
  pcall(vim.api.nvim_del_user_command, "NeodapDebugOverlayConfig")
  
  -- Clean up autocommands
  pcall(vim.api.nvim_del_augroup_by_name, "NeodapDebugOverlay")
  
  self.logger:info("DebugOverlay: Plugin destroyed")
end

return DebugOverlay