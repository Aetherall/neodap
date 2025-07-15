local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local Location = require("neodap.api.Location")
local NvimAsync = require("neodap.tools.async")
local StackNavigation = require("neodap.plugins.StackNavigation")

---@class neodap.plugin.DebugModeProps
---@field api Api
---@field logger Logger
---@field stackNavigation neodap.plugin.StackNavigation
---@field namespace integer
---@field is_active boolean
---@field original_maps table
---@field augroup integer

---@class neodap.plugin.DebugMode: neodap.plugin.DebugModeProps
---@field new Constructor<neodap.plugin.DebugModeProps>
local DebugMode = Class()

DebugMode.name = "DebugMode"
DebugMode.description = "Custom vim mode for stack navigation using hjkl keys"

function DebugMode.plugin(api)
  local logger = Logger.get()
  
  local instance = DebugMode:new({
    api = api,
    logger = logger,
    stackNavigation = api:getPluginInstance(StackNavigation),
    namespace = vim.api.nvim_create_namespace("neodap_debug_mode"),
    is_active = false,
    original_maps = {},
    augroup = vim.api.nvim_create_augroup("NeodapDebugMode", { clear = true })
  })
  
  instance:listen()
  instance:setupCommands()
  
  return instance
end

-- Set up reactive listeners for auto-activation
function DebugMode:listen()
  self.logger:debug("DebugMode: Setting up reactive listeners")
  
  self.api:onSession(function(session)
    session:onThread(function(thread)
      
      -- Auto-enter debug mode when thread stops
      thread:onStopped(function()
        self:enterDebugMode()
      end, { name = self.name .. ".onStopped" })
      
      -- Auto-exit debug mode when thread resumes
      thread:onResumed(function()
        self:exitDebugMode()
      end, { name = self.name .. ".onResumed" })
      
      -- Auto-exit debug mode when thread exits
      thread:onExited(function()
        self:exitDebugMode()
      end, { name = self.name .. ".onExited" })
      
    end, { name = self.name .. ".onThread" })
  end, { name = self.name .. ".onSession" })
end

-- Set up manual commands for debug mode
function DebugMode:setupCommands()
  vim.api.nvim_create_user_command("NeodapDebugModeEnter", function()
    self:enterDebugMode()
  end, { desc = "Enter Neodap debug mode" })
  
  vim.api.nvim_create_user_command("NeodapDebugModeExit", function()
    self:exitDebugMode()
  end, { desc = "Exit Neodap debug mode" })
  
  vim.api.nvim_create_user_command("NeodapDebugModeToggle", function()
    if self.is_active then
      self:exitDebugMode()
    else
      self:enterDebugMode()
    end
  end, { desc = "Toggle Neodap debug mode" })
end

-- Enter debug mode: install key mappings and update status
function DebugMode:enterDebugMode()
  if self.is_active then
    self.logger:debug("DebugMode: Already active, ignoring enter request")
    return
  end
  
  self.logger:info("DebugMode: Entering debug mode")
  self.is_active = true
  
  -- Save original mappings
  self:saveOriginalMappings()
  
  -- Install debug mode key mappings
  self:installDebugMappings()
  
  -- Update status line
  self:updateStatusLine()
  
  -- Show mode message
  vim.api.nvim_echo({{ "-- DEBUG --", "ModeMsg" }}, false, {})
end

-- Exit debug mode: restore original mappings and status
function DebugMode:exitDebugMode()
  if not self.is_active then
    self.logger:debug("DebugMode: Not active, ignoring exit request")
    return
  end
  
  self.logger:info("DebugMode: Exiting debug mode")
  self.is_active = false
  
  -- Restore original mappings
  self:restoreOriginalMappings()
  
  -- Clear status line updates
  self:clearStatusLine()
  
  -- Clear mode message
  vim.api.nvim_echo({{ "", "Normal" }}, false, {})
end

