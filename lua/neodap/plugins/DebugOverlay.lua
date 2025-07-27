-- DebugOverlay Plugin
-- Multi-panel debug interface with layout coordination

local BasePlugin = require('neodap.plugins.BasePlugin')

-- ========================================
-- PLUGIN CLASS
-- ========================================

---@class DebugOverlay: BasePlugin
local DebugOverlay = BasePlugin:extend()

DebugOverlay.name = "DebugOverlay"

-- ========================================
-- OVERLAY CONFIGURATION
-- ========================================

-- Define overlay regions for different debug panels
DebugOverlay.regions = {
  variables = { 
    row = 2, 
    col = 2, 
    width = 45, 
    height = 25,
    title = " Variables "
  },
  stack = { 
    row = 2, 
    col = 50, 
    width = 35, 
    height = 15,
    title = " Call Stack "
  },
  breakpoints = { 
    row = 19, 
    col = 50, 
    width = 35, 
    height = 10,
    title = " Breakpoints "
  },
  watches = {
    row = 29,
    col = 2,
    width = 83,
    height = 8,
    title = " Watch Expressions "
  }
}

-- ========================================
-- PLUGIN INITIALIZATION
-- ========================================

function DebugOverlay.plugin(api)
  return BasePlugin.createPlugin(api, DebugOverlay)
end

function DebugOverlay:listen()
  self.logger:info("Initializing DebugOverlay layout plugin")
  self:setupCommands()
  self.active_windows = {}
  self.overlay_active = false
  self.logger:info("DebugOverlay layout plugin initialized")
end

-- ========================================
-- COMMANDS
-- ========================================

function DebugOverlay:setupCommands()
  self:registerCommands({
    { "DebugOverlayShow", function() self:show() end, { desc = "Show debug overlay with all panels" } },
    { "DebugOverlayHide", function() self:hide() end, { desc = "Hide debug overlay" } },
    { "DebugOverlayToggle", function() self:toggle() end, { desc = "Toggle debug overlay" } },
    { "DebugOverlayRefresh", function() self:refresh() end, { desc = "Refresh all overlay panels" } }
  })
end

-- ========================================
-- OVERLAY MANAGEMENT
-- ========================================

function DebugOverlay:show(frame)
  if self.overlay_active then
    print("Debug overlay already active")
    return
  end
  
  -- Get current frame if not provided
  if not frame then
    frame = self:getCurrentFrame()
    if not frame then
      print("No current frame available. Start debugging and hit a breakpoint first.")
      return
    end
  end
  
  self.logger:info("Showing debug overlay for frame " .. (frame.ref.id or "unknown"))
  self.overlay_active = true
  
  -- Show all panels
  self:showVariablesInRegion(frame, self.regions.variables)
  -- TODO: Add other panels when services are available
  -- self:showStackInRegion(frame, self.regions.stack)
  -- self:showBreakpointsInRegion(self.regions.breakpoints)
  -- self:showWatchesInRegion(frame, self.regions.watches)
  
  print("🔍 Debug overlay active - Press :DebugOverlayHide to close")
end

function DebugOverlay:hide()
  if not self.overlay_active then
    print("Debug overlay not active")
    return
  end
  
  self.logger:info("Hiding debug overlay")
  self.overlay_active = false
  
  -- Close all active windows
  for panel_name, window_info in pairs(self.active_windows) do
    if window_info.buffer then
      window_info.buffer.close()
    end
    if window_info.win and vim.api.nvim_win_is_valid(window_info.win) then
      vim.api.nvim_win_close(window_info.win, true)
    end
  end
  
  self.active_windows = {}
  print("Debug overlay hidden")
end

function DebugOverlay:toggle()
  if self.overlay_active then
    self:hide()
  else
    self:show()
  end
end

function DebugOverlay:refresh()
  if not self.overlay_active then
    print("Debug overlay not active")
    return
  end
  
  local frame = self:getCurrentFrame()
  if not frame then
    print("No current frame available")
    return
  end
  
  self.logger:info("Refreshing debug overlay")
  
  -- Refresh all active panels
  for panel_name, window_info in pairs(self.active_windows) do
    if window_info.buffer and window_info.buffer.refresh then
      window_info.buffer.refresh()
    end
  end
  
  print("Debug overlay refreshed")
end

-- ========================================
-- PANEL INTEGRATION
-- ========================================

function DebugOverlay:showVariablesInRegion(frame, region)
  -- Get functional buffer from VariablesBuffer service
  local variables_service = self.api:getPluginInstance(require('neodap.plugins.VariablesBuffer'))
  if not variables_service then
    self.logger:error("VariablesBuffer service not available")
    return nil
  end
  
  local buffer_handle = variables_service:createBuffer(frame, {
    compact = true  -- Use compact mode for overlay
  })
  
  -- Create window in specific region
  local win = vim.api.nvim_open_win(buffer_handle.bufnr, false, {
    relative = 'editor',
    row = region.row,
    col = region.col,
    width = region.width,
    height = region.height,
    style = 'minimal',
    border = 'rounded',
    title = region.title,
    title_pos = 'center'
  })
  
  -- Store for cleanup and refresh
  self.active_windows.variables = {
    win = win,
    buffer = buffer_handle,
    region = region
  }
  
  self.logger:debug("Variables panel opened in overlay region")
  return { win = win, buffer = buffer_handle }
