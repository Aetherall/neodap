-- Plugin: Integration with VSCode .code-workspace files
-- Allows selecting and launching debug configurations from launch.json
--
-- Provides :DapLaunch command to:
-- - Pick a configuration from launch.json using vim.ui.select
-- - Start debug session(s) with the selected configuration
-- - Handles compounds (launches multiple sessions)

---@class CodeWorkspaceConfig
---@field path? string File path for context (defaults to current buffer)

local log = require("neodap.logger")
local entities = require("neodap.entities")
local uri = require("neodap.uri")
local neoword = require("neoword")

---Get the next index for a Config with the given name
---@param dbg neodap.entities.Debugger
---@param name string
---@return number
local function get_next_config_index(dbg, name)
  local max_index = 0
  for cfg in dbg.configs:iter() do
    if cfg.name:get() == name then
      max_index = math.max(max_index, cfg.index:get() or 0)
    end
  end
  return max_index + 1
end

---@param debugger neodap.entities.Debugger
---@param config? CodeWorkspaceConfig
---@return table api Plugin API
return function(debugger, config)
  config = config or {}

  local api = {}

  ---Start debug sessions for the given configurations
  ---@param configs table[] Array of launch configurations
  ---@param compound_meta table|nil Compound metadata (preLaunchTask, postDebugTask, name)
  function api.start_sessions(configs, compound_meta)
    if not configs or #configs == 0 then
      log:warn("No configurations to launch")
      return
    end

    -- Determine Config name (compound name or single config name)
    local config_name = (compound_meta and compound_meta.name) or (configs[1] and configs[1].name) or "Debug"
    local is_compound = compound_meta ~= nil or #configs > 1

    log:info("Starting Config: " .. config_name .. " (" .. #configs .. " configurations)")

    -- Create Config entity
    local config_id = neoword.generate()
    local config_index = get_next_config_index(debugger, config_name)
    local config_entity = entities.Config.new(debugger._graph, {
      uri = uri.config(config_id),
      configId = config_id,
      name = config_name,
      index = config_index,
      state = "active",
      isCompound = is_compound,
      stopAll = compound_meta and compound_meta.stopAll or false,
      postDebugTask = compound_meta and compound_meta.postDebugTask or nil,
      specifications = configs,  -- Store for restart capability
    })
    debugger.configs:link(config_entity)
    log:info("Created Config #" .. config_index .. ": " .. config_name)

    -- Run compound-level postDebugTask when Config terminates
    if compound_meta and compound_meta.postDebugTask then
      local task_name = compound_meta.postDebugTask
      config_entity.state:use(function(state)
        if state == "terminated" then
          local ok, overseer = pcall(require, "overseer")
          if ok then
            log:info("Running compound postDebugTask: " .. task_name)
            overseer.run_task({ name = task_name }, function(task, err)
              if err or not task then
                log:error("Compound postDebugTask failed to start", { task = task_name })
              else
                task:start()
              end
            end)
          else
            log:warn("overseer.nvim required for postDebugTask support")
          end
          return true -- Unsubscribe
        end
      end)
    end

    -- Helper to launch all configs
    local function launch_configs()
      for _, launch_config in ipairs(configs) do
        local ok, err = pcall(function()
          debugger:debug({ config = launch_config, config_entity = config_entity })
        end)
        if not ok then
          log:error("Failed to start session", { name = launch_config.name, error = tostring(err) })
        end
      end
    end

    -- Run compound-level preLaunchTask if present
    if compound_meta and compound_meta.preLaunchTask then
      local ok, overseer = pcall(require, "overseer")
      if ok then
        overseer.run_task({ name = compound_meta.preLaunchTask }, function(task, err)
          if err or not task then
            log:error("Compound preLaunchTask failed to start", { task = compound_meta.preLaunchTask })
            return
          end
          task:subscribe("on_complete", function(_, status)
            if status == "SUCCESS" then
              log:info("preLaunchTask completed: " .. compound_meta.preLaunchTask)
              launch_configs()
            else
              log:error("Compound preLaunchTask failed, aborting debug", { task = compound_meta.preLaunchTask })
            end
          end)
        end)
      else
        log:warn("overseer.nvim required for preLaunchTask support")
        launch_configs()
      end
    else
      launch_configs()
    end
  end

  ---Launch a configuration by name
  ---@param name string Configuration or compound name
  ---@param path? string File path for context
  ---@return boolean success
  function api.launch(name, path)
    local ok, workspace = pcall(require, "code-workspace")
    if not ok then
      log:error("code-workspace module not found")
      return false
    end

    local configs, compound_meta = workspace.resolve_launch_config(name, path or config.path)
    if configs then
      api.start_sessions(configs, compound_meta)
      return true
    else
      log:error("Configuration not found", { name = name })
      return false
    end
  end

  ---Show picker and launch selected configuration
  ---@param path? string File path for context
  function api.select_and_launch(path)
    local ok, workspace = pcall(require, "code-workspace")
    if not ok then
      log:error("code-workspace module not found")
      return
    end

    workspace.select_launch_config(path or config.path, function(configs, compound_meta)
      if configs then
        api.start_sessions(configs, compound_meta)
      end
    end)
  end

  -- Create user command
  vim.api.nvim_create_user_command("DapLaunch", function(opts)
    local ok, workspace = pcall(require, "code-workspace")
    if not ok then
      log:error("code-workspace module not found")
      return
    end

    if opts.args and opts.args ~= "" then
      -- If a name was provided directly, resolve it
      api.launch(opts.args, config.path)
    else
      -- Show picker
      api.select_and_launch(config.path)
    end
  end, {
    nargs = "?",
    desc = "Launch debug configuration from code-workspace",
    complete = function(arg_lead)
      local ok, workspace = pcall(require, "code-workspace")
      if not ok then return {} end

      local launch = workspace.get_launch_config(config.path)
      if not launch then return {} end

      local completions = {}

      -- Add configuration names
      if launch.configurations then
        for _, cfg in ipairs(launch.configurations) do
          if cfg.name and cfg.name:lower():find(arg_lead:lower(), 1, true) then
            table.insert(completions, cfg.name)
          end
        end
      end

      -- Add compound names
      if launch.compounds then
        for _, compound in ipairs(launch.compounds) do
          if compound.name and compound.name:lower():find(arg_lead:lower(), 1, true) then
            table.insert(completions, compound.name)
          end
        end
      end

      return completions
    end,
  })

  -- Return cleanup function
  local function cleanup()
    pcall(vim.api.nvim_del_user_command, "DapLaunch")
  end

  -- Return both API and cleanup
  api.cleanup = cleanup

  return api
end
