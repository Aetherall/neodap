-- VariablesPopup Presentation Plugin
-- Enhanced NUI popup wrapper using Variables4 buffer-composable rendering

local BasePlugin = require('neodap.plugins.BasePlugin')
local Popup = require("nui.popup")

-- ========================================
-- PLUGIN CLASS
-- ========================================

---@class VariablesPopup: BasePlugin
local VariablesPopup = BasePlugin:extend()

VariablesPopup.name = "VariablesPopup"

-- ========================================
-- PLUGIN INITIALIZATION
-- ========================================

function VariablesPopup.plugin(api)
  return BasePlugin.createPlugin(api, VariablesPopup)
end

function VariablesPopup:listen()
  self.logger:info("Initializing VariablesPopup presentation plugin (enhanced with Variables4)")
  self:setupCommands()
  self.logger:info("VariablesPopup presentation plugin initialized")
end

-- ========================================
-- POPUP PRESENTATION
-- ========================================

---Show variables in a popup window using Variables4's advanced features
---@param frame api.Frame The frame to show variables for
---@param options table? Optional configuration
---@return table popup_handle Enhanced popup window handle with Variables4 features
function VariablesPopup:show(frame, options)
  local opts = vim.tbl_extend("force", {
    width = "80%",
    height = "70%",
    position = "50%",
    title = " Variables Debug Tree ",
    auto_refresh = false,
    enable_focus = true,        -- Enable Variables4 focus mode
    enable_lazy = true,         -- Enable lazy variable resolution
    enable_advanced = true      -- Enable all Variables4 advanced features
  }, options or {})
  
  self.logger:debug("Opening enhanced variables popup for frame " .. (frame.ref.id or "unknown"))
  
  -- Get Variables4 service instead of VariablesBuffer
  local variables4 = self.api:getPluginInstance(require('neodap.plugins.Variables4'))
  if not variables4 then
    self.logger:error("Variables4 service not available")
    return self:createEmptyPopupHandle()
  end
  
  -- Create popup
  local popup = Popup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = { top = opts.title, top_align = "center" }
    },
    position = opts.position,
    size = { width = opts.width, height = opts.height },
    buf_options = { modifiable = false, readonly = true },
    win_options = { wrap = false }
  })
  
  popup:mount()
  
  -- Use Variables4's enhanced buffer-composable rendering
  local buffer_handle = variables4:renderToBuffer(popup.bufnr, {
    frame = frame,
    compact = false,
    auto_refresh = opts.auto_refresh,
    enable_focus = opts.enable_focus,
    enable_lazy = opts.enable_lazy
  })
  
  -- Link popup to buffer handle for Variables4 features
  buffer_handle.popup = popup
  
  -- Setup enhanced navigation (Variables4 handles this internally)
  self:setupEnhancedKeybindings(popup, buffer_handle)
  
  -- Store reference for cleanup
  self.active_popup = {
    popup = popup,
    buffer = buffer_handle
  }
  
  return {
    popup = popup,
    buffer = buffer_handle,
    close = function() self:closePopup(popup, buffer_handle) end,
    
    -- Expose Variables4 advanced features
    focusOnNode = buffer_handle.focusOnNode,
    navigateToNode = buffer_handle.navigateToNode,
    expandVariable = buffer_handle.expandVariable,
    resolveLazy = buffer_handle.resolveLazy,
    getCurrentNode = buffer_handle.getCurrentNode,
    getTree = buffer_handle.getTree,
    
    metadata = {
      service = "Variables4",
      presentation = "VariablesPopup",
      frame_id = frame.ref.id,
      has_advanced_features = buffer_handle.metadata.has_advanced_features,
      variables4_version = buffer_handle.metadata.variables4_version
    }
  }
end

function VariablesPopup:createEmptyPopupHandle()
  return {
    close = function() end,
    refresh = function() end,
    metadata = { empty = true }
  }
end

function VariablesPopup:setupEnhancedKeybindings(popup, buffer_handle)
  local map_opts = { noremap = true, silent = true }
  
  -- Close popup
  popup:map("n", "q", function()
    self:closePopup(popup, buffer_handle)
  end, map_opts)
  
  popup:map("n", "<Esc>", function()
    self:closePopup(popup, buffer_handle)
  end, map_opts)
  
  -- Enhanced help showing Variables4 features
  popup:map("n", "?", function()
    print("VariablesPopup Controls (Enhanced with Variables4):")
    print("")
    print("Navigation (vim-style):")
    print("  h/j/k/l: Navigate tree with advanced logic")  
    print("  <CR>/l: Expand variables with lazy resolution")
    print("  f: Focus mode - drill into specific scope")
    print("  r: Refresh tree")
    print("")
    print("Advanced Features:")
    print("  - AsNode() caching strategy")
    print("  - Lazy variable resolution") 
    print("  - Focus mode and viewport management")
    print("  - Sophisticated tree rendering with UTF-8 characters")
    print("  - Smart navigation and boundary handling")
    print("  - Recursive expansion with duplicate detection")
    print("")
    print("Controls:")
    print("  q/Esc: Close popup")
    print("  ?: Show this help")
    print("")
    print("Powered by Variables4 buffer-composable architecture")
  end, map_opts)
end

function VariablesPopup:closePopup(popup, buffer_handle)
  if buffer_handle then
    buffer_handle.close()
  end
  if popup and popup.unmount then
    popup:unmount()
  end
  self.active_popup = nil
end

-- ========================================
-- COMMANDS AND INTEGRATION
-- ========================================

function VariablesPopup:setupCommands()
  self:registerCommands({
    { "VariablesPopup", function() self:openPopup() end, { desc = "Open variables in popup" } },
    { "VariablesPopupClose", function() self:closeCurrentPopup() end, { desc = "Close variables popup" } }
  })
end

function VariablesPopup:openPopup()
  -- Get current frame from session context
  local current_frame = self:getCurrentFrame()
  if not current_frame then
    print("No current frame available. Start debugging first.")
    return
  end
  
  -- Close existing popup if open
  if self.active_popup then
    self:closeCurrentPopup()
  end
  
  -- Show new popup
  self:show(current_frame, { auto_refresh = true })
end

function VariablesPopup:closeCurrentPopup()
  if self.active_popup then
    self:closePopup(self.active_popup.popup, self.active_popup.buffer)
  end
end

-- ========================================
-- FRAME CONTEXT HELPERS
-- ========================================

function VariablesPopup:getCurrentFrame()
  -- Delegate to Variables4 plugin for frame access
  -- This ensures we use the same frame tracking logic
  local variables4 = self.api:getPluginInstance(require('neodap.plugins.Variables4'))
  if variables4 then
    return variables4:getCurrentFrame()
  end
  
  -- Fallback: simple session-based frame detection
  local manager = self.api.manager
  if manager and manager.sessions then
    for _, session in pairs(manager.sessions) do
      -- Try to get current thread and frame
      local thread = session:getCurrentThread()
      if thread and thread:isStopped() then
        return thread:getCurrentFrame()
      end
    end
  end
  return nil
end

-- ========================================
-- EVENT HANDLING (Optional)
-- ========================================

function VariablesPopup:onFrameChanged(new_frame)
  -- Optionally refresh popup when frame changes
  if self.active_popup and self.active_popup.buffer.metadata.auto_refresh then
    self.active_popup.buffer.refresh()
  end
end

return VariablesPopup