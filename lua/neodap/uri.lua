--- URI: Entity Identity
---
--- URIs are stable, unique strings that identify entities.
--- Format: {type}:{components...}
---
--- This module provides:
--- - Builders: construct URIs from components
--- - Parsing: extract type and components from URI string
--- - Resolution: find entity by URI (via graph index)
---@class neodap.uri
local M = {}

--------------------------------------------------------------------------------
-- Type Derivation
--------------------------------------------------------------------------------

-- Map URI type prefix to entity type name (for types that don't follow simple capitalization)
local type_map = {
  sourcebinding = "SourceBinding",
  bpbinding = "BreakpointBinding",
  exfilter = "ExceptionFilter",
  exfilterbind = "ExceptionFilterBinding",
  exfilters = "ExceptionFiltersGroup",
}

--- Extract entity type from URI string
--- "session:xotat" → "Session", "thread:xotat:1" → "Thread"
---@param uri string
---@return string? entity_type PascalCase type name
function M.type_of(uri)
  if uri == "debugger" then return "Debugger" end
  local t = uri:match("^([^:]+):")
  if not t then return nil end
  -- Use mapping for compound names, otherwise just capitalize first letter
  if type_map[t] then return type_map[t] end
  return t:sub(1, 1):upper() .. t:sub(2)
end

--------------------------------------------------------------------------------
-- Builders
--------------------------------------------------------------------------------

--- Build debugger URI (singleton)
---@return string
function M.debugger()
  return "debugger"
end

--- Build config URI
---@param configId string
---@return string
function M.config(configId)
  return "config:" .. configId
end

--- Build session URI
---@param sessionId string
---@return string
function M.session(sessionId)
  return "session:" .. sessionId
end

--- Build source URI
--- Source key already contains neoword + path info
---@param key string The source key
---@return string
function M.source(key)
  return "source:" .. key
end

--- Build source binding URI
---@param sessionId string
---@param sourceKey string
---@return string
function M.sourceBinding(sessionId, sourceKey)
  return "sourcebinding:" .. sessionId .. ":" .. sourceKey
end

--- Build thread URI
---@param sessionId string
---@param threadId number
---@return string
function M.thread(sessionId, threadId)
  return "thread:" .. sessionId .. ":" .. threadId
end

--- Build stack URI
---@param sessionId string
---@param threadId number
---@param index number
---@return string
function M.stack(sessionId, threadId, index)
  return "stack:" .. sessionId .. ":" .. threadId .. ":" .. index
end

--- Build frame URI
--- Includes stops to ensure uniqueness when debuggers reuse frameIds between stops
---@param sessionId string
---@param stops number The thread's stop sequence number
---@param frameId number
---@return string
function M.frame(sessionId, stops, frameId)
  return "frame:" .. sessionId .. ":" .. stops .. ":" .. frameId
end

--- Build scope URI
--- Name is free-form (can contain colons)
---@param sessionId string
---@param stops number The thread's stop sequence number
---@param frameId number
---@param name string
---@return string
function M.scope(sessionId, stops, frameId, name)
  return "scope:" .. sessionId .. ":" .. stops .. ":" .. frameId .. ":" .. name
end

--- Build variable URI
--- Name is free-form (can contain colons)
---@param sessionId string
---@param parentVarRef number The parent's variablesReference
---@param name string
---@return string
function M.variable(sessionId, parentVarRef, name)
  return "variable:" .. sessionId .. ":" .. parentVarRef .. ":" .. name
end

--- Build breakpoint URI
--- Location is free-form: path:line:column
---@param path string
---@param line number
---@param column number?
---@return string
function M.breakpoint(path, line, column)
  return "breakpoint:" .. path .. ":" .. line .. ":" .. (column or 0)
end

--- Build breakpoint binding URI
---@param sessionId string
---@param path string
---@param line number
---@param column number?
---@return string
function M.breakpointBinding(sessionId, path, line, column)
  return "bpbinding:" .. sessionId .. ":" .. path .. ":" .. line .. ":" .. (column or 0)
end

--- Build output URI
---@param sessionId string
---@param seq number
---@return string
function M.output(sessionId, seq)
  return "output:" .. sessionId .. ":" .. seq
end

--- Build exception filter URI (global, debugger-scoped)
---@param filterId string
---@return string
function M.exceptionFilter(filterId)
  return "exfilter:" .. filterId
end

--- Build exception filter binding URI (per-session)
---@param sessionId string
---@param filterId string
---@return string
function M.exceptionFilterBinding(sessionId, filterId)
  return "exfilterbind:" .. sessionId .. ":" .. filterId
end

--- Build stdio URI (intermediate node for session outputs)
---@param sessionId string
---@return string
function M.stdio(sessionId)
  return "stdio:" .. sessionId
end

--- Build threads group URI (UI grouping node for session threads)
---@param sessionId string
---@return string
function M.threads(sessionId)
  return "threads:" .. sessionId
end

--- Build breakpoints group URI (UI grouping node for breakpoints)
---@return string
function M.breakpointsGroup()
  return "breakpoints:group"
end

--- Build sessions group URI (UI grouping node for sessions)
---@return string
function M.sessionsGroup()
  return "sessions:group"
end

--- Build targets group URI (UI grouping node for leaf sessions / debug targets)
---@return string
function M.targets()
  return "targets:group"
end

--- Build configs group URI (UI grouping node for Config instances)
---@return string
function M.configsGroup()
  return "configs:group"
end

--- Build exception filters group URI (UI grouping node for exception filters)
---@return string
function M.exceptionFiltersGroup()
  return "exfilters:group"
end

--- Parse URI and return type and components
--- Returns nil if invalid
---@param uri string
---@return { type: string, components: table }?
function M.parse(uri)
  local type_end = uri:find(":")
  if not type_end then
    -- Singleton type (debugger)
    if uri == "debugger" then
      return { type = "debugger", components = {} }
    end
    return nil
  end

  local entity_type = uri:sub(1, type_end - 1)
  local rest = uri:sub(type_end + 1)

  -- Parse based on entity type and fixed component count
  local result = { type = entity_type, components = {} }

  if entity_type == "config" then
    -- config:{configId} - fixed: 1
    result.components.configId = rest
  elseif entity_type == "session" then
    -- session:{sessionId} - fixed: 1
    result.components.sessionId = rest
  elseif entity_type == "source" then
    -- source:{key} - fixed: 0, free-form: key
    result.components.key = rest
  elseif entity_type == "sourcebinding" then
    -- sourcebinding:{sessionId}:{sourceKey} - fixed: 1, free-form: sourceKey
    local sep = rest:find(":")
    if not sep then return nil end
    result.components.sessionId = rest:sub(1, sep - 1)
    result.components.sourceKey = rest:sub(sep + 1)
  elseif entity_type == "thread" then
    -- thread:{sessionId}:{threadId} - fixed: 2
    local parts = vim.split(rest, ":", { plain = true })
    if #parts < 2 then return nil end
    result.components.sessionId = parts[1]
    result.components.threadId = tonumber(parts[2])
  elseif entity_type == "stack" then
    -- stack:{sessionId}:{threadId}:{index} - fixed: 3
    local parts = vim.split(rest, ":", { plain = true })
    if #parts < 3 then return nil end
    result.components.sessionId = parts[1]
    result.components.threadId = tonumber(parts[2])
    result.components.index = tonumber(parts[3])
  elseif entity_type == "frame" then
    -- frame:{sessionId}:{stops}:{frameId} - fixed: 3
    local parts = vim.split(rest, ":", { plain = true })
    if #parts < 3 then return nil end
    result.components.sessionId = parts[1]
    result.components.stops = tonumber(parts[2])
    result.components.frameId = tonumber(parts[3])
  elseif entity_type == "scope" then
    -- scope:{sessionId}:{stops}:{frameId}:{name} - fixed: 3, free-form: name
    local parts = vim.split(rest, ":", { plain = true })
    if #parts < 4 then return nil end
    result.components.sessionId = parts[1]
    result.components.stops = tonumber(parts[2])
    result.components.frameId = tonumber(parts[3])
    -- Name is everything after third colon
    result.components.name = table.concat({ unpack(parts, 4) }, ":")
  elseif entity_type == "variable" then
    -- variable:{sessionId}:{varRef}:{name} - fixed: 2, free-form: name
    local parts = vim.split(rest, ":", { plain = true })
    if #parts < 3 then return nil end
    result.components.sessionId = parts[1]
    result.components.varRef = tonumber(parts[2])
    -- Name is everything after second colon
    result.components.name = table.concat({ unpack(parts, 3) }, ":")
  elseif entity_type == "breakpoint" then
    -- breakpoint:{location} - fixed: 0, free-form: location (path:line:column)
    -- Parse from right: column, line, then path
    local parts = vim.split(rest, ":", { plain = true })
    if #parts < 3 then return nil end
    result.components.column = tonumber(parts[#parts])
    result.components.line = tonumber(parts[#parts - 1])
    result.components.path = table.concat({ unpack(parts, 1, #parts - 2) }, ":")
  elseif entity_type == "bpbinding" then
    -- bpbinding:{sessionId}:{location} - fixed: 1, free-form: location
    local sep = rest:find(":")
    if not sep then return nil end
    result.components.sessionId = rest:sub(1, sep - 1)
    local location = rest:sub(sep + 1)
    -- Parse location from right
    local parts = vim.split(location, ":", { plain = true })
    if #parts < 3 then return nil end
    result.components.column = tonumber(parts[#parts])
    result.components.line = tonumber(parts[#parts - 1])
    result.components.path = table.concat({ unpack(parts, 1, #parts - 2) }, ":")
  elseif entity_type == "output" then
    -- output:{sessionId}:{seq} - fixed: 2
    local parts = vim.split(rest, ":", { plain = true })
    if #parts < 2 then return nil end
    result.components.sessionId = parts[1]
    result.components.seq = tonumber(parts[2])
  elseif entity_type == "exfilter" then
    -- exfilter:{filterId} - global, debugger-scoped
    result.components.filterId = rest
  elseif entity_type == "exfilterbind" then
    -- exfilterbind:{sessionId}:{filterId} - per-session binding
    local sep = rest:find(":")
    if not sep then return nil end
    result.components.sessionId = rest:sub(1, sep - 1)
    result.components.filterId = rest:sub(sep + 1)
  elseif entity_type == "stdio" then
    -- stdio:{sessionId} - fixed: 1
    result.components.sessionId = rest
  elseif entity_type == "threads" then
    -- threads:{sessionId} - fixed: 1
    result.components.sessionId = rest
  else
    return nil
  end

  return result
end

--------------------------------------------------------------------------------
-- Resolution
--------------------------------------------------------------------------------

--- Resolve URI to entity via graph query with filter
---@param debugger table The debugger entity (has _graph)
---@param uri string The URI to resolve
---@return table? entity The resolved entity, or nil
function M.resolve(debugger, uri)
  if uri == "debugger" then
    return debugger
  end

  local entity_type = M.type_of(uri)
  if not entity_type then return nil end

  local graph = debugger._graph
  if not graph then return nil end

  -- Use neograph-native view API with type and filter
  local ok, view = pcall(function()
    return graph:view({
      type = entity_type,
      filters = { { field = "uri", op = "eq", value = uri } },
    }, { immediate = true })
  end)

  if not ok or not view then return nil end

  -- view:items() returns an iterator function in neograph-native
  local entity = nil
  for item in view:items() do
    entity = graph:get(item.id)
    break -- Only need first match
  end

  -- Dispose view to prevent use-after-free crashes when entities are modified
  if view.dispose then
    view:dispose()
  end

  return entity
end

return M
