-- neolog - Standalone file logger for Neovim plugins
--
-- Writes structured logs to a file with timestamp, source location, and optional payload.
--
-- Usage:
--   local log = require("neolog").new("myapp")
--   log:debug("message")
--   log:info("message", { key = "value" })

local M = {}

---@class neolog.Logger
---@field name string Logger name (used for log filename)
---@field config neolog.Config
local Logger = {}
Logger.__index = Logger

---@class neolog.Config
---@field level? string Minimum log level (default: "info")
---@field file? string Log file path (default: stdpath("log")/<name>.log)

-- Log levels with numeric values for comparison
local LEVELS = {
  trace = 1,
  debug = 2,
  info = 3,
  warn = 4,
  error = 5,
  fatal = 6,
}

-- Level names for output
local LEVEL_NAMES = {
  [1] = "TRACE",
  [2] = "DEBUG",
  [3] = "INFO",
  [4] = "WARN",
  [5] = "ERROR",
  [6] = "FATAL",
}

---Get the log file path
---@param self neolog.Logger
---@return string
local function get_log_file(self)
  if not self.config.file then
    local log_dir = vim.fn.stdpath("log")
    self.config.file = log_dir .. "/" .. self.name .. ".log"
  end
  return self.config.file
end

---Get caller info (filename and line number)
---@param level number Stack level to inspect
---@return string filename, number line
local function get_caller_info(level)
  local info = debug.getinfo(level + 1, "Sl")
  if info then
    local source = info.source
    -- Remove leading @ if present
    if source:sub(1, 1) == "@" then
      source = source:sub(2)
    end
    -- Get just the filename, not full path
    local filename = source:match("([^/\\]+)$") or source
    return filename, info.currentline or 0
  end
  return "unknown", 0
end

---Format a value for single-line log output
---@param value any
---@param depth? number Current recursion depth
---@return string
local function format_value(value, depth)
  depth = depth or 0
  if depth > 2 then return "..." end

  local t = type(value)
  if t == "string" then
    -- Escape newlines and quotes for single-line output
    local escaped = value:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub('"', '\\"')
    return '"' .. escaped .. '"'
  elseif t == "number" or t == "boolean" then
    return tostring(value)
  elseif t == "nil" then
    return "nil"
  elseif t == "table" then
    local parts = {}
    local count = 0
    for k, v in pairs(value) do
      count = count + 1
      if count > 10 then
        table.insert(parts, "...")
        break
      end
      local key = type(k) == "string" and k or "[" .. tostring(k) .. "]"
      table.insert(parts, key .. "=" .. format_value(v, depth + 1))
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  else
    return "<" .. t .. ">"
  end
end

---Format a log entry
---@param level_num number Log level number
---@param filename string Source filename
---@param line number Source line number
---@param message string Log message
---@param payload any|nil Optional payload to inspect
---@return string
local function format_entry(level_num, filename, line, message, payload)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local level_name = LEVEL_NAMES[level_num] or "UNKNOWN"
  local location = string.format("%s:%d", filename, line)

  local entry = string.format("[%s] [%s] [%s] %s", timestamp, level_name, location, message)

  if payload ~= nil then
    local ok, formatted = pcall(format_value, payload)
    if ok then
      entry = entry .. " " .. formatted
    else
      entry = entry .. " <format failed>"
    end
  end

  return entry
end

---Write a log entry to file
---@param self neolog.Logger
---@param entry string The formatted log entry
local function write_to_file(self, entry)
  local file_path = get_log_file(self)

  -- Ensure parent directory exists
  local dir = vim.fn.fnamemodify(file_path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  -- Append to log file
  local file = io.open(file_path, "a")
  if file then
    file:write(entry .. "\n")
    file:close()
  end
end

---Check if a level should be logged
---@param self neolog.Logger
---@param level_num number The level to check
---@return boolean
local function should_log(self, level_num)
  local min_level = LEVELS[self.config.level] or LEVELS.info
  return level_num >= min_level
end

---Generic log function
---@param self neolog.Logger
---@param level_num number Log level number
---@param message string Log message
---@param payload any|nil Optional payload
local function log(self, level_num, message, payload)
  if not should_log(self, level_num) then
    return
  end

  local filename, line = get_caller_info(3) -- 3 = caller of log:level()
  local entry = format_entry(level_num, filename, line, message, payload)
  write_to_file(self, entry)
end

---Configure the logger
---@param self neolog.Logger
---@param opts neolog.Config
function Logger:setup(opts)
  opts = opts or {}
  if opts.level then
    self.config.level = opts.level
  end
  if opts.file then
    self.config.file = opts.file
  end
end

---Get the current log file path
---@param self neolog.Logger
---@return string
function Logger:get_log_file()
  return get_log_file(self)
end

---Set the minimum log level
---@param self neolog.Logger
---@param level string One of: trace, debug, info, warn, error, fatal
function Logger:set_level(level)
  if LEVELS[level] then
    self.config.level = level
  else
    error("Invalid log level: " .. tostring(level))
  end
end

---Log a trace message
---@param self neolog.Logger
---@param message string
---@param payload any|nil
function Logger:trace(message, payload)
  log(self, LEVELS.trace, message, payload)
end

---Log a debug message
---@param self neolog.Logger
---@param message string
---@param payload any|nil
function Logger:debug(message, payload)
  log(self, LEVELS.debug, message, payload)
end

---Log an info message
---@param self neolog.Logger
---@param message string
---@param payload any|nil
function Logger:info(message, payload)
  log(self, LEVELS.info, message, payload)
end

---Log a warning message
---@param self neolog.Logger
---@param message string
---@param payload any|nil
function Logger:warn(message, payload)
  log(self, LEVELS.warn, message, payload)
end

---Log an error message
---@param self neolog.Logger
---@param message string
---@param payload any|nil
function Logger:error(message, payload)
  log(self, LEVELS.error, message, payload)
end

---Log a fatal message
---@param self neolog.Logger
---@param message string
---@param payload any|nil
function Logger:fatal(message, payload)
  log(self, LEVELS.fatal, message, payload)
end

-- Cache of loggers by name
local loggers = {}

---Create or get a logger instance
---@param name string Logger name (used for log filename)
---@param opts? neolog.Config Optional configuration
---@return neolog.Logger
function M.new(name, opts)
  if loggers[name] then
    if opts then
      loggers[name]:setup(opts)
    end
    return loggers[name]
  end

  local logger = setmetatable({
    name = name,
    config = {
      level = "info",
      file = nil,
    },
  }, Logger)

  if opts then
    logger:setup(opts)
  end

  loggers[name] = logger
  return logger
end

return M
