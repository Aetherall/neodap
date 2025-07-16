local Logger = require("neodap.tools.logger")
local Class = require("neodap.tools.class")
local Location = require("neodap.api.Location")
local NvimAsync = require("neodap.tools.async")
local StackNavigation = require("neodap.plugins.StackNavigation")
local DebugOverlay = require("neodap.plugins.DebugOverlay")
local StackFrameTelescope = require("neodap.plugins.StackFrameTelescope")

---@class neodap.plugin.DebugModeProps
---@field api Api
---@field logger Logger
---@field stackNavigation neodap.plugin.StackNavigation
---@field debugOverlay neodap.plugin.DebugOverlay
---@field stackFrameTelescope neodap.plugin.StackFrameTelescope
---@field namespace integer
---@field is_active boolean
---@field original_maps table
---@field augroup integer

---@class neodap.plugin.DebugMode: neodap.plugin.DebugModeProps
---@field new Constructor<neodap.plugin.DebugModeProps>
local DebugMode = Class()

DebugMode.name = "DebugMode"
DebugMode.description = "Custom vim mode for stack navigation using arrow keys (preserves hjkl for normal navigation)"

function DebugMode.plugin(api)
    local logger = Logger.get()

    local instance = DebugMode:new({
        api = api,
        logger = logger,
        stackNavigation = api:getPluginInstance(StackNavigation),
        debugOverlay = api:getPluginInstance(DebugOverlay),
        stackFrameTelescope = api:getPluginInstance(StackFrameTelescope),
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
                self:EnterDebugMode()
            end, { name = self.name .. ".onStopped" })

            -- Auto-exit debug mode when thread resumes
            thread:onResumed(function()
                self:ExitDebugMode()
            end, { name = self.name .. ".onResumed" })

            -- Auto-exit debug mode when thread exits
            thread:onExited(function()
                self:ExitDebugMode()
            end, { name = self.name .. ".onExited" })
        end, { name = self.name .. ".onThread" })
    end, { name = self.name .. ".onSession" })
end

-- Set up manual commands for debug mode
function DebugMode:setupCommands()
    vim.api.nvim_create_user_command("NeodapDebugModeEnter", function()
        self:EnterDebugMode()
    end, { desc = "Enter Neodap debug mode" })

    vim.api.nvim_create_user_command("NeodapDebugModeExit", function()
        self:ExitDebugMode()
    end, { desc = "Exit Neodap debug mode" })

    vim.api.nvim_create_user_command("NeodapDebugModeToggle", function()
        self:ToggleDebugMode()
    end, { desc = "Toggle Neodap debug mode" })

    -- Add convenient keymap for entering debug mode
    vim.keymap.set("n", "<leader>dm", function()
        self:EnterDebugMode()
    end, { desc = "Enter Neodap debug mode" })
end

-- Enter debug mode: install key mappings and update status
function DebugMode:EnterDebugMode()
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
    vim.api.nvim_echo({ { "-- DEBUG --", "ModeMsg" } }, false, {})

    -- Show DebugOverlay when entering debug mode
    if self.debugOverlay then
        self.debugOverlay:show()
    end

    -- Navigate to smart closest frame when entering debug mode
    self:JumpToCurrentFrame()
end


function DebugMode:ToggleDebugMode()
    if self.is_active then
        self:ExitDebugMode()
    else
        self:EnterDebugMode()
    end
end

-- Exit debug mode: restore original mappings and status
function DebugMode:ExitDebugMode()
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

    -- Hide DebugOverlay when exiting debug mode
    if self.debugOverlay then
        self.debugOverlay:hide()
    end

    -- Clear mode message
    vim.api.nvim_echo({ { "", "Normal" } }, false, {})
end

