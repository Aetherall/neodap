-- Backend interface for process management
-- Provides spawn, connect, and run_in_terminal for DAP adapter communication.

---@class neodap.ProcessHandle
---@field task_id number|string Unique identifier for the task
---@field write fun(data: string) Write data to process stdin
---@field on_data fun(cb: fun(data: string)) Register callback for stdout data
---@field on_stderr fun(cb: fun(data: string)) Register callback for stderr data
---@field on_exit fun(cb: fun(code: number)) Register callback for process exit
---@field kill fun() Kill the process

---@class neodap.TaskHandle
---@field task_id number|string Unique identifier for the task
---@field on_exit fun(cb: fun(code: number)) Register callback for task completion
---@field kill fun() Kill/cancel the task

---@class neodap.TaskBackend
---@field name string Backend name for identification
---@field spawn fun(opts: neodap.SpawnOpts): neodap.ProcessHandle Spawn a process with stdio
---@field connect fun(host: string, port: number, opts?: neodap.ConnectOpts): neodap.ProcessHandle Connect via TCP
---@field run_in_terminal fun(opts: neodap.RunInTerminalOpts): neodap.TaskHandle Run command in terminal

---@class neodap.SpawnOpts
---@field command string Command to execute
---@field args? string[] Command arguments
---@field cwd? string Working directory
---@field env? table<string, string> Environment variables

---@class neodap.ConnectOpts
---@field retries? number Number of connection retries (default: 5)
---@field retry_delay? number Delay between retries in ms (default: 100)
---@field timeout? number Overall timeout in ms (default: 5000)
---@field on_close? fun() Callback when connection closes

---@class neodap.RunInTerminalOpts
---@field args string[] Command and arguments
---@field cwd? string Working directory
---@field env? table<string, string> Environment variables
---@field kind? "integrated"|"external" Terminal kind hint
---@field title? string Terminal title

local M = {}

local cached_backend = nil

---Get the backend
---@return neodap.TaskBackend
function M.get_backend()
  if not cached_backend then
    cached_backend = require("neodap.backends.builtin")
  end
  return cached_backend
end

---Reset cached backend (for testing)
function M.reset()
  cached_backend = nil
end

return M
