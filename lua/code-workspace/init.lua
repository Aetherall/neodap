local M = {}

-- Internal state
M._state = {
  workspace = nil,
  workspace_file = nil,
  root_dir = nil,
  folder_settings = nil,
}

-- Load other modules
local parser = require('code-workspace.parser')
local interpolate = require('code-workspace.interpolate')
local lsp = require('code-workspace.lsp')

-- ============================================================================
-- Internal functions
-- ============================================================================

--- Find .code-workspace file starting from given directory
---@param start_dir string Starting directory
---@return string|nil Workspace file path
local function find_workspace_file(start_dir)
  local current = start_dir
  while current ~= '/' do
    local files = vim.fn.globpath(current, '*.code-workspace', false, true)
    if #files > 0 then
      return files[1]
    end
    current = vim.fn.fnamemodify(current, ':h')
  end
  return nil
end

--- Load per-folder settings from .vscode/settings.json in each folder
local function load_folder_settings()
  if not M._state.workspace or not M._state.workspace.folders then
    return
  end

  M._state.folder_settings = {}

  for _, folder in ipairs(M._state.workspace.folders) do
    local folder_path = folder.path
    if not vim.startswith(folder_path, '/') and M._state.root_dir then
      folder_path = M._state.root_dir .. '/' .. folder_path
    end

    local settings_file = folder_path .. '/.vscode/settings.json'
    local folder_settings = parser.parse_json_file(settings_file)

    if folder_settings then
      M._state.folder_settings[folder.name or folder.path] = folder_settings
    end
  end
end

--- Load a workspace file
---@param workspace_file string Path to .code-workspace file
---@return boolean Success
local function load_workspace(workspace_file)
  local workspace_data = parser.parse_workspace_file(workspace_file)

  if not workspace_data then
    vim.notify('Failed to parse workspace file: ' .. workspace_file, vim.log.levels.ERROR)
    return false
  end

  M._state.workspace = workspace_data
  M._state.workspace_file = workspace_file
  M._state.root_dir = vim.fn.fnamemodify(workspace_file, ':h')

  load_folder_settings()

  vim.notify('Loaded workspace: ' .. workspace_file, vim.log.levels.INFO)
  return true
end

--- Find the workspace folder that contains the given path
---@param path string File or directory path
---@return string|nil Absolute path to the containing workspace folder, or nil
local function find_folder_for_path(path)
  if not M._state.workspace or not M._state.workspace.folders then
    return nil
  end

  local abs_path = vim.fn.fnamemodify(path, ':p')

  for _, folder in ipairs(M._state.workspace.folders) do
    local folder_path = folder.path
    if not vim.startswith(folder_path, '/') and M._state.root_dir then
      folder_path = M._state.root_dir .. '/' .. folder_path
    end
    folder_path = vim.fn.resolve(folder_path)

    if vim.startswith(abs_path, folder_path .. '/') or abs_path == folder_path then
      return folder_path
    end
  end

  return nil
end

--- Collect .vscode config file paths for a given path (folder + root)
---@param config_name string Config file name (e.g., 'launch.json', 'tasks.json')
---@param path string|nil File path to determine context (defaults to current buffer)
---@return table List of config file paths to load (folder first, then root)
local function collect_vscode_configs(config_name, path)
  -- Default to current buffer if no path
  if not path then
    path = vim.api.nvim_buf_get_name(0)
  end

  if path == '' then
    path = nil
  end

  local configs_to_load = {}

  -- Find which folder contains this path
  local folder_path = path and find_folder_for_path(path) or nil

  -- Add folder-specific config first (if path is in a folder and not at root)
  if folder_path and folder_path ~= M._state.root_dir then
    table.insert(configs_to_load, folder_path .. '/.vscode/' .. config_name)
  end

  -- Add root config
  if M._state.root_dir then
    table.insert(configs_to_load, M._state.root_dir .. '/.vscode/' .. config_name)
  end

  return configs_to_load
end

--- Load and merge multiple config files
---@param array_keys string|table Single key or list of keys to merge (e.g., 'configurations', 'tasks', 'compounds')
---@param paths table List of config file paths
---@return table|nil Merged configuration or nil if no configs found
local function merge_configs(array_keys, paths)
  -- Normalize to table
  if type(array_keys) == 'string' then
    array_keys = { array_keys }
  end

  local merged = {}
  for _, key in ipairs(array_keys) do
    merged[key] = {}
  end

  for _, config_path in ipairs(paths) do
    local config = parser.parse_json_file(config_path)
    if config then
      config = interpolate.interpolate_config(config, M._state)

      for _, key in ipairs(array_keys) do
        if config[key] then
          for _, item in ipairs(config[key]) do
            table.insert(merged[key], item)
          end
        end
      end

      -- Preserve version from first config found
      if config.version and not merged.version then
        merged.version = config.version
      end
    end
  end

  -- Check if any arrays have content
  local has_content = false
  for _, key in ipairs(array_keys) do
    if #merged[key] > 0 then
      has_content = true
    else
      merged[key] = nil -- Remove empty arrays
    end
  end

  if not has_content then
    return nil
  end

  return merged
