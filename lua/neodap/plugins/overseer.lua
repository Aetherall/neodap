-- Plugin: Overseer Integration
-- Supports preLaunchTask and postDebugTask from VS Code launch configs.
--
-- Usage:
--   debugger:use(require("neodap.plugins.overseer"))
--
-- Then launch configs with preLaunchTask/postDebugTask will automatically
-- run overseer tasks before/after debug sessions.
--
-- Requires: stevearc/overseer.nvim

local a = require("neodap.async")
local entities = require("neodap.entities")
local Debugger = entities.Debugger

---Run an overseer task by name and wait for completion
---@param task_name string Task name or "${defaultBuildTask}"
---@param config table The launch config (passed to task params)
---@return boolean success Whether the task completed successfully
local function run_task(task_name, config)
  local ok, overseer = pcall(require, "overseer")
  if not ok then
    vim.notify("overseer.nvim not found", vim.log.levels.ERROR)
    return false
  end

  local constants = require("overseer.constants")
  local STATUS = constants.STATUS
  local TAG = constants.TAG

  -- Build task search args
  local args = { autostart = false }
  if task_name == "${defaultBuildTask}" then
    args.tags = { TAG.BUILD }
  else
    args.name = task_name
  end

  -- Find and create the task
  local event = a.event()

  overseer.run_task(args, function(task, err)
    if err or not task then
      vim.schedule(function()
        vim.notify(
          string.format("Could not find task '%s': %s", task_name, err or "not found"),
          vim.log.levels.ERROR
        )
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

    task:subscribe("on_complete", function(_, status)
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
  -- Store original debug method
  local original_debug = Debugger.debug

  -- Override debug to support preLaunchTask
  function Debugger:debug(opts)
    local launch_config = opts.config

    -- Run preLaunchTask if present
    if launch_config and launch_config.preLaunchTask then
      local success = run_task(launch_config.preLaunchTask, launch_config)
      if not success then
        vim.notify(
          string.format("preLaunchTask '%s' failed, aborting debug", launch_config.preLaunchTask),
          vim.log.levels.ERROR
        )
        return nil
      end
    end

    -- Call original debug
    local session = original_debug(self, opts)

    -- Set up postDebugTask if present
    if session and launch_config and launch_config.postDebugTask then
      local task_name = launch_config.postDebugTask
      session.state:use(function(state)
        if state == "terminated" then
          a.run(function()
            run_task(task_name, launch_config)
          end)
          return true -- Unsubscribe
        end
      end)
    end

    return session
  end
  Debugger.debug = a.fn(Debugger.debug)

  return {}
end
