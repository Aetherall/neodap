-- Plugin: Integration with VSCode .code-workspace files
-- Allows selecting and launching debug configurations from launch.json
--
-- Provides :DapLaunch command to:
-- - Pick a configuration from launch.json using vim.ui.select
-- - Start debug session(s) with the selected configuration
-- - Handles compounds (launches multiple sessions)

local neostate = require("neostate")

---@class CodeWorkspaceConfig
---@field path? string File path for context (defaults to current buffer)

---@param debugger Debugger
---@param config? CodeWorkspaceConfig
---@return function cleanup
return function(debugger, config)
  config = config or {}

  ---Start debug sessions for the given configurations
  ---@param configs table[] Array of launch configurations
  local function start_sessions(configs)
    if not configs or #configs == 0 then
      vim.notify("No configurations to launch", vim.log.levels.WARN)
      return
    end

    -- Start each config in a coroutine
    for _, launch_config in ipairs(configs) do
      neostate.void(function()
        local ok, err = pcall(function()
          debugger:start(launch_config)
        end)
        if not ok then
          vim.notify("Failed to start " .. (launch_config.name or "session") .. ": " .. tostring(err),
            vim.log.levels.ERROR)
        end
      end)()
    end
  end

  vim.api.nvim_create_user_command("DapLaunch", function(opts)
    local ok, workspace = pcall(require, "code-workspace")
    if not ok then
      vim.notify("code-workspace module not found", vim.log.levels.ERROR)
      return
    end

    -- Determine path context
    local path = config.path
    if opts.args and opts.args ~= "" then
      -- If a name was provided directly, resolve it
      local configs = workspace.resolve_launch_config(opts.args, path)
      if configs then
        start_sessions(configs)
      else
        vim.notify("Configuration not found: " .. opts.args, vim.log.levels.ERROR)
      end
      return
    end

    -- Show picker
    workspace.select_launch_config(path, function(configs)
      if configs then
        start_sessions(configs)
      end
    end)
  end, {
    nargs = "?",
    desc = "Launch debug configuration from code-workspace",
    complete = function(arg_lead, cmd_line, cursor_pos)
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

  -- Cleanup on debugger dispose
  debugger:on_dispose(function()
    pcall(vim.api.nvim_del_user_command, "DapLaunch")
  end)

  -- Return manual cleanup function
  return function()
    pcall(vim.api.nvim_del_user_command, "DapLaunch")
  end
end
