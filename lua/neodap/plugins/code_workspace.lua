-- Plugin: Integration with VSCode .code-workspace files
-- Allows selecting and launching debug configurations from launch.json
--
-- Provides :DapLaunch command to:
-- - Pick a configuration from launch.json using vim.ui.select
-- - Start debug session(s) with the selected configuration
-- - Handles compounds (launches multiple sessions)

---@class CodeWorkspaceConfig
---@field path? string File path for context (defaults to current buffer)

---@param debugger neodap.entities.Debugger
---@param config? CodeWorkspaceConfig
---@return table api Plugin API
return function(debugger, config)
  config = config or {}

  local api = {}

  ---Start debug sessions for the given configurations
  ---@param configs table[] Array of launch configurations
  function api.start_sessions(configs)
    if not configs or #configs == 0 then
      vim.notify("No configurations to launch", vim.log.levels.WARN)
      return
    end

    -- Start each config (adapter resolved automatically from config.type)
    for _, launch_config in ipairs(configs) do
      local ok, err = pcall(function()
        debugger:debug({ config = launch_config })
      end)
      if not ok then
        vim.notify("Failed to start " .. (launch_config.name or "session") .. ": " .. tostring(err),
          vim.log.levels.ERROR)
      end
    end
  end

  ---Launch a configuration by name
  ---@param name string Configuration or compound name
  ---@param path? string File path for context
  ---@return boolean success
  function api.launch(name, path)
    local ok, workspace = pcall(require, "code-workspace")
    if not ok then
      vim.notify("code-workspace module not found", vim.log.levels.ERROR)
      return false
    end

    local configs = workspace.resolve_launch_config(name, path or config.path)
    if configs then
      api.start_sessions(configs)
      return true
    else
      vim.notify("Configuration not found: " .. name, vim.log.levels.ERROR)
      return false
    end
  end

  ---Show picker and launch selected configuration
  ---@param path? string File path for context
  function api.select_and_launch(path)
    local ok, workspace = pcall(require, "code-workspace")
    if not ok then
      vim.notify("code-workspace module not found", vim.log.levels.ERROR)
      return
    end

    workspace.select_launch_config(path or config.path, function(configs)
      if configs then
        api.start_sessions(configs)
      end
    end)
  end

  -- Create user command
  vim.api.nvim_create_user_command("DapLaunch", function(opts)
    local ok, workspace = pcall(require, "code-workspace")
    if not ok then
      vim.notify("code-workspace module not found", vim.log.levels.ERROR)
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
