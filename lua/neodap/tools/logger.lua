local Class = require('neodap.tools.class')

---@class LoggerProps
---@field file any?
---@field filepath string
---@field enabled boolean
---@field silent boolean
---@field namespace string
---@field level integer -- Current log level threshold

---@class Logger: LoggerProps
---@field new Constructor<LoggerProps>
local Logger = Class()

-- Log level constants
local LOG_LEVELS = {
    TRACE = 1,
    DEBUG = 2,
    INFO = 3,
    NOTICE = 4,
    WARN = 5,
    ERROR = 6,
    FAIL = 7,
    CRITICAL = 8
}

-- Level names for output
local LEVEL_NAMES = {
    [1] = "TRACE",
    [2] = "DEBUG",
    [3] = "INFO",
    [4] = "NOTICE",
    [5] = "WARN",
    [6] = "ERROR",
    [7] = "FAIL",
    [8] = "CRITICAL"
}

-- Default log level (INFO)
local DEFAULT_LOG_LEVEL = LOG_LEVELS
.TRACE                                     -- os.getenv("NEODAP_LOG_LEVEL") and LOG_LEVELS[os.getenv("NEODAP_LOG_LEVEL"):upper()] or
-- LOG_LEVELS.INFO

-- Create namespace-specific instances
local instances = {}

-- Process-specific shared log file
local process_log_file = nil
local process_log_path = nil

---Find the next available log file number
---@return integer
local function get_next_log_number()
    -- Get the project root directory (where this file is located)
    local source = debug.getinfo(1, "S").source:sub(2)
    local project_root = vim.fn.fnamemodify(source, ":p:h:h:h:h") -- Go up 4 levels from lua/neodap/tools/logger.lua
    local logdir = project_root .. "/log"

    -- Create log directory if it doesn't exist
    vim.fn.mkdir(logdir, "p")

    -- Find the next available log file number
    local i = 0
    while true do
        local filepath = logdir .. "/neodap." .. i .. ".log"
        if vim.fn.filereadable(filepath) == 0 then
            return i
        end
        i = i + 1
    end
end

---Get the process-specific log file path
---@return string
local function get_process_log_path()
    if not process_log_path then
        -- Get the project root directory (where this file is located)
        local source = debug.getinfo(1, "S").source:sub(2)
        local project_root = vim.fn.fnamemodify(source, ":p:h:h:h:h") -- Go up 4 levels from lua/neodap/tools/logger.lua
        local logdir = project_root .. "/log"

        -- Create log directory if it doesn't exist
        vim.fn.mkdir(logdir, "p")

        -- Get the next available log file number for this process
        local log_number = get_next_log_number()
        process_log_path = logdir .. "/neodap." .. log_number .. ".log"
    end
    return process_log_path
end

---@param namespace string? Optional namespace for the logger
---@return Logger
function Logger.get(namespace)
    namespace = namespace or "default"

    if not instances[namespace] then
        local filepath = get_process_log_path()

        -- Check if we're in playground mode by looking for specific environment
        -- Use pcall to safely access vim.env in case we're in a fast event context
        local is_playground = false
        pcall(function()
            is_playground = vim.env.NEODAP_PLAYGROUND or
                (vim.fn.argv()[0] and vim.fn.argv()[0]:match("playground%.lua"))
        end)

        instances[namespace] = Logger:new({
            filepath = filepath,
            file = nil,
            enabled = true,
            silent = is_playground and true or false,
            namespace = namespace,
            level = DEFAULT_LOG_LEVEL
        })

        -- Only write startup message for the first instance in this process
        if not process_log_file then
            instances[namespace]:_open()
            instances[namespace]:debug("=== Neodap Debug Log Started ===")
            instances[namespace]:debug("Log file: " .. filepath)
            instances[namespace]:debug("Namespace: " .. namespace)
            instances[namespace]:debug("Silent mode: " .. tostring(instances[namespace].silent))
            process_log_file = instances[namespace].file
        else
            -- Share the same file handle for all instances in this process
            instances[namespace].file = process_log_file
            instances[namespace]:debug("Logger initialized for namespace: " .. namespace)
        end
    end

    return instances[namespace]
end

function Logger:_open()
    if not self.file then
        self.file = io.open(self.filepath, "a")
        if self.file then
            self.file:setvbuf("line") -- Line buffering for immediate writes
        end
    end
end

