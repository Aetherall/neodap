-- Structured error types for neodap
--
-- Provides a NeodapError type with metadata about visibility and severity,
-- plus a centralized E.report() function that handles logging + user notification.
--
-- vim.notify is called in exactly ONE place: inside E.report().
-- All error paths (async handler, command wrapper) delegate to E.report().
--
-- Usage:
--   local E = require("neodap.error")
--
--   -- User-facing errors (shown via vim.notify):
--   error(E.user("No adapter configured for type 'python'"), 0)
--   error(E.warn("No thread found"), 0)
--
--   -- Internal errors (logged only, not shown to user):
--   error(E.internal("cleanup failed"), 0)
--
--   -- Report an error (logging + optional notification):
--   E.report(err)

local log = require("neodap.logger")

local M = {}

-- NeodapError: structured error with visibility metadata
local NeodapError = {}
NeodapError.__index = NeodapError

--- Create a new NeodapError.
---@param opts { message: string, show_user: boolean, level: integer, data: any? }
function NeodapError.new(opts)
  return setmetatable({
    message = opts.message,
    show_user = opts.show_user,
    level = opts.level or vim.log.levels.ERROR,
    data = opts.data,
  }, NeodapError)
end

function NeodapError:__tostring()
  return self.message
end

M.NeodapError = NeodapError

--- Create a user-facing error (shown in vim.notify at ERROR level).
---@param message string
---@param opts? { data: any }
---@return table NeodapError
function M.user(message, opts)
  return NeodapError.new({
    message = message,
    show_user = true,
    level = vim.log.levels.ERROR,
    data = opts and opts.data,
  })
end

--- Create a user-facing warning (shown in vim.notify at WARN level).
---@param message string
---@param opts? { data: any }
---@return table NeodapError
function M.warn(message, opts)
  return NeodapError.new({
    message = message,
    show_user = true,
    level = vim.log.levels.WARN,
    data = opts and opts.data,
  })
end

--- Create an internal error (logged but NOT shown to user).
---@param message string
---@param opts? { data: any }
---@return table NeodapError
function M.internal(message, opts)
  return NeodapError.new({
    message = message,
    show_user = false,
    data = opts and opts.data,
  })
end

--- Check if a value is a NeodapError.
---@param err any
---@return boolean
function M.is(err)
  return type(err) == "table" and getmetatable(err) == NeodapError
end

--- Extract a NeodapError from an error value, unwrapping AsyncError if needed.
--- Returns nil if the error is not (or does not wrap) a NeodapError.
---@param err any
---@return table|nil NeodapError or nil
function M.unwrap(err)
  if M.is(err) then return err end
  -- AsyncError wrapping a NeodapError: AsyncError.message == NeodapError
  if type(err) == "table" and M.is(err.message) then return err.message end
  return nil
end

--- Check if an error represents cancellation.
---@param err any
---@return boolean
local function is_cancelled(err)
  if err == "cancelled" then return true end
  -- AsyncError wrapping "cancelled"
  if type(err) == "table" and err.message == "cancelled" then return true end
  return false
end

--- Extract a clean, user-readable message from an error value.
--- Strips AsyncError wrapper and stack trace, returns just the message.
---@param err any
---@return string
local function clean_message(err)
  local nerr = M.unwrap(err)
  if nerr then return nerr.message end
  -- AsyncError wrapping a plain string
  if type(err) == "table" and type(err.message) == "string" then return err.message end
  return tostring(err)
end

--- Report an error: log it and optionally notify the user.
---
--- This is the SINGLE place where vim.notify is called for error reporting.
--- All error paths (async default_error_handler, protected commands) delegate here.
---
---@param err any The error value (string, NeodapError, AsyncError, or any throwable)
function M.report(err)
  if not err then return end
  if is_cancelled(err) then return end

  local nerr = M.unwrap(err)

  -- Always log with full detail (includes AsyncError stack trace)
  log:error("error", { error = tostring(err) })

  -- Notify user unless explicitly opted out
  if nerr and nerr.show_user == false then return end

  local message = clean_message(err)
  local level = nerr and nerr.level or vim.log.levels.ERROR

  vim.notify("[neodap] " .. message, level)
end

--- Registry of custom complete functions keyed by command name.
--- Populated by E.create_command when opts.complete is a function.
--- Used by command_router to delegate completion for :Dap subcommands.
M._completers = {}

--- Create a Vim user command with automatic error reporting.
--- Wraps the handler in pcall and routes errors to E.report().
--- This ensures ALL command-level errors (validation, entity state, etc.)
--- are surfaced to the user without manual vim.notify calls.
---
---@param name string Command name (e.g., "DapContinue")
---@param handler function Command handler (receives opts table from nvim_create_user_command)
---@param opts table Options for nvim_create_user_command (nargs, desc, complete, bang, etc.)
function M.create_command(name, handler, opts)
  if opts.complete and type(opts.complete) == "function" then
    M._completers[name] = opts.complete
  end
  vim.api.nvim_create_user_command(name, function(cmd_opts)
    local ok, err = pcall(handler, cmd_opts)
    if not ok then M.report(err) end
  end, opts)
end

--- Create a keymap with automatic error reporting.
--- Wraps the handler in pcall and routes errors to E.report().
--- Same pattern as E.create_command but for vim.keymap.set.
---
---@param mode string|string[] Mode(s) for the keymap
---@param lhs string Left-hand side of the keymap
---@param handler function Keymap handler (zero-arg function)
---@param opts? table Options for vim.keymap.set (buffer, desc, nowait, etc.)
function M.keymap(mode, lhs, handler, opts)
  vim.keymap.set(mode, lhs, function()
    local ok, err = pcall(handler)
    if not ok then M.report(err) end
  end, opts)
end

return M