end

--- LSP root_dir function with fallback
---@param bufnr integer Buffer number
---@param on_dir function Callback function that receives the root directory
local function lsp_root_dir(bufnr, on_dir)
  local ws_root = M._state.root_dir
  if ws_root then
    on_dir(ws_root)
    return
  end

  -- Fallback to .git or buffer's directory
  local fname = vim.api.nvim_buf_get_name(bufnr)
  local fallback = vim.fs.root(fname, { '.git' })

  if not fallback and fname ~= '' then
    fallback = vim.fn.fnamemodify(fname, ':h')
  end

  if fallback then
    on_dir(fallback)
  end
end

--- Handle workspace/configuration requests from LSP
---@param err table|nil Error
---@param result table Configuration request parameters
---@param ctx table Context with client info
---@return table Configuration items
local function handle_workspace_configuration(err, result, ctx)
  if err then
    return {}
  end

  local items = result.items or {}
  local responses = {}

  for _, item in ipairs(items) do
    local scope_uri = item.scopeUri
    local section = item.section

    -- Determine which folder this request is for
    local folder_name = nil
    if scope_uri and M._state.workspace_folders then
      for _, folder in ipairs(M._state.workspace_folders) do
        if scope_uri == folder.uri or vim.startswith(scope_uri, folder.uri .. '/') then
          folder_name = folder.name
          break
        end
      end
    end

    -- Get settings for this folder (or workspace-level if no folder match)
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    local settings = {}

    if client and client.name then
      settings = lsp.get_lsp_settings(M._state, client.name, folder_name)
    end

    -- Extract the requested section if specified
    if section and settings[section] then
      table.insert(responses, settings[section])
    else
      table.insert(responses, settings)
    end
  end

  return responses
end

--- LSP before_init callback to inject workspace settings
---@param params table LSP initialization params
---@param config table LSP config
local function lsp_before_init(params, config)
  -- Inject workspace settings if not already set
  if not config.settings or vim.tbl_isempty(config.settings) then
    local server_name = config.name
    if server_name then
      config.settings = lsp.get_lsp_settings(M._state, server_name)
    end
  end

  -- Inject workspace_folders if we have a workspace
  if M._state.workspace and not config.workspace_folders then
    config.workspace_folders = lsp.get_lsp_workspace_folders(M._state)
  end

  -- Set up workspace/configuration handler for folder-specific settings
  if not config.handlers then
    config.handlers = {}
  end

  if not config.handlers['workspace/configuration'] then
    config.handlers['workspace/configuration'] = handle_workspace_configuration
  end
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Setup the plugin
---@param opts table|nil Optional configuration
---   - file: string|nil - Explicit path to .code-workspace file to load
function M.setup(opts)
  opts = opts or {}

  if opts.file then
    load_workspace(opts.file)
  else
    -- Auto-detect
    local workspace_file = find_workspace_file(vim.fn.getcwd())
    if workspace_file then
      load_workspace(workspace_file)
    end
  end
end

--- Get LSP config for vim.lsp.config('*', workspace.lsp())
---@return table LSP config with root_dir, workspace_folders, and before_init
function M.lsp()
  local config = {
    root_dir = lsp_root_dir,
    before_init = lsp_before_init,
  }

  if M._state.workspace then
    config.workspace_folders = lsp.get_lsp_workspace_folders(M._state)
  end

  return config
end

--- Get workspace root directory
---@return string|nil Root directory
function M.get_root_dir()
  return M._state.root_dir
end

--- Get workspace folders as absolute paths
---@return table List of folder paths
function M.get_folders()
  if not M._state.workspace or not M._state.workspace.folders then
    return {}
  end

  local folders = {}
  for _, folder in ipairs(M._state.workspace.folders) do
    local path = folder.path
    if not vim.startswith(path, '/') then
      path = M._state.root_dir .. '/' .. path
    end
    table.insert(folders, vim.fn.resolve(path))
  end

  return folders
end

--- Get workspace settings
---@return table Workspace settings
function M.get_settings()
  if not M._state.workspace then
    return {}
  end
  return M._state.workspace.settings or {}
end

--- Register a custom setting prefix for an LSP server
---@param server_name string LSP server name (e.g., 'my_custom_ls')
---@param setting_prefix string VSCode setting prefix (e.g., 'myCustom')
function M.register_server_settings_prefix(server_name, setting_prefix)
  lsp.register_server_settings_prefix(server_name, setting_prefix)
end

--- Get launch.json configuration (interpolated)
--- Collects configurations and compounds from the workspace folder containing the path AND the workspace root
---@param path string|nil File path to determine context (defaults to current buffer)
---@return table|nil Parsed launch configuration with merged configurations and compounds arrays
function M.get_launch_config(path)
  local config_paths = collect_vscode_configs('launch.json', path)
  return merge_configs({ 'configurations', 'compounds' }, config_paths)