end

function DebugOverlay:showStackInRegion(frame, region)
  -- TODO: Implement when StackTraceBuffer service is available
  self.logger:warn("Stack trace panel not yet implemented")
  
  -- Placeholder implementation
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "Stack Trace Panel",
    "(Not yet implemented)",
    "",
    "Waiting for StackTraceBuffer service..."
  })
  
  local win = vim.api.nvim_open_win(bufnr, false, {
    relative = 'editor',
    row = region.row,
    col = region.col,
    width = region.width,
    height = region.height,
    style = 'minimal',
    border = 'rounded',
    title = region.title,
    title_pos = 'center'
  })
  
  self.active_windows.stack = {
    win = win,
    buffer = { bufnr = bufnr, close = function() vim.api.nvim_buf_delete(bufnr, {force = true}) end },
    region = region
  }
end

function DebugOverlay:showBreakpointsInRegion(region)
  -- TODO: Implement when BreakpointBuffer service is available
  self.logger:warn("Breakpoints panel not yet implemented")
  
  -- Placeholder implementation
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "Breakpoints Panel",
    "(Not yet implemented)",
    "",
    "Waiting for BreakpointBuffer service..."
  })
  
  local win = vim.api.nvim_open_win(bufnr, false, {
    relative = 'editor',
    row = region.row,
    col = region.col,
    width = region.width,
    height = region.height,
    style = 'minimal',
    border = 'rounded',
    title = region.title,
    title_pos = 'center'
  })
  
  self.active_windows.breakpoints = {
    win = win,
    buffer = { bufnr = bufnr, close = function() vim.api.nvim_buf_delete(bufnr, {force = true}) end },
    region = region
  }
end

function DebugOverlay:showWatchesInRegion(frame, region)
  -- TODO: Implement when WatchBuffer service is available
  self.logger:warn("Watch expressions panel not yet implemented")
  
  -- Placeholder implementation
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "Watch Expressions Panel",
    "(Not yet implemented)",
    "",
    "Waiting for WatchBuffer service..."
  })
  
  local win = vim.api.nvim_open_win(bufnr, false, {
    relative = 'editor',
    row = region.row,
    col = region.col,
    width = region.width,
    height = region.height,
    style = 'minimal',
    border = 'rounded',
    title = region.title,
    title_pos = 'center'
  })
  
  self.active_windows.watches = {
    win = win,
    buffer = { bufnr = bufnr, close = function() vim.api.nvim_buf_delete(bufnr, {force = true}) end },
    region = region
  }
end

-- ========================================
-- LAYOUT MANAGEMENT
-- ========================================

function DebugOverlay:adjustLayout()
  -- TODO: Implement responsive layout based on terminal size
  local width = vim.o.columns
  local height = vim.o.lines
  
  self.logger:debug("Terminal size: " .. width .. "x" .. height)
  
  -- For now, use fixed layout
  -- Future: Adjust regions based on available space
end

function DebugOverlay:saveLayout()
  -- TODO: Save current layout configuration
  self.logger:debug("Layout saving not yet implemented")
end

function DebugOverlay:restoreLayout()
  -- TODO: Restore saved layout configuration
  self.logger:debug("Layout restoration not yet implemented")
end

-- ========================================
-- CONTEXT HELPERS
-- ========================================

function DebugOverlay:getCurrentSession()
  -- Get the current active debugging session
  local manager = self.api.manager
  if manager and manager.sessions then
    for _, session in pairs(manager.sessions) do
      if session:isActive() then
        return session
      end
    end
  end
  return nil
end

function DebugOverlay:getCurrentFrame()
  local session = self:getCurrentSession()
  if not session then
    return nil
  end
  
  local thread = session:getCurrentThread()
  if not thread or not thread:isStopped() then
    return nil
  end
  
  return thread:getCurrentFrame()
end

-- ========================================
-- EVENT HANDLING
-- ========================================

function DebugOverlay:onFrameChanged(new_frame)
  -- Auto-refresh overlay when frame changes
  if self.overlay_active then
    self:refresh()
  end
end

function DebugOverlay:onSessionStopped()
  -- Auto-show overlay when debugging stops (hits breakpoint)
  if not self.overlay_active then
    local frame = self:getCurrentFrame()
    if frame then
      self:show(frame)
    end
  else
    self:refresh()
  end
end

function DebugOverlay:onSessionTerminated()
  -- Auto-hide overlay when debugging session ends
  if self.overlay_active then
    self:hide()
  end
end

return DebugOverlay