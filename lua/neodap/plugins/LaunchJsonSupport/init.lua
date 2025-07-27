-- lua/neodap/plugins/LaunchJsonSupport/init.lua
local BasePlugin = require("neodap.plugins.BasePlugin")
local Session = require("neodap.session.session")
local ExecutableTCPAdapter = require("neodap.adapter.executable_tcp")
local NvimAsync = require("neodap.tools.async")

---@class WorkspaceFolder
---@field name string
---@field path string
---@field absolutePath string

---@class WorkspaceInfo
---@field type "single" | "multi-root"
---@field rootPath string
---@field folders WorkspaceFolder[]
---@field workspaceFile string?

---@class NamespacedConfiguration
---@field name string
---@field originalName string
---@field folder WorkspaceFolder?
---@field config table
---@field source "folder" | "workspace"

---@class LaunchJsonSupportPlugin
---@field detectWorkspace fun(path?: string): WorkspaceInfo
---@field findClosestLaunchJson fun(path: string): string?
---@field loadAllConfigurations fun(workspaceInfo?: WorkspaceInfo): table<string, NamespacedConfiguration>
---@field createSessionFromConfig fun(config_name: string, manager: Manager, workspaceInfo?: WorkspaceInfo): Session
---@field createCompoundSessions fun(compound_name: string, manager: Manager, workspaceInfo?: WorkspaceInfo): Session[]
---@field getAvailableConfigurations fun(workspaceInfo?: WorkspaceInfo): string[]
---@field substituteVariables fun(config: table, context: table): table

---@class LaunchJsonSupport: BasePlugin
---@field cached_workspace_info WorkspaceInfo?
---@field cached_configurations table<string, NamespacedConfiguration>?
local LaunchJsonSupport = BasePlugin:extend()

LaunchJsonSupport.name = "LaunchJsonSupport"
LaunchJsonSupport.description = "VS Code launch.json configuration support with multi-root workspace support"

function LaunchJsonSupport.plugin(api)
  return BasePlugin.createPlugin(api, LaunchJsonSupport, {
    cached_workspace_info = nil,
    cached_configurations = nil,
  })
end

function LaunchJsonSupport:setupCommands()
  self:registerCommands()
end

---Detect workspace type and structure
---@param path string?
---@return WorkspaceInfo
function LaunchJsonSupport:detectWorkspace(path)
  path = path or vim.fn.getcwd()

  -- First, try to find the closest launch.json file for better workspace detection
  local closest_launch_json = self:findClosestLaunchJson(path)

  -- Check for .code-workspace file in current directory or parent directories
  local workspace_file = self:findWorkspaceFile(path)

  if workspace_file then
    return self:parseMultiRootWorkspace(workspace_file)
  elseif closest_launch_json then
    -- Create workspace based on closest launch.json location
    local workspace_root = vim.fn.fnamemodify(closest_launch_json, ":h:h") -- Remove /.vscode/launch.json
    return {
      type = "single",
      rootPath = workspace_root,
      folders = { {
        name = vim.fn.fnamemodify(workspace_root, ":t"),
        path = ".",
        absolutePath = workspace_root
      } },
      workspaceFile = nil
    }
  else
    -- Fallback: Single-folder workspace from given path
    return {
      type = "single",
      rootPath = path,
      folders = { {
        name = vim.fn.fnamemodify(path, ":t"),
        path = ".",
        absolutePath = path
      } },
      workspaceFile = nil
    }
  end
end

---Find the closest launch.json file by traversing up the directory tree
---@param start_path string
---@return string?
function LaunchJsonSupport:findClosestLaunchJson(start_path)
  -- If start_path is a file, get its directory
  local current = start_path
  if vim.fn.isdirectory(start_path) == 0 then
    current = vim.fn.fnamemodify(start_path, ":h")
  end

  -- Traverse up the directory tree looking for .vscode/launch.json
  while current ~= "/" and current ~= "" and current ~= "." do
    local launch_json_path = current .. "/.vscode/launch.json"
    if vim.fn.filereadable(launch_json_path) == 1 then
      self.logger:debug("Found closest launch.json at:", launch_json_path)
      return launch_json_path
    end
    local parent = vim.fn.fnamemodify(current, ":h")
    -- Prevent infinite loop if we can't go up anymore
    if parent == current then
      break
    end
    current = parent
  end

  self.logger:debug("No launch.json found for path:", start_path)
  return nil
end

