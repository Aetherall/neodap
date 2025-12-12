-- Task runner abstraction for neodap
--
-- Provides a pluggable interface for executing VS Code tasks (preLaunchTask,
-- postDebugTask). The default is a noop implementation that skips tasks
-- gracefully. Plugins (like overseer.lua) can register a real implementation.
--
-- Usage:
--   local task_runner = require("neodap.task_runner")
--   task_runner.run("build-all")  -- noop unless a runner is registered
--
--   -- Register a runner (e.g., from overseer plugin):
--   task_runner.register({
--     run = function(name, opts) ... return success end,
--   })

local log = require("neodap.logger")

---@class neodap.TaskRunner
---@field run fun(name: string, opts?: table): boolean

local M = {}

---@type neodap.TaskRunner?
local runner = nil

---Register a task runner implementation.
---@param task_runner neodap.TaskRunner
function M.register(task_runner)
  runner = task_runner
  log:info("Task runner registered", { name = task_runner.name or "custom" })
end

---Unregister the current task runner (mainly for testing).
function M.unregister()
  runner = nil
end

---Run a named task. Returns true on success, false on failure.
---If no runner is registered (noop), logs and returns true (tasks are skipped).
---This function is async-compatible: if the runner's run() uses a.wait(),
---the caller must be in an async context (a.fn or a.run).
---@param name string Task name (label from tasks.json or ${defaultBuildTask})
---@param opts? table Optional context (e.g., the launch config)
---@return boolean success
function M.run(name, opts)
  if not runner then
    log:debug("No task runner configured, skipping task: " .. name)
    return true
  end
  log:info("Running task: " .. name)
  local ok, result = pcall(runner.run, name, opts)
  if not ok then
    log:error("Task runner error", { task = name, error = tostring(result) })
    return false
  end
  return result ~= false
end

---Check if a task runner is registered.
---@return boolean
function M.has_runner()
  return runner ~= nil
end

return M
