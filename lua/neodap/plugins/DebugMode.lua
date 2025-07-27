-- DebugMode Orchestration Plugin
-- Provides integrated debug workflow with keybindings for various debug services

local BasePlugin = require('neodap.plugins.BasePlugin')

-- ========================================
-- PLUGIN CLASS
-- ========================================

---@class DebugMode: BasePlugin
local DebugMode = BasePlugin:extend()

DebugMode.name = "DebugMode"

-- ========================================
-- PLUGIN INITIALIZATION
-- ========================================

function DebugMode.plugin(api)
  return BasePlugin.createPlugin(api, DebugMode)
end

function DebugMode:listen()
  self.logger:info("Initializing DebugMode orchestration plugin")
  self:setupCommands()
  self.debug_mode_active = false
  self.logger:info("DebugMode orchestration plugin initialized")
end

-- ========================================
-- DEBUG MODE MANAGEMENT
-- ========================================

function DebugMode:setupCommands()
  self:registerCommands({
    { "DebugModeEnter", function() self:enter() end, { desc = "Enter debug mode with integrated keybindings" } },
    { "DebugModeExit", function() self:exit() end, { desc = "Exit debug mode" } },
    { "DebugModeToggle", function() self:toggle() end, { desc = "Toggle debug mode" } },
    { "DebugModeStatus", function() self:showStatus() end, { desc = "Show debug mode status" } }
  })
end

function DebugMode:enter()
  if self.debug_mode_active then
    print("Debug mode already active")
    return
  end
  
  self.logger:info("Entering debug mode")
  self.debug_mode_active = true
  
  -- Setup debug mode keybindings
  self:setupDebugKeybindings()
  
  -- Show status
  print("🐛 Debug mode active")
  print("Keybindings:")
  print("  v - Show variables")
  print("  b - Show breakpoints") 
  print("  s - Show stack trace")
  print("  q - Exit debug mode")
  print("  <F5> - Continue")
  print("  <F10> - Step over")
  print("  <F11> - Step into")
end

function DebugMode:exit()
  if not self.debug_mode_active then
    print("Debug mode not active")
    return
  end
  
  self.logger:info("Exiting debug mode")
  self.debug_mode_active = false
  
  -- Clean up keybindings
  self:cleanupDebugKeybindings()
  
  print("Debug mode deactivated")
end

function DebugMode:toggle()
  if self.debug_mode_active then
    self:exit()
  else
    self:enter()
  end
end

function DebugMode:showStatus()
  if self.debug_mode_active then
    print("🐛 Debug mode: ACTIVE")
    local session = self:getCurrentSession()
    if session then
      print("Session: " .. (session.name or "unnamed"))
      local thread = session:getCurrentThread()
      if thread then
        print("Thread: " .. (thread.ref.name or thread.ref.id))
        if thread:isStopped() then
          local frame = thread:getCurrentFrame()
          if frame then
            print("Frame: " .. (frame.ref.name or "unnamed") .. " (line " .. (frame.ref.line or "?") .. ")")
          end
        else
          print("Status: Running")
        end
      end
    else
      print("No active debugging session")
    end
  else
    print("Debug mode: INACTIVE")
  end
end

-- ========================================
-- KEYBINDING MANAGEMENT
-- ========================================

function DebugMode:setupDebugKeybindings()
  local opts = { noremap = true, silent = true, desc = "Debug mode" }
  
  -- Store original keymaps for restoration
  self.original_keymaps = {}
  
  -- Variables integration
  vim.keymap.set('n', 'v', function()
    self:showVariables()
  end, vim.tbl_extend("force", opts, { desc = "Debug: Show variables" }))
  
  -- Breakpoints integration  
  vim.keymap.set('n', 'b', function()
    self:showBreakpoints()
  end, vim.tbl_extend("force", opts, { desc = "Debug: Show breakpoints" }))
  
  -- Stack trace integration
  vim.keymap.set('n', 's', function()
    self:showStackTrace()
  end, vim.tbl_extend("force", opts, { desc = "Debug: Show stack trace" }))
  
  -- Exit debug mode
  vim.keymap.set('n', 'q', function()
    self:exit()
  end, vim.tbl_extend("force", opts, { desc = "Debug: Exit debug mode" }))
  
  -- Debug control
  vim.keymap.set('n', '<F5>', function()
    self:continue()
  end, vim.tbl_extend("force", opts, { desc = "Debug: Continue" }))
  
  vim.keymap.set('n', '<F10>', function()
    self:stepOver()
  end, vim.tbl_extend("force", opts, { desc = "Debug: Step over" }))
  
  vim.keymap.set('n', '<F11>', function()
    self:stepInto()
  end, vim.tbl_extend("force", opts, { desc = "Debug: Step into" }))
  
  vim.keymap.set('n', '<S-F11>', function()
    self:stepOut()
  end, vim.tbl_extend("force", opts, { desc = "Debug: Step out" }))
