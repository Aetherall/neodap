local M = {}

local interpolate = require('code-workspace.interpolate')

--- Convert flat dot-notation settings to nested tables
--- e.g., "Lua.runtime.version" = "LuaJIT" becomes {Lua = {runtime = {version = "LuaJIT"}}}
---@param flat_settings table Flat settings
---@param prefix string Setting prefix to extract
---@return table Nested settings
local function unflatten_settings(flat_settings, prefix)
  local result = {}

  for key, value in pairs(flat_settings) do
    if vim.startswith(key, prefix .. '.') then
      -- Remove prefix and split by dots
      local path = key:sub(#prefix + 2) -- +2 to skip the dot
      local parts = vim.split(path, '.', { plain = true })

      -- Build nested table
      local current = result
      for i = 1, #parts - 1 do
        if not current[parts[i]] then
          current[parts[i]] = {}
        end
        current = current[parts[i]]
      end
      current[parts[#parts]] = value
    end
  end

  return result
end

--- Default mapping of LSP server names to their VSCode setting prefixes
--- This is just a fallback for common servers. The actual extraction is more flexible.
--- Users can override this via M.register_server_settings_prefix()
local DEFAULT_SETTING_PREFIXES = {
  -- LSP server name -> setting prefix in VSCode
  pyright = 'python',
  pylsp = 'python',
  ruff_lsp = 'python',
  tsserver = 'typescript',
  ts_ls = 'typescript',
  denols = 'deno',
  rust_analyzer = 'rust-analyzer',
  gopls = 'gopls',
  clangd = 'clangd',
  lua_ls = 'Lua',
  eslint = 'eslint',
  jsonls = 'json',
  yamlls = 'yaml',
  html = 'html',
  cssls = 'css',
  tailwindcss = 'tailwindCSS',
}

--- User-registered custom mappings (takes precedence)
M._custom_setting_prefixes = {}

--- Register a custom setting prefix for an LSP server
--- This allows users to define how settings are extracted for custom or renamed servers
---@param server_name string LSP server name (e.g., 'my_custom_ls')
---@param setting_prefix string VSCode setting prefix (e.g., 'myCustom')
---@usage require('code-workspace.lsp').register_server_settings_prefix('my_ls', 'myLanguage')
function M.register_server_settings_prefix(server_name, setting_prefix)
  M._custom_setting_prefixes[server_name] = setting_prefix
end

--- Get the VSCode setting prefix for an LSP server
---@param server_name string LSP server name
---@return string|nil Setting prefix, or nil if unknown
local function get_setting_prefix(server_name)
  -- Check custom mappings first
  if M._custom_setting_prefixes[server_name] then
    return M._custom_setting_prefixes[server_name]
  end

  -- Check default mappings
  if DEFAULT_SETTING_PREFIXES[server_name] then
    return DEFAULT_SETTING_PREFIXES[server_name]
  end

  -- Fallback: use server name as prefix
  return server_name
end

--- Extract settings for a specific prefix from flat or nested settings
---@param settings table Settings (can be flat or nested)
---@param prefix string Setting prefix to extract
---@return table Extracted settings
local function extract_prefix_settings(settings, prefix)
  local result = {}

  -- Check if settings are already nested
  if settings[prefix] and type(settings[prefix]) == 'table' then
    result[prefix] = vim.deepcopy(settings[prefix])
  else
    -- Convert flat dot-notation settings to nested format
    local nested = unflatten_settings(settings, prefix)
    if next(nested) ~= nil then
      result[prefix] = nested
    end
  end

  return result
end

--- Extract LSP settings for a specific server from workspace settings
---@param state table Plugin state
---@param server_name string LSP server name (e.g., 'pyright', 'tsserver')
---@param folder_name string|nil Folder name for folder-specific settings
---@return table LSP settings
function M.get_lsp_settings(state, server_name, folder_name)
  if not state.workspace or not state.workspace.settings then
    return {}
  end

  local settings = state.workspace.settings
  local result = {}

  -- Get the setting prefix for this server
  local prefix = get_setting_prefix(server_name)

  -- Extract workspace-level settings for this prefix
  result = extract_prefix_settings(settings, prefix)

  -- Also check for direct server settings (e.g., settings["tsserver"] = {...})
  if settings[server_name] and type(settings[server_name]) == 'table' then
    result[server_name] = vim.deepcopy(settings[server_name])
  end

  -- Merge folder-specific settings if available
  if folder_name and state.folder_settings and state.folder_settings[folder_name] then
    local folder_settings = state.folder_settings[folder_name]
    local folder_result = extract_prefix_settings(folder_settings, prefix)

    -- Also check for direct server settings in folder
    if folder_settings[server_name] and type(folder_settings[server_name]) == 'table' then
      folder_result[server_name] = vim.deepcopy(folder_settings[server_name])
    end

    result = vim.tbl_deep_extend('force', result, folder_result)
  end

  -- Interpolate all settings
  return interpolate.interpolate_config(result, state)
end

--- Get all LSP-related settings from workspace
---@param state table Plugin state
---@return table All LSP settings
function M.get_all_lsp_settings(state)
  if not state.workspace or not state.workspace.settings then
    return {}
  end

  local settings = vim.deepcopy(state.workspace.settings)

  -- Interpolate all settings
  return interpolate.interpolate_config(settings, state)
end

--- Extract workspace folders for LSP
---@param state table Plugin state
---@return table List of workspace folders in LSP format
function M.get_lsp_workspace_folders(state)
  if not state.workspace or not state.workspace.folders then
    return {}
  end

  local folders = {}
  for _, folder in ipairs(state.workspace.folders) do
    local path = folder.path
    if not vim.startswith(path, '/') and state.root_dir then
      path = state.root_dir .. '/' .. path
    end
    path = vim.fn.resolve(path)

    table.insert(folders, {
      uri = vim.uri_from_fname(path),
      name = folder.name or vim.fn.fnamemodify(path, ':t'),
    })
  end

  return folders
end

return M
