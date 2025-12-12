-- Task integration plugin for neodap
--
-- Handles per-config preLaunchTask and postDebugTask using lifecycle hooks
-- and the task_runner abstraction. Loaded by default in boost.lua.
--
-- With noop runner (default): tasks are skipped, debug proceeds normally.
-- With overseer adapter: tasks execute via overseer before/after debug sessions.
--
-- This replaces the monkey-patching approach used by the old overseer plugin.

local task_runner = require("neodap.task_runner")
local a = require("neodap.async")
local log = require("neodap.logger")

---@param debugger neodap.entities.Debugger
---@param config? table
return function(debugger, config)
  -- before_debug: run preLaunchTask before session starts
  debugger:hook("before_debug", function(opts)
    local launch_config = opts.config
    if not launch_config or not launch_config.preLaunchTask then
      return -- proceed
    end

    local task_name = launch_config.preLaunchTask
    local success = task_runner.run(task_name, launch_config)
    if not success then
      log:error("preLaunchTask failed, aborting debug", { task = task_name })
      return false -- abort debug
    end
    log:info("preLaunchTask succeeded", { task = task_name })
  end)

  -- on_session: set up postDebugTask listener when session is created
  -- For server adapters (e.g., js-debug), a single debug() call creates
  -- both a root session and child sessions. All share the same opts table.
  -- We attach a watcher to every session but use a "fired" flag (keyed by
  -- opts identity) to ensure the task runs exactly once per debug() call:
  -- whichever session terminates first triggers the task.
  local post_task_fired = {}
  setmetatable(post_task_fired, { __mode = "k" })  -- weak keys for GC

  debugger:hook("on_session", function(session, opts)
    local launch_config = opts.config
    if not launch_config or not launch_config.postDebugTask then
      return
    end

    local task_name = launch_config.postDebugTask
    session.state:use(function(state)
      if state == "terminated" then
        -- Only fire once per debug() invocation
        if post_task_fired[opts] then
          return true -- already fired, just unsubscribe
        end
        post_task_fired[opts] = true

        log:info("Running postDebugTask: " .. task_name)
        a.run(function()
          task_runner.run(task_name, launch_config)
        end)
        return true -- unsubscribe
      end
    end)
  end)

  return {}
end