---Find .code-workspace file in current or parent directories
---@param start_path string
---@return string?
function LaunchJsonSupport:findWorkspaceFile(start_path)
  local current = start_path
  while current ~= "/" and current ~= "" do
    local workspace_files = vim.fn.glob(current .. "/*.code-workspace", false, true)
    if #workspace_files > 0 then
      return workspace_files[1]
    end
    current = vim.fn.fnamemodify(current, ":h")
  end
  return nil
end

---Parse multi-root workspace file
---@param workspace_file string
---@return WorkspaceInfo
function LaunchJsonSupport:parseMultiRootWorkspace(workspace_file)
  local content = vim.fn.readfile(workspace_file)
  local json_string = table.concat(content, "\n")

  -- Handle JSON5 comments
  json_string = json_string:gsub("//.-\n", "\n")
  json_string = json_string:gsub("/%*.--%*/", "")

  local ok, parsed = pcall(vim.json.decode, json_string)
  if not ok then
    self.logger:error("Failed to parse workspace file:", workspace_file, parsed)
    error("Failed to parse workspace file: " .. workspace_file)
  end

  local workspace_dir = vim.fn.fnamemodify(workspace_file, ":h")
  local folders = {}

  for _, folder_config in ipairs(parsed.folders or {}) do
    local folder_path = folder_config.path
    local absolute_path = folder_path

    -- Resolve relative paths
    if not vim.fn.fnamemodify(folder_path, ":p"):match("^/") then
      absolute_path = vim.fn.fnamemodify(workspace_dir .. "/" .. folder_path, ":p")
    end

    table.insert(folders, {
      name = folder_config.name or vim.fn.fnamemodify(absolute_path, ":t"),
      path = folder_path,
      absolutePath = absolute_path
    })
  end

  return {
    type = "multi-root",
    rootPath = workspace_dir,
    folders = folders,
    workspaceFile = workspace_file,
    workspaceConfig = parsed
  }
end

---Load configurations from all workspace folders
---@param workspaceInfo WorkspaceInfo?
---@return table<string, NamespacedConfiguration>
function LaunchJsonSupport:loadAllConfigurations(workspaceInfo)
  workspaceInfo = workspaceInfo or self:detectWorkspace()

  -- Return cached configurations if workspace hasn't changed
  if self.cached_workspace_info and
      self.cached_workspace_info.rootPath == workspaceInfo.rootPath and
      self.cached_configurations then
    return self.cached_configurations
  end

  local all_configs = {}

  -- Load folder-level configurations
  for _, folder in ipairs(workspaceInfo.folders) do
    local folder_configs = self:loadFolderConfigurations(folder)
    for config_name, config in pairs(folder_configs) do
      all_configs[config_name] = config
    end
  end

  -- Load workspace-level configurations
  if workspaceInfo.type == "multi-root" and workspaceInfo.workspaceConfig then
    local workspace_configs = self:loadWorkspaceConfigurations(workspaceInfo)
    for config_name, config in pairs(workspace_configs) do
      all_configs[config_name] = config
    end
  end

  -- Cache the results
  self.cached_workspace_info = workspaceInfo
  self.cached_configurations = all_configs

  return all_configs
end

---Load configurations from a single folder
---@param folder WorkspaceFolder
---@return table<string, NamespacedConfiguration>
function LaunchJsonSupport:loadFolderConfigurations(folder)
  local launch_json_path = folder.absolutePath .. "/.vscode/launch.json"

  if not vim.fn.filereadable(launch_json_path) then
    return {}
  end

  local content = vim.fn.readfile(launch_json_path)
  local json_string = table.concat(content, "\n")

  -- Handle JSON5 comments
  json_string = json_string:gsub("//.-\n", "\n")
  json_string = json_string:gsub("/%*.--%*/", "")

  local ok, parsed = pcall(vim.json.decode, json_string)
  if not ok then
    self.logger:error("Failed to parse launch.json:", launch_json_path, parsed)
    return {}
  end

  local configs = {}

  -- Process regular configurations
  for _, config in ipairs(parsed.configurations or {}) do
    local namespaced_name = self:namespaceConfigName(config.name, folder)
    configs[namespaced_name] = {
      name = namespaced_name,
      originalName = config.name,
      folder = folder,
      config = config,
      source = "folder"
    }
  end

  -- Process compound configurations
  for _, compound in ipairs(parsed.compounds or {}) do
    local namespaced_name = self:namespaceConfigName(compound.name, folder, true)
    configs[namespaced_name] = {
      name = namespaced_name,
      originalName = compound.name,
      folder = folder,
      config = compound,
      source = "folder"
    }
  end

  return configs
end

