-- Plugin: Overseer Task Runner Adapter
--
-- Registers overseer.nvim as the task runner backend for neodap.
-- This enables preLaunchTask and postDebugTask execution via overseer.
--
-- Usage:
--   debugger:use(require("neodap.plugins.overseer"))
--
-- Requires: stevearc/overseer.nvim
--
-- Without this plugin, the default noop task runner skips all tasks.
-- With this plugin, tasks are executed via overseer's task management.

local a = require("neodap.async")
local task_runner = require("neodap.task_runner")
local log = require("neodap.logger")
local E = require("neodap.error")

---Run an overseer task by name and wait for completion.
---This is the core adapter function wrapping overseer's callback API
---into neodap's coroutine-based async.
---@param name string Task name or "${defaultBuildTask}"
---@param opts? table Launch config context (unused by overseer adapter)
---@return boolean success Whether the task completed successfully
local function overseer_run(name, opts)
  local ok, overseer = pcall(require, "overseer")
  if not ok then
    error(E.user("overseer.nvim not found — install it or remove the overseer plugin"), 0)
  end

  local constants = require("overseer.constants")
  local STATUS = constants.STATUS
  local TAG = constants.TAG

  -- Build task search args
  local args = { autostart = false }
  if name == "${defaultBuildTask}" then
    args.tags = { TAG.BUILD }
  else
    args.name = name
  end

  -- Find and create the task
  local event = a.event()

  overseer.run_task(args, function(task, err)
    if err or not task then
      vim.schedule(function()
        log:error("Could not find task", { task = name, error = err or "not found" })
        E.report(E.user("Task not found: '" .. name .. "'"))
      end)
      event:set(false)
      return
    end

    -- Subscribe to completion (use closure to ensure single-fire)
    local on_done
    on_done = function(success)
      on_done = function() end
      event:set(success)
    end

    log:info("Starting task: " .. name)
    task:subscribe("on_complete", function(_, status)
      log:info("Task completed: " .. name)
      on_done(status == STATUS.SUCCESS)
      return true -- Unsubscribe
    end)

    task:subscribe("on_result", function()
      -- Background tasks signal completion via on_result
      on_done(task.status ~= STATUS.FAILURE)
      return true -- Unsubscribe
    end)

    task:start()
  end)

  return a.wait(event.wait, "overseer:run_task")
end

---@param debugger neodap.entities.Debugger
---@param config? table
return function(debugger, config)
  -- Register overseer as the task runner
  task_runner.register({
    name = "overseer",
    run = overseer_run,
  })

  return {}
end
