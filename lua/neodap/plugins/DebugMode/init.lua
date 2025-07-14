local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local Location = require("neodap.api.Location")
local NvimAsync = require("neodap.tools.async")

---@class neodap.plugin.DebugModeProps
---@field api Api
---@field logger Logger
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
  
  -- Stack navigation
  vim.keymap.set('n', 'h', function() self:navigateDown() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Navigate down stack" }))
  vim.keymap.set('n', 'l', function() self:navigateUp() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Navigate up stack" }))
  vim.keymap.set('n', 'j', function() self:navigateDown() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Navigate down stack" }))
  vim.keymap.set('n', 'k', function() self:navigateUp() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Navigate up stack" }))
  
  -- Arrow keys
  vim.keymap.set('n', '<Left>', function() self:navigateDown() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Navigate down stack" }))
  vim.keymap.set('n', '<Right>', function() self:navigateUp() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Navigate up stack" }))
  vim.keymap.set('n', '<Down>', function() self:navigateDown() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Navigate down stack" }))
  vim.keymap.set('n', '<Up>', function() self:navigateUp() end, 
    vim.tbl_extend('force', opts, { desc = opts.desc .. "Navigate up stack" }))
  
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

-- Get closest frame to cursor (reuse StackNavigation logic)
---@param location api.Location?
---@return api.Frame?
function DebugMode:getClosestFrame(location)
  local target = location or Location.fromCursor()

  local closest = nil
  local closest_distance = math.huge
  
  -- Find frame closest to cursor across all sessions and threads
  for session in self.api:eachSession() do
    for thread in session:eachThread({ filter = 'stopped' }) do
      local stack = thread:stack()
      if stack then
        for frame in stack:eachFrame({ sourceId = target.sourceId }) do
          local frame_location = frame:location()
          if frame_location then
            local distance = frame_location:distance(target)
            if distance < closest_distance then
              closest_distance = distance
              closest = frame
            end
          end
        end
      end
    end
  end

  self.logger:debug("DebugMode: Closest frame found at distance", closest_distance)
  return closest
end

-- Navigate up the call stack
function DebugMode:navigateUp()
  NvimAsync.run(function()
    local closest = self:getClosestFrame()
    local parent = closest and closest:up()
    if parent then 
      parent:jump()
      self:updateStatusLine()
    else
      vim.api.nvim_echo({{ "DebugMode: No parent frame available", "WarningMsg" }}, false, {})
    end
  end)
end

-- Navigate down the call stack
function DebugMode:navigateDown()
  NvimAsync.run(function()
    local closest = self:getClosestFrame()
    local child = closest and closest:down()
    if child then 
      child:jump()
      self:updateStatusLine()
    else
      vim.api.nvim_echo({{ "DebugMode: No child frame available", "WarningMsg" }}, false, {})
    end
  end)
end

-- Jump to current frame
function DebugMode:jumpToCurrentFrame()
  NvimAsync.run(function()
    local closest = self:getClosestFrame()
    if closest then 
      closest:jump()
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
    "Navigation:",
    "  h/→ : Navigate down stack (towards caller)",
    "  l/← : Navigate up stack (towards callee)", 
    "  j/↓ : Navigate down stack (towards callee)",
    "  k/↑ : Navigate up stack (towards caller)",
    "",
    "Actions:",
    "  <CR>  : Jump to current frame",
    "  <Esc> : Exit debug mode",
    "  q     : Exit debug mode",
    "  ?     : Show this help",
    "",
    "Status shows: [current frame] / [total frames]"
  }
  
  vim.api.nvim_echo(vim.tbl_map(function(line) return { line, "Normal" } end, help_lines), false, {})
end

-- Update status line to show debug mode info
function DebugMode:updateStatusLine()
  if not self.is_active then return end
  
  local closest = self:getClosestFrame()
  if closest then
    local stack = closest.stack
    local frames = stack:frames()
    local current_index = stack:indexOf(closest.ref.id)
    local total_frames = #frames
    
    local status = string.format("DEBUG [%d/%d] %s", 
      current_index or 0, 
      total_frames,
      closest:location() and closest:location().key or "unknown")
    
    vim.g.neodap_debug_mode_status = status
  else
    vim.g.neodap_debug_mode_status = "DEBUG [no frames]"
  end
  
  -- Trigger status line refresh
  vim.cmd("redrawstatus")
end

-- Clear status line
function DebugMode:clearStatusLine()
  vim.g.neodap_debug_mode_status = nil
  vim.cmd("redrawstatus")
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