---Load workspace-level configurations
---@param workspaceInfo WorkspaceInfo
---@return table<string, NamespacedConfiguration>
function LaunchJsonSupport:loadWorkspaceConfigurations(workspaceInfo)
  local launch_config = workspaceInfo.workspaceConfig.launch
  if not launch_config then
    return {}
  end

  local configs = {}

  -- Process regular configurations
  for _, config in ipairs(launch_config.configurations or {}) do
    local namespaced_name = self:namespaceConfigName(config.name, nil, false, "workspace")
    configs[namespaced_name] = {
      name = namespaced_name,
      originalName = config.name,
      folder = nil,
      config = config,
      source = "workspace"
    }
  end

  -- Process compound configurations
  for _, compound in ipairs(launch_config.compounds or {}) do
    local namespaced_name = self:namespaceConfigName(compound.name, nil, true, "workspace")
    configs[namespaced_name] = {
      name = namespaced_name,
      originalName = compound.name,
      folder = nil,
      config = compound,
      source = "workspace"
    }
  end

  return configs
end

---Create namespaced configuration name
---@param name string
---@param folder WorkspaceFolder?
---@param is_compound boolean?
---@param source_type string?
---@return string
function LaunchJsonSupport:namespaceConfigName(name, folder, is_compound, source_type)
  local suffix = is_compound and " (compound)" or ""

  if folder then
    return string.format("%s [%s]%s", name, folder.name, suffix)
  elseif source_type == "workspace" then
    return string.format("%s [workspace]%s", name, suffix)
  else
    return name .. suffix
  end
end

---Enhanced variable substitution with workspace scoping
---@param config table
---@param context table
---@return table
function LaunchJsonSupport:substituteVariables(config, context)
  local workspaceInfo = context.workspaceInfo or self:detectWorkspace()
  local currentFolder = context.folder

  -- Build variable map
  local vars = {
    file = vim.fn.expand("%:p"),
    relativeFile = vim.fn.expand("%:."),
    fileBasename = vim.fn.expand("%:t"),
    fileBasenameNoExtension = vim.fn.expand("%:t:r"),
    fileDirname = vim.fn.expand("%:p:h"),
    fileExtname = vim.fn.expand("%:e"),
    cwd = workspaceInfo.rootPath or vim.fn.getcwd(),
  }

  -- Add workspace-specific variables
  if workspaceInfo.type == "single" then
    vars.workspaceFolder = workspaceInfo.rootPath
    vars.workspaceFolderBasename = vim.fn.fnamemodify(workspaceInfo.rootPath, ":t")
  else
    -- Multi-root workspace
    vars.workspaceFolder = workspaceInfo.rootPath
    vars.workspaceFolderBasename = vim.fn.fnamemodify(workspaceInfo.rootPath, ":t")

    -- Add scoped workspace folder variables
    for _, folder in ipairs(workspaceInfo.folders) do
      vars["workspaceFolder:" .. folder.name] = folder.absolutePath
    end

    -- If we have a current folder context, set default workspaceFolder
    if currentFolder then
      vars.workspaceFolder = currentFolder.absolutePath
      vars.workspaceFolderBasename = currentFolder.name
    end
  end

  -- Add custom context variables
  for k, v in pairs(context.vars or {}) do
    vars[k] = v
  end

  -- Recursively substitute variables
  local function substitute_recursive(obj)
    if type(obj) == "string" then
      -- Handle scoped variables first (${workspaceFolder:FolderName})
      obj = obj:gsub("%${([%w_]+):([%w_%-]+)}", function(var, scope)
        local scoped_var = var .. ":" .. scope
        return vars[scoped_var] or ("${" .. var .. ":" .. scope .. "}")
      end)

      -- Handle regular variables
      obj = obj:gsub("%${([%w_]+)}", function(var)
        return vars[var] or ("${" .. var .. "}")
      end)

      return obj
    elseif type(obj) == "table" then
      local result = {}
      for k, v in pairs(obj) do
        result[k] = substitute_recursive(v)
      end
      return result
    else
      return obj
    end
  end

  return substitute_recursive(config)
end

---Create adapter from launch.json configuration
---@param config table
---@param folder WorkspaceFolder?
---@return ExecutableTCPAdapter
function LaunchJsonSupport:createAdapterFromConfig(config, folder)
  local adapter_configs = {
    ["pwa-node"] = {
      cmd = "js-debug",
      cwd = folder and folder.absolutePath or vim.fn.getcwd(),
    },
    ["node"] = {
      cmd = "node-debug2",
      cwd = folder and folder.absolutePath or vim.fn.getcwd(),
    },
    ["python"] = {
      cmd = "debugpy-adapter",
      cwd = folder and folder.absolutePath or vim.fn.getcwd(),
    },
    ["chrome"] = {
      cmd = "vscode-chrome-debug",
      cwd = folder and folder.absolutePath or vim.fn.getcwd(),
    },
    -- Add more adapter mappings as needed
  }

  local adapter_config = adapter_configs[config.type]
  if not adapter_config then
    error("Unsupported adapter type: " .. tostring(config.type))
  end

  return ExecutableTCPAdapter.create({
    executable = adapter_config,
    connection = { host = "::1" }
  })
