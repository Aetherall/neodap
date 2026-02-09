local M = {}

-- Load other modules
local parser = require('code-workspace.parser')
local interpolate = require('code-workspace.interpolate')
local lsp = require('code-workspace.lsp')

-- ============================================================================
-- Internal functions
-- ============================================================================

--- Find .code-workspace file starting from given directory
--- Walks all the way up to / regardless of .vscode or .git directories found along the way
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

--- Find .vscode directory starting from given directory
---@param start_dir string Starting directory
---@return string|nil Parent directory containing .vscode
local function find_vscode_root(start_dir)
  local current = start_dir
  while current ~= '/' do
    local vscode_dir = current .. '/.vscode'
    if vim.fn.isdirectory(vscode_dir) == 1 then
      return current
    end
    current = vim.fn.fnamemodify(current, ':h')
  end
  return nil
end

--- Resolve the search path from an optional path argument
--- Falls back to current buffer, then cwd
---@param path string|nil Explicit path
---@return string Resolved absolute path
local function resolve_search_path(path)
  local search_path = path
  if not search_path or search_path == '' then
    search_path = vim.api.nvim_buf_get_name(0)
  end
  if not search_path or search_path == '' then
    search_path = vim.fn.getcwd()
  end
  return vim.fn.fnamemodify(search_path, ':p')
end

--- Resolve the starting directory from a path (file → parent dir, dir → itself)
---@param abs_path string Absolute path
---@return string Directory path
local function to_search_dir(abs_path)
  if vim.fn.isdirectory(abs_path) == 0 then
    return vim.fn.fnamemodify(abs_path, ':h')
  end
  return abs_path
end

--- Resolve workspace folder paths from workspace data
--- Converts relative folder paths to absolute using workspace root
---@param workspace_data table Parsed workspace data
---@param ws_root string Workspace root directory (where .code-workspace lives)
---@return table List of {path = abs_path, name = folder_name} entries
local function resolve_workspace_folders(workspace_data, ws_root)
  local folders = {}
  if not workspace_data or not workspace_data.folders then
    return folders
  end
  for _, folder in ipairs(workspace_data.folders) do
    local folder_path = folder.path
    if folder_path == '.' then
      folder_path = ws_root
    elseif not vim.startswith(folder_path, '/') then
      folder_path = ws_root .. '/' .. folder_path
    end
    folder_path = vim.fn.resolve(folder_path)
    table.insert(folders, {
      path = folder_path,
      name = folder.name or vim.fn.fnamemodify(folder_path, ':t'),
    })
  end
  return folders
end

--- Resolve workspace context for a given path (stateless)
--- Walks up from the path looking for .code-workspace, parses it on the fly
---@param path string|nil File path (defaults to current buffer, then cwd)
---@return table|nil workspace_data Parsed workspace data, or nil
---@return string|nil ws_root Workspace root directory
---@return table|nil folders Resolved folder list [{path, name}]
local function resolve_workspace(path)
  local abs_path = resolve_search_path(path)
  local search_dir = to_search_dir(abs_path)

  local workspace_file = find_workspace_file(search_dir)
  if not workspace_file then
    return nil, nil, nil
  end

  local workspace_data = parser.parse_workspace_file(workspace_file)
  if not workspace_data then
    return nil, nil, nil
  end

  local ws_root = vim.fn.fnamemodify(workspace_file, ':h')
  local folders = resolve_workspace_folders(workspace_data, ws_root)

  return workspace_data, ws_root, folders
end

--- Find which workspace folder contains a given path
---@param abs_path string Absolute path
---@param folders table Resolved folder list [{path, name}]
---@return table|nil folder The matching folder entry, or nil
local function find_containing_folder(abs_path, folders)
  for _, folder in ipairs(folders) do
    if vim.startswith(abs_path, folder.path .. '/') or abs_path == folder.path then
      return folder
    end
  end
  return nil
end

