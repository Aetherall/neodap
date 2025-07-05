local Class = require('neodap.tools.class')

---@class LoggerProps
---@field file any?
---@field filepath string
---@field enabled boolean
---@field silent boolean

---@class Logger: LoggerProps
---@field new Constructor<LoggerProps>
local Logger = Class()

-- Create a singleton instance
local instance = nil

---Get the next log file number
---@return integer
local function get_next_log_number()
  -- Get the project root directory (where this file is located)
  local source = debug.getinfo(1, "S").source:sub(2)
  local project_root = vim.fn.fnamemodify(source, ":p:h:h:h:h") -- Go up 4 levels from lua/neodap/tools/logger.lua
  local logdir = project_root .. "/log"
  
  -- Create log directory if it doesn't exist
  vim.fn.mkdir(logdir, "p")
  
  -- Find existing log files and get the highest number
  local max_num = 0
  local files = vim.fn.glob(logdir .. "/neodap_*.log", false, true)
  
  for _, file in ipairs(files) do
    local num = tonumber(file:match("neodap_(%d+)%.log"))
    if num and num > max_num then
      max_num = num
    end
  end
  
  return max_num + 1
end

---@return Logger
function Logger.get()
  if not instance then
    local source = debug.getinfo(1, "S").source:sub(2)
    local project_root = vim.fn.fnamemodify(source, ":p:h:h:h:h")
    local logdir = project_root .. "/log"
    
    local log_number = get_next_log_number()
    local filepath = logdir .. "/neodap_" .. log_number .. ".log"
    
    -- Check if we're in playground mode by looking for specific environment
    local is_playground = vim.env.NEODAP_PLAYGROUND or (vim.fn.argv()[0] and vim.fn.argv()[0]:match("playground%.lua"))
    
    instance = Logger:new({
      filepath = filepath,
      file = nil,
      enabled = true,
      silent = is_playground and true or false
    })
    
    instance:_open()
    instance:info("=== Neodap Debug Log Started ===")
    instance:info("Log file: " .. filepath)
    instance:info("Log number: " .. log_number)
    instance:info("Silent mode: " .. tostring(instance.silent))
  end
  
  return instance
end

function Logger:_open()
  if not self.file then
    self.file = io.open(self.filepath, "a")
    if self.file then
      self.file:setvbuf("line") -- Line buffering for immediate writes
    end
  end
end

function Logger:_write(level, ...)
  if not self.enabled then return end
  
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
  
  local log_line = string.format("[%s] [%s] %s - %s\n", timestamp, level, location, message)
  self.file:write(log_line)
  self.file:flush()
end

---Log debug message
function Logger:debug(...)
  self:_write("DEBUG", ...)
end

---Log info message
function Logger:info(...)
  self:_write("INFO", ...)
end

---Log warning message
function Logger:warn(...)
  self:_write("WARN", ...)
end

---Log error message
function Logger:error(...)
  self:_write("ERROR", ...)
end

---Log buffer snapshot for debugging visual state
---@param bufnr number Buffer number to capture
---@param label string? Optional label for the snapshot
function Logger:snapshot(bufnr, label)
  if not self.enabled then return end
  
  -- Import buffer snapshot functionality
  local BufferSnapshot = require("spec.helpers.buffer_snapshot")
  
  local snapshot_label = label or "Buffer Snapshot"
  self:info("=== " .. snapshot_label .. " ===")
  self:info("Buffer ID:", bufnr)
  
  -- Check if buffer is valid
  if not bufnr or bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
    self:warn("Invalid buffer for snapshot:", bufnr)
    return
  end
  
  -- Capture the snapshot
  local snapshot = BufferSnapshot.capture_buffer_snapshot(bufnr)
  if snapshot then
    -- Log each line of the snapshot
    local lines = vim.split(snapshot, "\n")
    for i, line in ipairs(lines) do
      self:info(string.format("L%d: %s", i, line))
    end
  else
    self:warn("Failed to capture buffer snapshot")
  end
  
  self:info("=== End " .. snapshot_label .. " ===")
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

---Get the log file path
---@return string
function Logger:getFilePath()
  return self.filepath
end

---Close the log file
function Logger:close()
  if self.file then
    self:info("=== Neodap Debug Log Ended ===")
    self.file:close()
    self.file = nil
  end
end

return Logger