-- Save current key mappings that we'll override
function DebugMode:saveOriginalMappings()
  self.original_maps = {}
  
  local keys_to_save = { 'h', 'j', 'k', 'l', '<Left>', '<Down>', '<Up>', '<Right>', '<CR>', '<Esc>', 'q', '?' }
  
  for _, key in ipairs(keys_to_save) do
    local existing = vim.fn.maparg(key, 'n', false, true)
    if existing and existing.lhs then
      self.original_maps[key] = existing
      self.logger:debug("DebugMode: Saved mapping for", key)
    end
  end
end

-- Install debug mode key mappings
function DebugMode:installDebugMappings()
  local opts = { noremap = true, silent = true, desc = "DebugMode: " }
  
  -- Enhanced navigation and stepping
  vim.keymap.set('n', 'h', function() self:navigateDown() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Navigate down stack (towards callee)" }))
  vim.keymap.set('n', 'l', function() self:smartRightKey() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Smart: step in if top frame, navigate up otherwise" }))
  vim.keymap.set('n', 'j', function() self:stepOver() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Step over (next line)" }))
  vim.keymap.set('n', 'k', function() self:stepOut() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Step out (return to caller)" }))
  
  -- Arrow keys
  vim.keymap.set('n', '<Left>', function() self:navigateDown() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Navigate down stack (towards callee)" }))
  vim.keymap.set('n', '<Right>', function() self:smartRightKey() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Smart: step in if top frame, navigate up otherwise" }))
  vim.keymap.set('n', '<Down>', function() self:stepOver() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Step over (next line)" }))
  vim.keymap.set('n', '<Up>', function() self:stepOut() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Step out (return to caller)" }))
  
  -- Jump to current frame
  vim.keymap.set('n', '<CR>', function() self:jumpToCurrentFrame() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Jump to current frame" }))
  
  -- Exit debug mode
  vim.keymap.set('n', '<Esc>', function() self:exitDebugMode() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Exit debug mode" }))
  vim.keymap.set('n', 'q', function() self:exitDebugMode() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Exit debug mode" }))
  
  -- Help
  vim.keymap.set('n', '?', function() self:showHelp() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Show help" }))
  
  self.logger:debug("DebugMode: Installed debug key mappings")
end

-- Restore original key mappings
function DebugMode:restoreOriginalMappings()
  local keys_to_restore = { 'h', 'j', 'k', 'l', '<Left>', '<Down>', '<Up>', '<Right>', '<CR>', '<Esc>', 'q', '?' }
  
  for _, key in ipairs(keys_to_restore) do
    -- Delete our mapping
    pcall(vim.keymap.del, 'n', key)
    
    -- Restore original if it existed
    local original = self.original_maps[key]
    if original then
      local opts = {
        noremap = original.noremap == 1,
        silent = original.silent == 1,
        expr = original.expr == 1,
        desc = original.desc
      }
      vim.keymap.set('n', key, original.rhs, opts)
      self.logger:debug("DebugMode: Restored mapping for", key)
    end
  end
  
  self.original_maps = {}
end

-- Delegate to StackNavigation plugin for frame operations
---@param location api.Location?
---@return api.Frame?
function DebugMode:getClosestFrame(location)
  return self.stackNavigation:getClosestFrame(location)
end

-- Navigate up the call stack using StackNavigation
function DebugMode:navigateUp()
  self.stackNavigation:up()
  self:updateStatusLine()
end

-- Navigate down the call stack using StackNavigation
function DebugMode:navigateDown()
  self.stackNavigation:down()
  self:updateStatusLine()
end

-- Step operations using thread from current frame
function DebugMode:stepIn()
  NvimAsync.run(function()
    local closest = self:getClosestFrame()
    if closest and closest.stack and closest.stack.thread then
      closest.stack.thread:stepIn()
      vim.api.nvim_echo({{ "DebugMode: Step Into", "Normal" }}, false, {})
    else
      vim.api.nvim_echo({{ "DebugMode: No active thread for step in", "WarningMsg" }}, false, {})
    end
  end)
end

function DebugMode:stepOut()
  NvimAsync.run(function()
    local closest = self:getClosestFrame()
    if closest and closest.stack and closest.stack.thread then
      closest.stack.thread:stepOut()
      vim.api.nvim_echo({{ "DebugMode: Step Out", "Normal" }}, false, {})
    else
      vim.api.nvim_echo({{ "DebugMode: No active thread for step out", "WarningMsg" }}, false, {})
    end
  end)
end

function DebugMode:stepOver()
  NvimAsync.run(function()
    local closest = self:getClosestFrame()
    if closest and closest.stack and closest.stack.thread then
      closest.stack.thread:stepOver()
      vim.api.nvim_echo({{ "DebugMode: Step Over", "Normal" }}, false, {})
    else
      vim.api.nvim_echo({{ "DebugMode: No active thread for step over", "WarningMsg" }}, false, {})
    end
  end)
end

-- Intelligent right key: stepIn if on top frame, navigate up otherwise
function DebugMode:smartRightKey()
  local closest = self:getClosestFrame()
  if not closest then
    vim.api.nvim_echo({{ "DebugMode: No frame available", "WarningMsg" }}, false, {})
    return
  end
  
  local top_frame = closest.stack:top()
  if closest == top_frame then
    -- On top frame: step into
    self:stepIn()
  else
    -- Not on top frame: navigate up stack
    self:navigateUp()
  end
end

-- Jump to current frame using StackNavigation
function DebugMode:jumpToCurrentFrame()
  NvimAsync.run(function()
    local closest = self:getClosestFrame()
    if closest then 
      closest:jump()
      self:updateStatusLine()
      vim.api.nvim_echo({{ "DebugMode: Jumped to current frame", "Normal" }}, false, {})
    else
      vim.api.nvim_echo({{ "DebugMode: No frame at cursor", "WarningMsg" }}, false, {})
    end
  end)
end

-- Show help message
function DebugMode:showHelp()
  local help_lines = {
    "=== Neodap Debug Mode Help ===",
    "",
    "Stack Navigation:",
    "  h/← : Navigate down stack (towards callee)",
    "  l/→ : Smart navigation/stepping:",
    "         • If on top frame: Step into function calls",
    "         • If not on top: Navigate up stack (towards caller)",
    "",
    "Execution Control:",
    "  j/↓ : Step over (next line, same level)",
    "  k/↑ : Step out (return to caller)",
    "",
    "Actions:",
    "  <CR>  : Jump to current frame location",
    "  <Esc> : Exit debug mode",
    "  q     : Exit debug mode", 
    "  ?     : Show this help",
    "",
    "Status: [current frame] / [total frames] location"
  }
  
  vim.api.nvim_echo(vim.tbl_map(function(line) return { line, "Normal" } end, help_lines), false, {})
end

-- Update status line to show debug mode info
function DebugMode:updateStatusLine()
  -- if not self.is_active then return end
  
  -- local closest = self:getClosestFrame()
  -- if closest then
  --   local stack = closest.stack
  --   local frames = stack:frames()
  --   local current_index = stack:indexOf(closest.ref.id)
  --   local total_frames = #frames
    
  --   local status = string.format("DEBUG [%d/%d] %s", 
  --     current_index or 0, 
  --     total_frames,
  --     closest:location() and closest:location().key or "unknown")
    
  --   vim.g.neodap_debug_mode_status = status
  -- else
  --   vim.g.neodap_debug_mode_status = "DEBUG [no frames]"
  -- end
  
  -- -- Trigger status line refresh
  -- vim.cmd("redrawstatus")
end

-- Clear status line
function DebugMode:clearStatusLine()
  -- vim.g.neodap_debug_mode_status = nil
  -- vim.cmd("redrawstatus")
end

-- Cleanup method
function DebugMode:destroy()
  self.logger:debug("DebugMode: Destroying plugin")
  
  -- Exit debug mode if active
  if self.is_active then
    self:exitDebugMode()
  end
  
  -- Clear autocommands
  pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
  
  -- Clear user commands
  pcall(vim.api.nvim_del_user_command, "NeodapDebugModeEnter")
  pcall(vim.api.nvim_del_user_command, "NeodapDebugModeExit")
  pcall(vim.api.nvim_del_user_command, "NeodapDebugModeToggle")
  
  self.logger:info("DebugMode: Plugin destroyed")
end

return DebugMode