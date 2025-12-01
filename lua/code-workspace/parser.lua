local M = {}

--- Parse a JSON file with comments (JSONC)
---@param file_path string Path to JSON file
---@return table|nil Parsed JSON data
function M.parse_json_file(file_path)
  local f = io.open(file_path, 'r')
  if not f then
    return nil
  end

  local content = f:read('*a')
  f:close()

  -- Remove comments from JSONC
  content = M.strip_json_comments(content)

  -- Parse JSON
  local ok, data = pcall(vim.fn.json_decode, content)
  if not ok then
    return nil
  end

  return data
end

--- Strip comments from JSONC (JSON with comments)
---@param str string JSONC string
---@return string JSON string without comments
function M.strip_json_comments(str)
  local result = {}
  local in_string = false
  local in_single_comment = false
  local in_multi_comment = false
  local escape_next = false

  local i = 1
  while i <= #str do
    local c = str:sub(i, i)
    local next_c = str:sub(i + 1, i + 1)

    if escape_next then
      if not in_single_comment and not in_multi_comment then
        table.insert(result, c)
      end
      escape_next = false
      i = i + 1
    elseif in_string then
      table.insert(result, c)
      if c == '\\' then
        escape_next = true
      elseif c == '"' then
        in_string = false
      end
      i = i + 1
    elseif in_single_comment then
      if c == '\n' then
        in_single_comment = false
        table.insert(result, c)
      end
      i = i + 1
    elseif in_multi_comment then
      if c == '*' and next_c == '/' then
        in_multi_comment = false
        i = i + 2
      else
        i = i + 1
      end
    else
      if c == '"' then
        in_string = true
        table.insert(result, c)
        i = i + 1
      elseif c == '/' and next_c == '/' then
        in_single_comment = true
        i = i + 2
      elseif c == '/' and next_c == '*' then
        in_multi_comment = true
        i = i + 2
      else
        table.insert(result, c)
        i = i + 1
      end
    end
  end

  return table.concat(result)
end

--- Parse a .code-workspace file
---@param workspace_file string Path to workspace file
---@return table|nil Parsed workspace data
function M.parse_workspace_file(workspace_file)
  return M.parse_json_file(workspace_file)
end

return M
