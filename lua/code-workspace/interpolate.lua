local M = {}

--- Get environment variables with VSCode compatibility
---@return table Environment variables
local function get_env_vars()
  local env = vim.fn.environ()
  -- Add common VSCode variables
  env.HOME = os.getenv('HOME') or ''
  env.USER = os.getenv('USER') or ''
  env.TMPDIR = os.getenv('TMPDIR') or '/tmp'
  return env
end

--- Interpolate workspace variables in a string
---@param str string String with variables like ${workspaceFolder}
---@param state table Plugin state
---@param folder_index number|nil Specific folder index
---@return string Interpolated string
function M.interpolate_string(str, state, folder_index)
  if not str or type(str) ~= 'string' then
    return str
  end

  local result = str
  local env = get_env_vars()

  -- Get workspace folders
  local folders = {}
  if state.workspace and state.workspace.folders then
    for _, folder in ipairs(state.workspace.folders) do
      local path = folder.path
      if not vim.startswith(path, '/') and state.root_dir then
        path = state.root_dir .. '/' .. path
      end
      table.insert(folders, vim.fn.resolve(path))
    end
  end

  -- Default workspace folder
  local workspace_folder = folders[1] or state.root_dir or vim.fn.getcwd()

  -- Variable replacements
  local replacements = {
    -- Workspace variables
    ['${workspaceFolder}'] = workspace_folder,
    ['${workspaceFolderBasename}'] = vim.fn.fnamemodify(workspace_folder, ':t'),
    ['${workspaceRoot}'] = workspace_folder, -- deprecated but still supported

    -- File variables (relative to current buffer)
    ['${file}'] = function()
      return vim.fn.expand('%:p')
    end,
    ['${fileBasename}'] = function()
      return vim.fn.expand('%:t')
    end,
    ['${fileBasenameNoExtension}'] = function()
      return vim.fn.expand('%:t:r')
    end,
    ['${fileExtname}'] = function()
      return vim.fn.expand('%:e')
    end,
    ['${fileDirname}'] = function()
      return vim.fn.expand('%:p:h')
    end,
    ['${fileRelative}'] = function()
      local file = vim.fn.expand('%:p')
      return vim.fn.fnamemodify(file, ':~:.')
    end,
    ['${relativeFile}'] = function()
      local file = vim.fn.expand('%:p')
      return vim.fn.fnamemodify(file, ':~:.')
    end,

    -- Other variables
    ['${cwd}'] = vim.fn.getcwd(),
    ['${execPath}'] = vim.v.progpath,
    ['${pathSeparator}'] = package.config:sub(1, 1),

    -- Line variables
    ['${lineNumber}'] = function()
      return tostring(vim.fn.line('.'))
    end,
    ['${selectedText}'] = function()
      return vim.fn.getreg('"')
    end,
  }

  -- Handle ${workspaceFolder:N} where N is the folder index
  result = result:gsub('%${workspaceFolder:(%d+)}', function(idx)
    local index = tonumber(idx)
    return folders[index] or workspace_folder
  end)

  -- Handle ${workspaceFolderBasename:N}
  result = result:gsub('%${workspaceFolderBasename:(%d+)}', function(idx)
    local index = tonumber(idx)
    local folder = folders[index] or workspace_folder
    return vim.fn.fnamemodify(folder, ':t')
  end)

  -- Replace standard variables
  for pattern, replacement in pairs(replacements) do
    if type(replacement) == 'function' then
      -- Lazy evaluation for file-relative variables
      result = result:gsub(vim.pesc(pattern), function()
        return replacement()
      end)
    else
      result = result:gsub(vim.pesc(pattern), replacement)
    end
  end

  -- Handle environment variables ${env:VAR_NAME}
  result = result:gsub('%${env:([%w_]+)}', function(var_name)
    return env[var_name] or ''
  end)

  -- Handle config variables ${config:section.key}
  result = result:gsub('%${config:([%w_.]+)}', function(config_path)
    -- Try to get from workspace settings first
    if state.workspace and state.workspace.settings then
      local value = state.workspace.settings
      for part in config_path:gmatch('[^.]+') do
        if type(value) == 'table' then
          value = value[part]
        else
          value = nil
          break
        end
      end
      if value ~= nil then
        return tostring(value)
      end
    end
    -- Fallback to vim.g variables
    return tostring(vim.g[config_path] or '')
  end)

  -- Handle command substitution ${command:commandId}
  result = result:gsub('%${command:([%w_.]+)}', function(command_id)
    -- This would need integration with VSCode command system
    -- For now, just return empty string
    return ''
  end)

  return result
end

--- Recursively interpolate all strings in a table
---@param tbl table Table to interpolate
---@param state table Plugin state
---@return table Interpolated table
function M.interpolate_config(tbl, state)
  if type(tbl) ~= 'table' then
    if type(tbl) == 'string' then
      return M.interpolate_string(tbl, state)
    end
    return tbl
  end

  local result = {}
  for k, v in pairs(tbl) do
    if type(v) == 'table' then
      result[k] = M.interpolate_config(v, state)
    elseif type(v) == 'string' then
      result[k] = M.interpolate_string(v, state)
    else
      result[k] = v
    end
  end

  return result
end

return M