end

--- Resolve a launch configuration by name
--- If the name matches a configuration, returns a table with that single config.
--- If the name matches a compound, returns a table with all configurations it references.
--- This provides a universal interface for starting debug sessions regardless of config type.
---@param name string Configuration or compound name to resolve
---@param path string|nil File path to determine context (defaults to current buffer)
---@return table|nil Array of resolved configurations, or nil if not found
function M.resolve_launch_config(name, path)
  local launch = M.get_launch_config(path)
  if not launch then
    return nil
  end

  -- Build a lookup table for configurations by name
  local configs_by_name = {}
  if launch.configurations then
    for _, config in ipairs(launch.configurations) do
      if config.name then
        configs_by_name[config.name] = config
      end
    end
  end

  -- First, check if name matches a configuration
  if configs_by_name[name] then
    return { configs_by_name[name] }
  end

  -- Second, check if name matches a compound
  if launch.compounds then
    for _, compound in ipairs(launch.compounds) do
      if compound.name == name then
        local resolved = {}
        for _, ref_name in ipairs(compound.configurations or {}) do
          local config = configs_by_name[ref_name]
          if config then
            table.insert(resolved, config)
          end
        end
        -- Return resolved configs even if some references weren't found
        if #resolved > 0 then
          return resolved
        end
        return nil
      end
    end
  end

  return nil
end

--- Select a launch configuration using vim.ui.select
--- Shows a picker with all configurations and compounds, then resolves the selection.
---@param path string|nil File path to determine context (defaults to current buffer)
---@param callback fun(configs: table|nil) Called with resolved configurations or nil if cancelled
function M.select_launch_config(path, callback)
  local launch = M.get_launch_config(path)
  if not launch then
    vim.notify('No launch configurations found', vim.log.levels.WARN)
    callback(nil)
    return
  end

  -- Build list of selectable items
  local items = {}

  -- Add configurations
  if launch.configurations then
    for _, config in ipairs(launch.configurations) do
      if config.name then
        table.insert(items, {
          name = config.name,
          kind = 'config',
          display = config.name,
        })
      end
    end
  end

  -- Add compounds (with visual distinction)
  if launch.compounds then
    for _, compound in ipairs(launch.compounds) do
      if compound.name then
        local ref_count = compound.configurations and #compound.configurations or 0
        table.insert(items, {
          name = compound.name,
          kind = 'compound',
          display = string.format('%s [%d configs]', compound.name, ref_count),
        })
      end
    end
  end

  if #items == 0 then
    vim.notify('No launch configurations found', vim.log.levels.WARN)
    callback(nil)
    return
  end

  vim.ui.select(items, {
    prompt = 'Select launch configuration:',
    format_item = function(item)
      return item.display
    end,
  }, function(selected)
    if not selected then
      callback(nil)
      return
    end

    local configs = M.resolve_launch_config(selected.name, path)
    callback(configs)
  end)
end

--- Get tasks.json configuration (interpolated)
--- Collects tasks from the workspace folder containing the path AND the workspace root
---@param path string|nil File path to determine context (defaults to current buffer)
---@return table|nil Parsed tasks configuration with merged tasks array
function M.get_tasks_config(path)
  local config_paths = collect_vscode_configs('tasks.json', path)
  return merge_configs('tasks', config_paths)
end

--- Resolve a task by label
---@param label string Task label to resolve
---@param path string|nil File path to determine context (defaults to current buffer)
---@return table|nil The task configuration, or nil if not found
function M.resolve_task_config(label, path)
  local tasks_config = M.get_tasks_config(path)
  if not tasks_config or not tasks_config.tasks then
    return nil
  end

  for _, task in ipairs(tasks_config.tasks) do
    if task.label == label then
      return task
    end
  end

  return nil
end

--- Select a task using vim.ui.select
--- Shows a picker with all tasks, then resolves the selection.
---@param path string|nil File path to determine context (defaults to current buffer)
---@param callback fun(task: table|nil) Called with the selected task or nil if cancelled
function M.select_task_config(path, callback)
  local tasks_config = M.get_tasks_config(path)
  if not tasks_config or not tasks_config.tasks then
    vim.notify('No tasks found', vim.log.levels.WARN)
    callback(nil)
    return
  end

  -- Build list of selectable items
  local items = {}
  for _, task in ipairs(tasks_config.tasks) do
    if task.label then
      table.insert(items, {
        label = task.label,
        display = task.label,
      })
    end
  end

  if #items == 0 then
    vim.notify('No tasks found', vim.log.levels.WARN)
    callback(nil)
    return
  end

  vim.ui.select(items, {
    prompt = 'Select task:',
    format_item = function(item)
      return item.display
    end,
  }, function(selected)
    if not selected then
      callback(nil)
      return
    end

    local task = M.resolve_task_config(selected.label, path)
    callback(task)
  end)
end

return M