function Logger:_write(level_num, ...)
    if not self.enabled then return end

    -- Check if this log level should be written
    if level_num < self.level then return end

    self:_open()
    if not self.file then return end

    local timestamp = os.date("%Y-%m-%d %H:%M:%S.%03d", os.time())
    local info = debug.getinfo(3, "Sl")
    local location = string.format("%s:%d", info.short_src:match("([^/]+)$") or info.short_src, info.currentline)

    -- Convert all arguments to strings and concatenate
    local args = { ... }
    local message = ""
    for i, arg in ipairs(args) do
        if type(arg) == "table" then
            message = message .. vim.inspect(arg)
        else
            message = message .. tostring(arg)
        end
        if i < #args then
            message = message .. " "
        end
    end

    local level_name = LEVEL_NAMES[level_num] or "UNKNOWN"
    local namespace_prefix = self.namespace and self.namespace ~= "default" and "[" .. self.namespace .. "] " or ""
    local log_line = string.format("[%s] [%s] %s%s - %s\n", timestamp, level_name, namespace_prefix, location, message)
    self.file:write(log_line)
    self.file:flush()

    -- For NOTICE level and above, also show visual feedback
    if level_num >= LOG_LEVELS.NOTICE and not self.silent then
        local vim_level = vim.log.levels.INFO
        if level_num >= LOG_LEVELS.CRITICAL then
            vim_level = vim.log.levels.ERROR
        elseif level_num >= LOG_LEVELS.ERROR then
            vim_level = vim.log.levels.ERROR
        elseif level_num >= LOG_LEVELS.WARN then
            vim_level = vim.log.levels.WARN
        end

        local notify_message = namespace_prefix .. message
        -- Schedule the notification to avoid fast event context issues
        vim.schedule(function()
            vim.notify(notify_message, vim_level)
        end)
    end
end

---Log trace message (most verbose)
function Logger:trace(...)
    self:_write(LOG_LEVELS.TRACE, ...)
end

---Log debug message
function Logger:debug(...)
    self:_write(LOG_LEVELS.DEBUG, ...)
end

---Log info message
function Logger:info(...)
    self:_write(LOG_LEVELS.INFO, ...)
end

---Log notice message (will show visual feedback)
function Logger:notice(...)
    self:_write(LOG_LEVELS.NOTICE, ...)
end

---Log warning message (will show visual feedback)
function Logger:warn(...)
    self:_write(LOG_LEVELS.WARN, ...)
end

---Log error message (will show visual feedback)
function Logger:error(...)
    self:_write(LOG_LEVELS.ERROR, ...)
end

---Log fail message (will show visual feedback)
function Logger:fail(...)
    self:_write(LOG_LEVELS.FAIL, ...)
end

---Log critical message (will show visual feedback)
function Logger:critical(...)
    self:_write(LOG_LEVELS.CRITICAL, ...)
end

---Log buffer snapshot for debugging visual state
---@param bufnr number Buffer number to capture
---@param label string? Optional label for the snapshot
function Logger:snapshot(bufnr, label)
    return
    -- if not self.enabled then return end

    -- -- Import buffer snapshot functionality
    -- local BufferSnapshot = require("spec.helpers.buffer_snapshot")

    -- local snapshot_label = label or "Buffer Snapshot"
    -- self:info("=== " .. snapshot_label .. " ===")
    -- self:info("Buffer ID:", bufnr)

    -- -- Check if buffer is valid
    -- if not bufnr or bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
    --   self:warn("Invalid buffer for snapshot:", bufnr)
    --   return
    -- end

    -- -- Capture the snapshot
    -- local snapshot = BufferSnapshot.capture_buffer_snapshot(bufnr)
    -- if snapshot then
    --   -- Log each line of the snapshot
    --   local lines = vim.split(snapshot, "\n")
    --   for i, line in ipairs(lines) do
    --     self:info(string.format("L%d: %s", i, line))
    --   end
    -- else
    --   self:warn("Failed to capture buffer snapshot")
    -- end

    -- self:info("=== End " .. snapshot_label .. " ===")
end

---Enable logging
function Logger:enable()
    self.enabled = true
end

---Disable logging
function Logger:disable()
    self.enabled = false
end

---Enable silent mode (no console output)
function Logger:setSilent(silent)
    self.silent = silent
end

---Set the minimum log level
---@param level string|integer Log level name or number
function Logger:setLevel(level)
    if type(level) == "string" then
        local level_upper = string.upper(level)
        if LOG_LEVELS[level_upper] then
            self.level = LOG_LEVELS[level_upper]
        else
            self:warn("Unknown log level:", level, "- keeping current level")
        end
    elseif type(level) == "number" then
        if level >= 1 and level <= 8 then
            self.level = level
        else
            self:warn("Invalid log level number:", level, "- must be 1-8")
        end
    else
        self:warn("Invalid log level type:", type(level), "- must be string or number")
    end
end

---Get the current log level
---@return integer
function Logger:getLevel()
    return self.level
end

---Get the current log level name
---@return string
function Logger:getLevelName()
    return LEVEL_NAMES[self.level] or "UNKNOWN"
end

---Get the log file path
---@return string
function Logger:getFilePath()
    return self.filepath
end

---Close the log file
function Logger:close()
    if self.file then
        self:debug("=== Neodap Debug Log Ended ===")
        self.file:close()
        self.file = nil
    end
end

-- Export log levels for external use
Logger.LEVELS = LOG_LEVELS
Logger.LEVEL_NAMES = LEVEL_NAMES

return Logger