end

---Transform launch.json config to neodap session config
---@param config table
---@return table
function LaunchJsonSupport:transformConfiguration(config)
  local transformed = vim.deepcopy(config)

  -- Keep type and request fields as they are required by DAP protocol
  -- Only remove VS Code specific fields that are not part of DAP standard

  return transformed
end

---Create session from namespaced configuration
---@param config_name string
---@param manager Manager
---@param workspaceInfo WorkspaceInfo?
---@return Session
function LaunchJsonSupport:createSessionFromConfig(config_name, manager, workspaceInfo)
  local all_configs = self:loadAllConfigurations(workspaceInfo)
  local namespaced_config = all_configs[config_name]

  if not namespaced_config then
    --- Look if first word matches any configuration name
    for namespaced_name, config in pairs(all_configs) do
      if namespaced_name:match("^" .. vim.pesc(config_name) .. "%s") then
        namespaced_config = config
        break
      end
    end
  end

  if not namespaced_config then
    error("Configuration not found: " .. config_name)
  end

  local config = namespaced_config.config

  -- Skip compound configurations
  if config.configurations then
    error("Use createCompoundSessions for compound configurations")
  end

  -- Substitute variables with proper context
  local context = {
    workspaceInfo = workspaceInfo or self:detectWorkspace(),
    folder = namespaced_config.folder,
    vars = {}
  }
  config = self:substituteVariables(config, context)

  -- Create adapter
  local adapter = self:createAdapterFromConfig(config, namespaced_config.folder)

  -- Create session
  local session = Session.create({
    manager = manager,
    adapter = adapter,
  })

  -- Start session
  session:start({
    configuration = self:transformConfiguration(config),
    request = config.request or "launch",
  })

  self.logger:info("Created session from configuration:", config_name)
  return session
end