end

function DebugMode:cleanupDebugKeybindings()
  -- Remove debug mode keybindings
  local keys = { 'v', 'b', 's', 'q', '<F5>', '<F10>', '<F11>', '<S-F11>' }
  
  for _, key in ipairs(keys) do
    pcall(vim.keymap.del, 'n', key)
  end
  
  -- TODO: Restore original keymaps if needed
  self.original_keymaps = {}
end

-- ========================================
-- SERVICE INTEGRATION
-- ========================================

function DebugMode:showVariables()
  local current_frame = self:getCurrentFrame()
  if not current_frame then
    print("No current frame available. Start debugging and hit a breakpoint first.")
    return
  end
  
  self.logger:debug("Opening variables for frame " .. (current_frame.ref.id or "unknown"))
  
  -- Use VariablesPopup service
  local variables_popup = self.api:getPluginInstance(require('neodap.plugins.VariablesPopup'))
  if not variables_popup then
    print("VariablesPopup plugin not available")
    return
  end
  
  variables_popup:show(current_frame, {
    title = " Variables (Debug Mode) ",
    auto_refresh = true
  })
end

function DebugMode:showBreakpoints()
  -- Use BreakpointApi service (when available)
  print("Breakpoints view not yet implemented")
  -- TODO: Implement when we have a BreakpointBuffer service
end

function DebugMode:showStackTrace()
  -- Use StackTrace service (when available)
  print("Stack trace view not yet implemented")
  -- TODO: Implement when we have a StackTraceBuffer service
end

-- ========================================
-- DEBUG CONTROL
-- ========================================

function DebugMode:continue()
  local session = self:getCurrentSession()
  if not session then
    print("No active debugging session")
    return
  end
  
  local thread = session:getCurrentThread()
  if not thread then
    print("No current thread")
    return
  end
  
  if not thread:isStopped() then
    print("Thread is not stopped")
    return
  end
  
  thread:Continue()
  print("Continuing execution...")
end

function DebugMode:stepOver()
  local session = self:getCurrentSession()
  if not session then
    print("No active debugging session")
    return
  end
  
  local thread = session:getCurrentThread()
  if not thread then
    print("No current thread")
    return
  end
  
  if not thread:isStopped() then
    print("Thread is not stopped")
    return
  end
  
  thread:StepOver()
  print("Stepping over...")
end

function DebugMode:stepInto()
  local session = self:getCurrentSession()
  if not session then
    print("No active debugging session")
    return
  end
  
  local thread = session:getCurrentThread()
  if not thread then
    print("No current thread")
    return
  end
  
  if not thread:isStopped() then
    print("Thread is not stopped")
    return
  end
  
  thread:StepIn()
  print("Stepping into...")
end

function DebugMode:stepOut()
  local session = self:getCurrentSession()
  if not session then
    print("No active debugging session")
    return
  end
  
  local thread = session:getCurrentThread()
  if not thread then
    print("No current thread")
    return
  end
  
  if not thread:isStopped() then
    print("Thread is not stopped")
    return
  end
  
  thread:StepOut()
  print("Stepping out...")
end

-- ========================================
-- CONTEXT HELPERS
-- ========================================

function DebugMode:getCurrentSession()
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

function DebugMode:getCurrentFrame()
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

return DebugMode