--- Get effective root directory for a given path (stateless)
--- Priority: workspace folder > workspace root > .vscode (within .git) > .git > cwd
---@param path string|nil File path (defaults to current buffer, then cwd)
---@return string|nil Root directory
local function get_project_root(path)
  local abs_path = resolve_search_path(path)
  local search_dir = to_search_dir(abs_path)

  -- Try workspace resolution first (always walks all the way up)
  local workspace_data, ws_root, folders = resolve_workspace(path)
  if workspace_data and folders then
    -- Find which workspace folder contains this path
    local folder = find_containing_folder(abs_path, folders)
    if folder then
      return folder.path
    end
    -- Path is within workspace but not in a specific folder
    if ws_root and (vim.startswith(abs_path, ws_root .. '/') or abs_path == ws_root) then
      return ws_root
    end
  end

  -- No workspace - fall back to .vscode/.git heuristics
  local git_root = vim.fs.root(search_dir, { '.git' })
  local vscode_root = find_vscode_root(search_dir)

  -- Prefer .vscode only if it's at or below .git root (part of the project)
  -- Otherwise prefer .git (the .vscode might be user config at home level)
  if vscode_root and git_root then
    if vim.startswith(vscode_root, git_root) or vscode_root == git_root then
      return vscode_root
    else
      return git_root
    end
  elseif vscode_root then
    return vscode_root
  elseif git_root then
    return git_root
  end

  -- Last resort: use cwd
  return vim.fn.getcwd()
end

