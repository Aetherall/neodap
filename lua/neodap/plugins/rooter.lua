-- Plugin: Integration with rooter.nvim for VS Code launch configurations.
-- Reads launch.json via rooter.launch_configs(), resolves configs/compounds,
-- and starts debug sessions.
--
-- Provides :DapLaunch command to:
-- - Pick a configuration from launch.json using vim.ui.select
-- - Start debug session(s) with the selected configuration
-- - Handles compounds (launches multiple sessions)

---@class RooterPluginConfig
---@field path? string File path for context (defaults to current buffer)

local log = require("neodap.logger")
local E = require("neodap.error")
local entities = require("neodap.entities")
local uri = require("neodap.uri")
local neoword = require("neoword")
local task_runner = require("neodap.task_runner")
local a = require("neodap.async")

---Get the next index for a Config with the given name
---@param dbg neodap.entities.Debugger
---@param name string
---@return number
local function get_next_config_index(dbg, name)
  local max_index = 0
  for cfg in dbg.configs:filter({
    filters = {{ field = "name", op = "eq", value = name }}
  }):iter() do
    max_index = math.max(max_index, cfg.index:get() or 0)
  end
  return max_index + 1
end

--- Resolve a launch configuration by name from rooter.launch_configs().
--- If the name matches a configuration, returns it directly.
--- If the name matches a compound, resolves all referenced configurations.
---@param name string Configuration or compound name
---@param path? string File path for context
---@return table[]|nil configs Array of resolved configurations
---@return table|nil compound_meta Compound metadata if resolving a compound
local function resolve_launch_config(name, path)
  local rooter = require("rooter")
  local launch = rooter.launch_configs(path)
  if not launch then return nil, nil end

  local by_name = {}
  if launch.configurations then
    for _, cfg in ipairs(launch.configurations) do
      if cfg.name then by_name[cfg.name] = cfg end
    end
  end

  if by_name[name] then
    return { by_name[name] }, nil
  end

  if launch.compounds then
    for _, compound in ipairs(launch.compounds) do
      if compound.name == name then
        local resolved = {}
        for _, ref_name in ipairs(compound.configurations or {}) do
          if by_name[ref_name] then
            resolved[#resolved + 1] = by_name[ref_name]
          end
        end
        if #resolved > 0 then
          return resolved, {
            name = compound.name,
            preLaunchTask = compound.preLaunchTask,
            postDebugTask = compound.postDebugTask,
            stopAll = compound.stopAll,
          }
        end
      end
    end
  end

  return nil, nil
end

--- Show a picker for launch configurations and compounds via vim.ui.select.
---@param path? string File path for context
---@param callback fun(configs: table[]|nil, compound_meta: table|nil)
local function select_launch_config(path, callback)
  local rooter = require("rooter")
  local launch = rooter.launch_configs(path)
  if not launch then
    vim.notify("No launch configurations found", vim.log.levels.WARN)
    callback(nil, nil)
    return
  end

  local items = {}
  local groups, group_order = {}, {}

  local function add_item(folder, item)
    folder = folder or "other"
    if not groups[folder] then
      groups[folder] = {}
      group_order[#group_order + 1] = folder
    end
    groups[folder][#groups[folder] + 1] = item
  end

  if launch.configurations then
    for _, cfg in ipairs(launch.configurations) do
      if cfg.name then
        add_item(cfg.__folder, { name = cfg.name, kind = "config", folder = cfg.__folder })
      end
    end
  end
  if launch.compounds then
    for _, compound in ipairs(launch.compounds) do
      if compound.name then
        local n = compound.configurations and #compound.configurations or 0
        add_item(compound.__folder, { name = compound.name, kind = "compound", folder = compound.__folder, ref_count = n })
      end
    end
  end

  local has_groups = #group_order > 1
  for _, folder in ipairs(group_order) do
    for _, item in ipairs(groups[folder]) do
      local display = item.name
      if item.kind == "compound" then
        display = string.format("%s [%d configs]", item.name, item.ref_count)
      end
      if has_groups then
        display = string.format("[%s] %s", item.folder, display)
      end
      item.display = display
      items[#items + 1] = item
    end
  end

  if #items == 0 then
    vim.notify("No launch configurations found", vim.log.levels.WARN)
    callback(nil, nil)
    return
  end

  vim.ui.select(items, {
    prompt = "Select launch configuration:",
    format_item = function(item) return item.display end,
    snacks = {
      filter = {
        transform = function(_, filter)
          filter.pattern = filter.pattern:gsub(":", " ")
        end,
      },
      transform = function(item)
        item.text = item.text:gsub(":", " ")
      end,
    },
  }, function(selected)
    if not selected then
      callback(nil, nil)
      return
    end
    local configs, compound_meta = resolve_launch_config(selected.name, path)
    callback(configs, compound_meta)
  end)
end

---@param debugger neodap.entities.Debugger
---@param config? RooterPluginConfig
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
      superseded = false,
      isCompound = is_compound,
      stopAll = compound_meta and compound_meta.stopAll or false,
      postDebugTask = compound_meta and compound_meta.postDebugTask or nil,
      specifications = configs,  -- Store for restart capability
    })
    debugger.configs:link(config_entity)
    log:info("Created Config #" .. config_index .. ": " .. config_name)

    -- Mark older terminated Configs with the same name as superseded
    for cfg in debugger.configs:filter({
      filters = {{ field = "name", op = "eq", value = config_name }}
    }):iter() do
      if cfg._id ~= config_entity._id and cfg.state:get() == "terminated" then
        cfg:update({ superseded = true })
      end
    end

    -- Run compound-level postDebugTask when Config terminates
    if compound_meta and compound_meta.postDebugTask then
      local task_name = compound_meta.postDebugTask
      config_entity.state:use(function(state)
        if state == "terminated" then
          log:info("Running compound postDebugTask: " .. task_name)
          a.run(function()
            task_runner.run(task_name)
          end)
          return true -- Unsubscribe
        end
      end)
    end

    -- Helper to launch all configs
    local function launch_all()
      -- For compounds with server adapters, use the compound supervisor
      -- so all configs live under one process group (visible in pstree).
      if is_compound then
        local neodap_mod = require("neodap")
        local supervisor = require("neodap.supervisor")
        local session_mod = require("neodap.session")

        -- Resolve adapters and build compound config specs
        local compound_specs = {}
        local adapter_map = {} -- name -> resolved adapter
        for _, launch_config in ipairs(configs) do
          local type_name = launch_config.type
          local adapter_cfg = type_name and neodap_mod.config.adapters[type_name]
          if adapter_cfg then
            if type(adapter_cfg) == "function" then
              adapter_cfg = adapter_cfg(launch_config)
            end
            if adapter_cfg.on_config then
              launch_config = adapter_cfg.on_config(launch_config) or launch_config
            end
          end

          if adapter_cfg and adapter_cfg.type == "server" and adapter_cfg.command then
            table.insert(compound_specs, {
              name = launch_config.name or launch_config.type or "debug",
              command = adapter_cfg.command,
              args = adapter_cfg.args,
              connect_condition = adapter_cfg.connect_condition,
            })
            adapter_map[launch_config.name or launch_config.type or "debug"] = {
              adapter = adapter_cfg,
              config = launch_config,
            }
          else
            -- Non-server adapter: launch directly (won't be under compound shim)
            local ok, err = pcall(function()
              debugger:debug({ config = launch_config, config_entity = config_entity })
            end)
            if not ok then
              log:error("Failed to start session", { name = launch_config.name, error = tostring(err) })
              E.report(E.user("Failed to start '" .. (launch_config.name or "?") .. "': " .. tostring(err)))
            end
          end
        end

        if #compound_specs > 0 then
          local compound_handle
          compound_handle = supervisor.launch_compound({
            name = config_name,
            configs = compound_specs,
          }, function(cfg_name, sup_handle, port, host)
            local entry = adapter_map[cfg_name]
            if not entry then return end

            host = host or entry.adapter.host or "127.0.0.1"
            log:info("Compound config ready", { name = cfg_name, port = port, host = host, pid = sup_handle.pid })

            local tcp_handle = session_mod.connect_tcp({
              host = host,
              port = port,
              retries = 5,
              retry_delay = 100,
            })

            tcp_handle.on_exit(function()
              sup_handle.disconnect()
            end)

            local ok, err = pcall(function()
              debugger:debug({
                config = entry.config,
                config_entity = config_entity,
                process_handle = tcp_handle,
                child_adapter = { type = "tcp", host = host, port = port },
                _supervisor_handle = compound_handle,
              })
            end)
            if not ok then
              log:error("Failed to start session", { name = cfg_name, error = tostring(err) })
              E.report(E.user("Failed to start '" .. cfg_name .. "': " .. tostring(err)))
            end
          end, function(cfg_name, err)
            log:error("Config failed", { name = cfg_name, error = err })
            E.report(E.user("Debug config '" .. cfg_name .. "' failed: " .. tostring(err)))
          end)

          config_entity._compound_handle = compound_handle
        end

        return
      end

      -- Single config launch (or non-compound)
      for _, launch_config in ipairs(configs) do
        local ok, err = pcall(function()
          debugger:debug({ config = launch_config, config_entity = config_entity })
        end)
        if not ok then
          log:error("Failed to start session", { name = launch_config.name, error = tostring(err) })
          E.report(E.user("Failed to start '" .. (launch_config.name or "?") .. "': " .. tostring(err)))
        end
      end
    end

    -- Run compound-level preLaunchTask if present
    if compound_meta and compound_meta.preLaunchTask then
      local task_name = compound_meta.preLaunchTask
      local success = task_runner.run(task_name)
      if not success then
        local msg = "preLaunchTask '" .. task_name .. "' failed"
        log:warn(msg)
        E.report(E.warn(msg))
        local choice = a.wait(function(cb)
          vim.ui.select({ "Launch anyway", "Cancel" }, {
            prompt = msg .. " — launch debug sessions anyway?",
          }, function(selection)
            cb(nil, selection)
          end)
        end, "preLaunchTask:dialog")
        if choice ~= "Launch anyway" then
          log:info("Debug launch cancelled by user")
          return
        end
      else
        log:info("preLaunchTask completed: " .. task_name)
      end
    end

    launch_all()
  end
  api.start_sessions = a.fn(api.start_sessions)

  ---Launch a configuration by name
  ---@param name string Configuration or compound name
  ---@param path? string File path for context
  ---@return boolean success
  function api.launch(name, path)
    local configs, compound_meta = resolve_launch_config(name, path or config.path)
    if configs then
      api.start_sessions(configs, compound_meta)
      return true
    else
      error(E.user("Configuration not found: '" .. name .. "'"), 0)
    end
  end

  ---Show picker and launch selected configuration
  ---@param path? string File path for context
  function api.select_and_launch(path)
    select_launch_config(path or config.path, function(configs, compound_meta)
      if configs then
        api.start_sessions(configs, compound_meta)
      end
    end)
  end

  -- Create user command
  E.create_command("DapLaunch", function(opts)
    if opts.args and opts.args ~= "" then
      api.launch(opts.args, config.path)
    else
      api.select_and_launch(config.path)
    end
  end, {
    nargs = "?",
    desc = "Launch debug configuration from launch.json",
    complete = function(arg_lead)
      local ok, rooter = pcall(require, "rooter")
      if not ok then return {} end

      local launch = rooter.launch_configs(config.path)
      if not launch then return {} end

      local completions = {}
      if launch.configurations then
        for _, cfg in ipairs(launch.configurations) do
          if cfg.name and cfg.name:lower():find(arg_lead:lower(), 1, true) then
            completions[#completions + 1] = cfg.name
          end
        end
      end
      if launch.compounds then
        for _, compound in ipairs(launch.compounds) do
          if compound.name and compound.name:lower():find(arg_lead:lower(), 1, true) then
            completions[#completions + 1] = compound.name
          end
        end
      end
      return completions
    end,
  })

  local function cleanup()
    pcall(vim.api.nvim_del_user_command, "DapLaunch")
  end

  api.cleanup = cleanup
  return api
end