---Create multiple sessions from compound configuration
---@param compound_name string
---@param manager Manager
---@param workspaceInfo WorkspaceInfo?
---@return Session[]
function LaunchJsonSupport:createCompoundSessions(compound_name, manager, workspaceInfo)
  local all_configs = self:loadAllConfigurations(workspaceInfo)
  local namespaced_config = all_configs[compound_name]

  if not namespaced_config then
    error("Compound configuration not found: " .. compound_name)
  end

  local compound = namespaced_config.config

  if not compound.configurations then
    error("Not a compound configuration: " .. compound_name)
  end

  local sessions = {}

  for _, config_name in ipairs(compound.configurations) do
    -- Handle cross-folder references
    local resolved_config_name = self:resolveConfigurationReference(config_name, namespaced_config, all_configs)

    if resolved_config_name then
      local session = self:createSessionFromConfig(resolved_config_name, manager, workspaceInfo)
      table.insert(sessions, session)
    else
      self.logger:warn("Could not resolve configuration reference:", config_name)
    end
  end

  self.logger:info("Created compound sessions for:", compound_name, "(" .. #sessions .. " sessions)")
  return sessions
end

---Resolve configuration reference in compound (handles cross-folder references)
---@param config_name string
---@param compound_config NamespacedConfiguration
---@param all_configs table<string, NamespacedConfiguration>
---@return string?
function LaunchJsonSupport:resolveConfigurationReference(config_name, compound_config, all_configs)
  -- Direct match (exact namespaced name)
  if all_configs[config_name] then
    return config_name
  end

  -- Search for matching configuration by original name
  for namespaced_name, config in pairs(all_configs) do
    if config.originalName == config_name then
      -- If compound is from same folder, prioritize same folder configs
      if compound_config.folder and config.folder and
          compound_config.folder.name == config.folder.name then
        return namespaced_name
      end

      -- Otherwise, return first match
      if not compound_config.folder or not config.folder then
        return namespaced_name
      end
    end
  end

  return nil
end

---Get available configuration names
---@param workspaceInfo WorkspaceInfo?
---@return string[]
function LaunchJsonSupport:getAvailableConfigurations(workspaceInfo)
  local all_configs = self:loadAllConfigurations(workspaceInfo)
  local names = {}

  for name, _ in pairs(all_configs) do
    table.insert(names, name)
  end

  table.sort(names)
  return names
end

---Register user commands
function LaunchJsonSupport:setupCommands()
  -- Main launch command
  vim.api.nvim_create_user_command("NeodapLaunchJson", function(opts)
    local config_name = opts.args
    local workspaceInfo = self:detectWorkspace()

    if config_name == "" then
      -- Show picker
      local configs = self:getAvailableConfigurations(workspaceInfo)
      if #configs == 0 then
        vim.notify("No launch configurations found", vim.log.levels.WARN)
        return
      end

      vim.ui.select(configs, {
        prompt = "Select launch configuration:",
        format_item = function(item)
          return item
        end,
      }, function(choice)
        if choice then
          if choice:match("%(compound%)") then
            self:createCompoundSessions(choice, self.api.manager, workspaceInfo)
          else
            self:createSessionFromConfig(choice, self.api.manager, workspaceInfo)
          end
        end
      end)
    else
      -- Direct configuration name
      if config_name:match("%(compound%)") then
        self:createCompoundSessions(config_name, self.api.manager, workspaceInfo)
      else
        self:createSessionFromConfig(config_name, self.api.manager, workspaceInfo)
      end
    end
  end, {
    nargs = "?",
    complete = function()
      return self:getAvailableConfigurations()
    end,
    desc = "Start debugging session from launch.json configuration"
  })

  -- Workspace info command
  vim.api.nvim_create_user_command("NeodapWorkspaceInfo", function()
    local workspaceInfo = self:detectWorkspace()
    local info = {
      "=== Workspace Information ===",
      "Type: " .. workspaceInfo.type,
      "Root Path: " .. workspaceInfo.rootPath,
      "",
      "Folders:"
    }

    for _, folder in ipairs(workspaceInfo.folders) do
      table.insert(info, string.format("  - %s: %s", folder.name, folder.absolutePath))
    end

    if workspaceInfo.workspaceFile then
      table.insert(info, "")
      table.insert(info, "Workspace File: " .. workspaceInfo.workspaceFile)
    end

    local configs = self:getAvailableConfigurations(workspaceInfo)
    table.insert(info, "")
    table.insert(info, "Available Configurations: " .. #configs)
    for _, config in ipairs(configs) do
      table.insert(info, "  - " .. config)
    end

    vim.api.nvim_echo({ { table.concat(info, "\n"), "Normal" } }, true, {})
  end, { desc = "Show workspace and configuration information" })

  -- Closest launch.json command - uses current buffer's path
  vim.api.nvim_create_user_command("NeodapLaunchClosest", function(opts)
    local config_name = opts.args
    local current_file = vim.api.nvim_buf_get_name(0)

    if current_file == "" then
      vim.notify("No file in current buffer", vim.log.levels.WARN)
      return
    end

    -- Detect workspace from current buffer's path
    local workspaceInfo = self:detectWorkspace(current_file)

    if config_name == "" then
      -- Show picker for configurations in closest workspace
      local configs = self:getAvailableConfigurations(workspaceInfo)
      if #configs == 0 then
        vim.notify("No launch configurations found for current buffer's workspace", vim.log.levels.WARN)
        return
      end

      vim.ui.select(configs, {
        prompt = "Select configuration from closest workspace:",
        format_item = function(item)
          return item
        end,
      }, function(choice)
        if choice then
          local session = self:createSessionFromConfig(choice, self.api.manager, workspaceInfo)
          self.logger:info("Created session from closest configuration:", choice)
        end
      end)
    else
      -- Run specified configuration
      NvimAsync.run(function()
        local session = self:createSessionFromConfig(config_name, self.api.manager, workspaceInfo)
        self.logger:info("Created session from closest configuration:", config_name)
      end)
    end
  end, {
    nargs = "?",
    complete = function()
      local current_file = vim.api.nvim_buf_get_name(0)
      if current_file == "" then
        return {}
      end
      local workspaceInfo = self:detectWorkspace(current_file)
      return self:getAvailableConfigurations(workspaceInfo)
    end,
    desc = "Start debugging session from closest launch.json to current buffer"
  })

  -- Reload configurations command
  vim.api.nvim_create_user_command("NeodapReloadConfigs", function()
    self.cached_workspace_info = nil
    self.cached_configurations = nil

    local workspaceInfo = self:detectWorkspace()
    local configs = self:getAvailableConfigurations(workspaceInfo)

    vim.notify(string.format("Reloaded %d launch configurations", #configs), vim.log.levels.INFO)
  end, { desc = "Reload launch.json configurations" })
end

return LaunchJsonSupport
