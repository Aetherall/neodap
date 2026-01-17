local M = {}

--- Simple fallback: strip trailing commas from JSON
---@param str string JSON string
---@return string Cleaned JSON string
local function strip_trailing_commas(str)
  return str:gsub(',%s*]', ']'):gsub(',%s*}', '}')
end

--- Simple fallback: strip single-line comments from JSON
---@param str string JSON string
---@return string Cleaned JSON string
local function strip_line_comments(str)
  -- Remove // comments (but not inside strings - simple heuristic)
  return str:gsub('(.-)\n', function(line)
    -- Find // that's not inside a string (simple: not preceded by odd number of ")
    local in_string = false
    local i = 1
    while i <= #line do
      local c = line:sub(i, i)
      if c == '"' and line:sub(i - 1, i - 1) ~= '\\' then
        in_string = not in_string
      elseif not in_string and c == '/' and line:sub(i + 1, i + 1) == '/' then
        return line:sub(1, i - 1) .. '\n'
      end
      i = i + 1
    end
    return line .. '\n'
  end)
end

--- Parse a JSON file with comments (JSONC)
--- Uses plenary.json if available, falls back to simple stripping
---@param file_path string Path to JSON file
---@return table|nil Parsed JSON data
function M.parse_json_file(file_path)
  local f = io.open(file_path, 'r')
  if not f then
    return nil
  end

  local content = f:read('*a')
  f:close()

  -- Try plenary.json first (robust handling of comments + trailing commas)
  local ok, plenary_json = pcall(require, 'plenary.json')
  if ok then
    content = plenary_json.json_strip_comments(content, {
      whitespace = false,
      trailing_commas = false,
    })
  else
    -- Fallback: simple comment and trailing comma removal
    content = strip_line_comments(content)
    content = strip_trailing_commas(content)
  end

  -- Parse JSON
  local decode_ok, data = pcall(vim.fn.json_decode, content)
  if not decode_ok then
    return nil
  end

  return data
end

--- Parse a .code-workspace file
---@param workspace_file string Path to workspace file
---@return table|nil Parsed workspace data
function M.parse_workspace_file(workspace_file)
  return M.parse_json_file(workspace_file)
end

return M