--- Collect .vscode config file paths for a given path (stateless)
--- If a .code-workspace is found, collects from ALL declared folders
--- Otherwise collects from the nearest .vscode directory
---@param config_name string Config file name (e.g., 'launch.json', 'tasks.json')
---@param path string|nil File path to determine context (defaults to current buffer)
---@return table configs_to_load List of {path, folder} entries
---@return table|nil workspace_data Parsed workspace data (for caller to use)
---@return string|nil ws_root Workspace root directory
local function collect_vscode_configs(config_name, path)
  local abs_path = resolve_search_path(path)
  local effective_root = get_project_root(path)

  local configs_to_load = {}
  local added_paths = {}

  local function add_config(config_path, workspace_folder)
    if not added_paths[config_path] then
      added_paths[config_path] = true
      table.insert(configs_to_load, { path = config_path, folder = workspace_folder })
    end
  end

  -- Try to find workspace and collect from all folders
  local workspace_data, ws_root, folders = resolve_workspace(path)
  if workspace_data and folders then
    for _, folder in ipairs(folders) do
      if folder.path ~= effective_root then
        add_config(folder.path .. '/.vscode/' .. config_name, folder.path)
      end
    end
  end

  -- Add effective root config last (ensures it's always included)
  if effective_root then
    add_config(effective_root .. '/.vscode/' .. config_name, effective_root)
  end

  return configs_to_load, workspace_data, ws_root
end

--- Load and merge multiple config files (stateless)
--- Each merged item gets a __folder field with the folder name it came from
---@param array_keys string|table Single key or list of keys to merge
---@param paths table List of config entries (each with .path and .folder)
---@param effective_root string|nil Root directory for interpolation fallback
---@param workspace_data table|nil Parsed workspace data (for interpolation)
---@param ws_root string|nil Workspace root directory (for interpolation)
---@param folders table|nil Resolved workspace folders for name lookup
---@return table|nil Merged configuration or nil if no configs found
local function merge_configs(array_keys, paths, effective_root, workspace_data, ws_root, folders)
  if type(array_keys) == 'string' then
    array_keys = { array_keys }
  end

  -- Build folder path → name lookup
  local folder_names = {}
  if folders then
    for _, folder in ipairs(folders) do
      folder_names[folder.path] = folder.name
    end
  end

  local merged = {}
  for _, key in ipairs(array_keys) do
    merged[key] = {}
  end

  for _, config_entry in ipairs(paths) do
    local config_path = config_entry.path
    local config_folder = config_entry.folder
    local folder_name = folder_names[config_folder]
      or (config_folder and vim.fn.fnamemodify(config_folder, ':t'))

    -- Create interpolation state with the config's own folder as root
    local interp_state = {
      workspace = workspace_data,
      workspace_root_dir = ws_root,
      root_dir = config_folder or effective_root,
    }

    local config = parser.parse_json_file(config_path)
    if config then
      config = interpolate.interpolate_config(config, interp_state)

      for _, key in ipairs(array_keys) do
        if config[key] then
          for _, item in ipairs(config[key]) do
            item.__folder = folder_name
            table.insert(merged[key], item)
          end
        end
      end

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
      merged[key] = nil
    end
  end

  if not has_content then
    return nil
  end

  return merged
end

--- Load per-folder settings dynamically
---@param folders table Resolved folder list [{path, name}]
---@return table folder_settings Map of folder_name -> settings
local function load_folder_settings(folders)
  local folder_settings = {}
  for _, folder in ipairs(folders) do
    local settings_file = folder.path .. '/.vscode/settings.json'
    local settings = parser.parse_json_file(settings_file)
    if settings then
      folder_settings[folder.name] = settings
    end
  end
  return folder_settings
end

--- Build LSP state from workspace context (computed on the fly)
---@param workspace_data table|nil Parsed workspace data
---@param ws_root string|nil Workspace root directory
---@param folders table|nil Resolved folder list
---@return table state State table compatible with lsp.lua functions
local function build_lsp_state(workspace_data, ws_root, folders)
  local state = {
    workspace = workspace_data,
    root_dir = ws_root,
    folder_settings = folders and load_folder_settings(folders) or nil,
  }
  return state
end

--- LSP root_dir function - resolves per-buffer using get_project_root
---@param bufnr integer Buffer number
---@param on_dir function Callback function that receives the root directory
local function lsp_root_dir(bufnr, on_dir)
  local fname = vim.api.nvim_buf_get_name(bufnr)
  local root = get_project_root(fname)

  if root then
    on_dir(root)
    return
  end

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

  -- Resolve workspace context dynamically from the client's root
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  if not client then
    return {}
  end

  local workspace_data, ws_root, folders = resolve_workspace(
    client.root_dir or vim.fn.getcwd()
  )
  local state = build_lsp_state(workspace_data, ws_root, folders)

  local items = result.items or {}
  local responses = {}

  -- Build folder URI lookup for scope matching
  local folder_uri_map = {}
  if folders then
    for _, folder in ipairs(folders) do
      folder_uri_map[vim.uri_from_fname(folder.path)] = folder.name
    end
  end

  for _, item in ipairs(items) do
    local scope_uri = item.scopeUri
    local section = item.section

    -- Determine which folder this request is for
    local folder_name = nil
    if scope_uri then
      for uri, name in pairs(folder_uri_map) do
        if scope_uri == uri or vim.startswith(scope_uri, uri .. '/') then
          folder_name = name
          break
        end
      end
    end

    local settings = {}
    if client.name then
      settings = lsp.get_lsp_settings(state, client.name, folder_name)
    end

    if section and settings[section] then
      table.insert(responses, settings[section])
    else
      table.insert(responses, settings)
    end
  end

  return responses
end

--- LSP before_init callback to inject workspace settings
--- Only injects the workspace folder that contains root_dir, not all folders.
--- Other folders are added lazily via workspace/didChangeWorkspaceFolders
--- when buffers from those folders are opened.
---@param params table LSP initialization params
---@param config table LSP config
local function lsp_before_init(params, config)
  -- Resolve workspace context from the LSP root or cwd
  local root = config.root_dir
  if type(root) == 'string' then
    -- root_dir is already resolved at this point
  else
    root = vim.fn.getcwd()
  end

  local workspace_data, ws_root, folders = resolve_workspace(root)
  local state = build_lsp_state(workspace_data, ws_root, folders)

  -- Inject workspace settings if not already set
  if not config.settings or vim.tbl_isempty(config.settings) then
    local server_name = config.name
    if server_name then
      config.settings = lsp.get_lsp_settings(state, server_name)
    end
  end

  -- Only inject the folder that contains root_dir, not all workspace folders.
  -- This prevents tsserver from eagerly loading tsconfigs from all folders
  -- (e.g., loading frontend/ when you're only working in backend/).
  -- Additional folders are added lazily when buffers from them are opened.
  if workspace_data and folders and not config.workspace_folders then
    local abs_root = vim.fn.fnamemodify(root, ':p')
    local containing = find_containing_folder(abs_root, folders)
    if containing then
      config.workspace_folders = {
        {
          uri = vim.uri_from_fname(containing.path),
          name = containing.name,
        },
      }
    end
  end

  -- Set up workspace/configuration handler for folder-specific settings
  if not config.handlers then
    config.handlers = {}
  end

  if not config.handlers['workspace/configuration'] then
    config.handlers['workspace/configuration'] = handle_workspace_configuration
  end
end

--- Custom reuse_client that allows reusing a client for any buffer
--- within the same workspace, even if its folder hasn't been added yet.
--- When reusing, lazily adds the new folder via workspace/didChangeWorkspaceFolders.
---@param client vim.lsp.Client
---@param config table LSP config
---@return boolean
local function reuse_client(client, config)
  if client.name ~= config.name or client:is_stopped() then
    return false
  end

  -- Get the new config's root_dir
  local new_root = config.root_dir
  if type(new_root) ~= 'string' or new_root == '' then
    return false
  end

  -- Check if the new root and the client's root are in the same workspace
  local _, new_ws_root = resolve_workspace(new_root)
  if not new_ws_root then
    -- No workspace - fall back to default: same root_dir means reuse
    return client.root_dir == new_root
  end

  local _, client_ws_root = resolve_workspace(client.root_dir)
  if new_ws_root ~= client_ws_root then
    return false
  end

  -- Same workspace - reuse the client, but lazily add the new folder if needed
  local new_uri = vim.uri_from_fname(new_root)
  local already_has = false
  for _, folder in ipairs(client.workspace_folders or {}) do
    if folder.uri == new_uri then
      already_has = true
      break
    end
  end

  if not already_has then
    -- Find the folder name from workspace metadata
    local _, _, folders = resolve_workspace(new_root)
    local folder_entry = folders and find_containing_folder(
      vim.fn.fnamemodify(new_root, ':p'), folders
    )
    local new_folder = {
      uri = new_uri,
      name = folder_entry and folder_entry.name or vim.fn.fnamemodify(new_root, ':t'),
    }

    -- Notify the LSP server about the new folder
    client:notify('workspace/didChangeWorkspaceFolders', {
      event = {
        added = { new_folder },
        removed = {},
      },
    })

    -- Update the client's workspace_folders so future reuse checks work
    client.workspace_folders = client.workspace_folders or {}
    table.insert(client.workspace_folders, new_folder)
  end

  return true
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Get LSP config for vim.lsp.config('*', workspace.lsp())
---@return table LSP config with root_dir, before_init, and reuse_client
function M.lsp()
  return {
    root_dir = lsp_root_dir,
    before_init = lsp_before_init,
    reuse_client = reuse_client,
  }
end

--- Get effective root directory for a given path
---@param path string|nil File path (defaults to current buffer, then cwd)
---@return string|nil Root directory
function M.get_project_root(path)
  return get_project_root(path)
end

--- Get workspace folders as absolute paths for a given path
---@param path string|nil File path to determine context (defaults to current buffer)
---@return table List of folder paths
function M.get_folders(path)
  local _, _, folders = resolve_workspace(path)
  if not folders then
    return {}
  end
  local paths = {}
  for _, folder in ipairs(folders) do
    table.insert(paths, folder.path)
  end
  return paths
end

--- Get workspace settings for a given path
---@param path string|nil File path to determine context (defaults to current buffer)
---@return table Workspace settings
function M.get_settings(path)
  local workspace_data = resolve_workspace(path)
  if not workspace_data then
    return {}
  end
  return workspace_data.settings or {}
end

--- Register a custom setting prefix for an LSP server
---@param server_name string LSP server name (e.g., 'my_custom_ls')
---@param setting_prefix string VSCode setting prefix (e.g., 'myCustom')
function M.register_server_settings_prefix(server_name, setting_prefix)
  lsp.register_server_settings_prefix(server_name, setting_prefix)
end

--- Get launch.json configuration (interpolated)
--- Collects configurations and compounds from all workspace folders + workspace launch section
---@param path string|nil File path to determine context (defaults to current buffer)
---@return table|nil Parsed launch configuration with merged configurations and compounds arrays
function M.get_launch_config(path)
  local effective_root = get_project_root(path)
  local config_paths, workspace_data, ws_root = collect_vscode_configs('launch.json', path)
  local _, _, folders = resolve_workspace(path)
  local merged = merge_configs({ 'configurations', 'compounds' }, config_paths, effective_root, workspace_data, ws_root, folders)

  -- Also merge configurations and compounds from the workspace file's launch section
  -- These are workspace-level (no specific folder)
  if workspace_data and workspace_data.launch then
    local ws_launch = workspace_data.launch
    if ws_launch.compounds then
      merged = merged or { configurations = {}, compounds = {} }
      merged.compounds = merged.compounds or {}
      for _, compound in ipairs(ws_launch.compounds) do
        compound.__folder = 'workspace'
        table.insert(merged.compounds, compound)
      end
    end
    if ws_launch.configurations then
      merged = merged or { configurations = {}, compounds = {} }
      merged.configurations = merged.configurations or {}
      for _, config in ipairs(ws_launch.configurations) do
        config.__folder = 'workspace'
        table.insert(merged.configurations, config)
      end
    end
  end

  return merged
end

--- Resolve a launch configuration by name
--- If the name matches a configuration, returns a table with that single config.
--- If the name matches a compound, returns a table with all configurations it references.
---@param name string Configuration or compound name to resolve
---@param path string|nil File path to determine context (defaults to current buffer)
---@return table|nil configs Array of resolved configurations, or nil if not found
---@return table|nil compound Compound metadata (preLaunchTask, postDebugTask) if resolving a compound
function M.resolve_launch_config(name, path)
  local launch = M.get_launch_config(path)
  if not launch then
    return nil, nil
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
    return { configs_by_name[name] }, nil
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
        if #resolved > 0 then
          local compound_meta = {
            name = compound.name,
            preLaunchTask = compound.preLaunchTask,
            postDebugTask = compound.postDebugTask,
            stopAll = compound.stopAll,
          }
          return resolved, compound_meta
        end
        return nil, nil
      end
    end
  end

  return nil, nil
end

--- Select a launch configuration using vim.ui.select
--- Shows a picker with all configurations and compounds, then resolves the selection.
---@param path string|nil File path to determine context (defaults to current buffer)
---@param callback fun(configs: table|nil, compound_meta: table|nil) Called with resolved configurations and optional compound metadata
function M.select_launch_config(path, callback)
  local launch = M.get_launch_config(path)
  if not launch then
    vim.notify('No launch configurations found', vim.log.levels.WARN)
    callback(nil, nil)
    return
  end

  -- Collect items grouped by folder
  ---@type table<string, table[]>
  local groups = {}
  local group_order = {}

  local function add_item(folder, item)
    folder = folder or 'other'
    if not groups[folder] then
      groups[folder] = {}
      table.insert(group_order, folder)
    end
    table.insert(groups[folder], item)
  end

  if launch.configurations then
    for _, config in ipairs(launch.configurations) do
      if config.name then
        add_item(config.__folder, {
          name = config.name,
          kind = 'config',
          folder = config.__folder,
        })
      end
    end
  end

  if launch.compounds then
    for _, compound in ipairs(launch.compounds) do
      if compound.name then
        local ref_count = compound.configurations and #compound.configurations or 0
        add_item(compound.__folder, {
          name = compound.name,
          kind = 'compound',
          folder = compound.__folder,
          ref_count = ref_count,
        })
      end
    end
  end

  -- Flatten groups into ordered list
  local items = {}
  local has_multiple_groups = #group_order > 1

  for _, folder in ipairs(group_order) do
    for _, item in ipairs(groups[folder]) do
      -- Build display string
      local display = item.name
      if item.kind == 'compound' then
        display = string.format('%s [%d configs]', item.name, item.ref_count)
      end
      -- Prepend folder name when there are multiple groups
      if has_multiple_groups then
        display = string.format('[%s] %s', item.folder, display)
      end
      item.display = display
      table.insert(items, item)
    end
  end

  if #items == 0 then
    vim.notify('No launch configurations found', vim.log.levels.WARN)
    callback(nil, nil)
    return
  end

  vim.ui.select(items, {
    prompt = 'Select launch configuration:',
    format_item = function(item)
      return item.display
    end,
  }, function(selected)
    if not selected then
      callback(nil, nil)
      return
    end

    local configs, compound_meta = M.resolve_launch_config(selected.name, path)
    callback(configs, compound_meta)
  end)
end

--- Get tasks.json configuration (interpolated)
---@param path string|nil File path to determine context (defaults to current buffer)
---@return table|nil Parsed tasks configuration with merged tasks array
function M.get_tasks_config(path)
  local effective_root = get_project_root(path)
  local config_paths, workspace_data, ws_root = collect_vscode_configs('tasks.json', path)
  local _, _, folders = resolve_workspace(path)
  return merge_configs('tasks', config_paths, effective_root, workspace_data, ws_root, folders)
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
---@param path string|nil File path to determine context (defaults to current buffer)
---@param callback fun(task: table|nil) Called with the selected task or nil if cancelled
function M.select_task_config(path, callback)
  local tasks_config = M.get_tasks_config(path)
  if not tasks_config or not tasks_config.tasks then
    vim.notify('No tasks found', vim.log.levels.WARN)
    callback(nil)
    return
  end

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

-- Export internal helpers for direct use
M.find_workspace_file = find_workspace_file
M.find_vscode_root = find_vscode_root
M.find_folder_for_path = function(path)
  local abs_path = vim.fn.fnamemodify(path, ':p')
  local _, _, folders = resolve_workspace(path)
  if not folders then return nil end
  local folder = find_containing_folder(abs_path, folders)
  return folder and folder.path or nil
end

return M