-- Save current key mappings that we'll override
function DebugMode:saveOriginalMappings()
    self.original_maps = {}

    local keys_to_save = { '<Left>', '<Down>', '<Up>', '<Right>', '<CR>', '<Esc>', 'q', '?', 's' }

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

    -- Arrow keys only - preserve hjkl for normal navigation
    vim.keymap.set('n', '<Left>', function() self:NavigateDown() end,
        vim.tbl_extend('force', opts, { desc = opts.desc .. "Navigate down stack (towards callee)" }))
    vim.keymap.set('n', '<Right>', function() self:SmartRightKey() end,
        vim.tbl_extend('force', opts, { desc = opts.desc .. "Smart: step in if top frame, navigate up otherwise" }))
    vim.keymap.set('n', '<Down>', function() self:StepOver() end,
        vim.tbl_extend('force', opts, { desc = opts.desc .. "Step over (next line)" }))
    vim.keymap.set('n', '<Up>', function() self:StepOut() end,
        vim.tbl_extend('force', opts, { desc = opts.desc .. "Step out (return to caller)" }))

    -- Jump to current frame
    vim.keymap.set('n', '<CR>', function() self:JumpToCurrentFrame() end,
        vim.tbl_extend('force', opts, { desc = opts.desc .. "Jump to current frame" }))

    -- Exit debug mode
    vim.keymap.set('n', '<Esc>', function() self:ExitDebugMode() end,
        vim.tbl_extend('force', opts, { desc = opts.desc .. "Exit debug mode" }))
    vim.keymap.set('n', 'q', function() self:ExitDebugMode() end,
        vim.tbl_extend('force', opts, { desc = opts.desc .. "Exit debug mode" }))

    -- Stack frame telescope
    vim.keymap.set('n', 's', function() self:ShowStackFrameTelescope() end,
        vim.tbl_extend('force', opts, { desc = opts.desc .. "Show stack frame telescope" }))

    -- Help
    vim.keymap.set('n', '?', function() self:ShowHelp() end,
        vim.tbl_extend('force', opts, { desc = opts.desc .. "Show help" }))

    self.logger:debug("DebugMode: Installed debug key mappings (arrow keys only)")
end

-- Restore original key mappings
function DebugMode:restoreOriginalMappings()
    local keys_to_restore = { '<Left>', '<Down>', '<Up>', '<Right>', '<CR>', '<Esc>', 'q', '?', 's' }

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
    self.stackNavigation:Up()
    self:updateStatusLine()
end

-- Navigate down the call stack using StackNavigation
function DebugMode:NavigateDown()
    self.stackNavigation:Down()
    self:updateStatusLine()
end

-- Step operations using thread from current frame
function DebugMode:stepIn()
    local closest = self:getClosestFrame()
    if closest and closest.stack and closest.stack.thread then
        closest.stack.thread:stepIn()
        vim.api.nvim_echo({ { "DebugMode: Step Into", "Normal" } }, false, {})
    else
        vim.api.nvim_echo({ { "DebugMode: No active thread for step in", "WarningMsg" } }, false, {})
    end
end

function DebugMode:StepOut()
    local closest = self:getClosestFrame()
    if closest and closest.stack and closest.stack.thread then
        closest.stack.thread:stepOut()
        vim.api.nvim_echo({ { "DebugMode: Step Out", "Normal" } }, false, {})
    else
        vim.api.nvim_echo({ { "DebugMode: No active thread for step out", "WarningMsg" } }, false, {})
    end
end

function DebugMode:StepOver()
    local closest = self:getClosestFrame()
    if closest and closest.stack and closest.stack.thread then
        closest.stack.thread:stepOver()
        vim.api.nvim_echo({ { "DebugMode: Step Over", "Normal" } }, false, {})
    else
        vim.api.nvim_echo({ { "DebugMode: No active thread for step over", "WarningMsg" } }, false, {})
    end
end

-- Intelligent right key: stepIn if on top frame, navigate up otherwise
function DebugMode:SmartRightKey()
    local closest = self:getClosestFrame()
    if not closest then
        vim.api.nvim_echo({ { "DebugMode: No frame available", "WarningMsg" } }, false, {})
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
function DebugMode:JumpToCurrentFrame()
    local closest = self:getClosestFrame()
    if closest then
        closest:jump()
        self:updateStatusLine()
        vim.api.nvim_echo({ { "DebugMode: Jumped to current frame", "Normal" } }, false, {})
    else
        vim.api.nvim_echo({ { "DebugMode: No frame at cursor", "WarningMsg" } }, false, {})
    end
end

-- Show stack frame telescope
function DebugMode:ShowStackFrameTelescope()
    if not self.stackFrameTelescope:is_available() then
        vim.api.nvim_echo({ { "DebugMode: Telescope not available", "WarningMsg" } }, false, {})
        return
    end

    self.stackFrameTelescope:ShowFramePicker()
end

-- Show help message
function DebugMode:ShowHelp()
    local help_lines = {
        "=== Neodap Debug Mode Help ===",
        "",
        "Stack Navigation (Arrow Keys Only):",
        "  ←  : Navigate down stack (towards callee)",
        "  →  : Smart navigation/stepping:",
        "        • If on top frame: Step into function calls",
        "        • If not on top: Navigate up stack (towards caller)",
        "",
        "Execution Control:",
        "  ↓  : Step over (next line, same level)",
        "  ↑  : Step out (return to caller)",
        "",
        "Actions:",
        "  <CR>  : Jump to current frame location",
        "  s     : Show stack frame telescope browser",
        "  <Esc> : Exit debug mode",
        "  q     : Exit debug mode",
        "  ?     : Show this help",
        "",
        "Note: hjkl keys remain available for normal navigation",
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
        self:ExitDebugMode()
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