-- Shared URI parsing utilities for plugin buffers
-- Handles URIs like: scheme:path?key1=value1&key2

local M = {}

---Parse a plugin URI into path and query options
---@param uri string Full URI (e.g., "dap-input:@frame?pin&closeonsubmit")
---@param scheme string Scheme prefix to strip (e.g., "dap-input")
---@return string path The path portion
---@return table options Query parameters as key-value pairs
function M.parse(uri, scheme)
  -- Remove scheme: prefix
  local pattern = "^" .. scheme:gsub("%-", "%%-") .. ":"
  local path = uri:gsub(pattern, "")

  -- Split path and query string
  local path_part, query = path:match("^([^?]+)%??(.*)")
  path_part = path_part or path

  -- Parse query options
  local options = {}
  if query and query ~= "" then
    for param in query:gmatch("[^&]+") do
      local key, value = param:match("([^=]+)=?(.*)")
      if key then
        options[key] = value ~= "" and value or true
      end
    end
  end

  return path_part, options
end

---Parse dap://source/{path}[?session={id}] URI
---@param uri string URI to parse
---@return string? path Source path or nil if not a valid source URI
---@return string? session_id Session ID if specified in query param
function M.parse_source_uri(uri)
  local after_scheme = uri:match("^dap://source/(.+)$")
  if not after_scheme then
    return nil, nil
  end

  -- Split path and query string
  local path, query = after_scheme:match("^([^?]+)%??(.*)")
  path = path or after_scheme

  -- Extract session from query params
  local session_id = nil
  if query and query ~= "" then
    session_id = query:match("session=([^&]+)")
  end

  return path, session_id
end

return M
