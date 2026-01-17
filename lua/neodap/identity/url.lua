--- URL: Entity Navigation
---
--- URLs are navigation paths through the entity graph.
--- Formats:
---   Absolute:   /sessions:xotat/threads:1
---   Contextual: @frame/scopes
---   Hybrid:     frame:xotat:42/scopes (URI + path)
---
--- This module provides:
--- - Parsing: URL string → query structure
--- - Resolution: execute query, return entities
--- - Watching: reactive resolution via signals

local uri_module = require("neodap.uri")
local schema = require("neodap.schema")

local M = {}

--------------------------------------------------------------------------------
-- Schema Derivation (computed once at load time)
--------------------------------------------------------------------------------

local edge_to_type  -- edge name → target type
local reference_edges  -- set of edge names that are reference rollups (single result)

local function get_edge_info()
  if edge_to_type then return edge_to_type, reference_edges end
  edge_to_type = {}
  reference_edges = {}
  local schema_def = schema.schema
  -- Flat format: { TypeName = { field = "type" | { type = "edge", ... } | { type = "reference", ... } } }
  for _, type_def in pairs(schema_def) do
    for field_name, field_def in pairs(type_def) do
      if type(field_def) == "table" then
        if field_def.type == "edge" then
          edge_to_type[field_name] = field_def.target
        elseif field_def.type == "reference" then
          -- Reference rollups are now traversable as edges in neograph
          local source_edge_def = type_def[field_def.edge]
          if source_edge_def and source_edge_def.type == "edge" then
            edge_to_type[field_name] = source_edge_def.target
            reference_edges[field_name] = true
          end
        elseif field_def.type == "collection" then
          -- Collection rollups return multiple results
          local source_edge_def = type_def[field_def.edge]
          if source_edge_def and source_edge_def.type == "edge" then
            edge_to_type[field_name] = source_edge_def.target
          end
        end
      end
    end
  end
  return edge_to_type, reference_edges
end

--------------------------------------------------------------------------------
-- Conventions
--------------------------------------------------------------------------------

--- Derive key field from edge name
--- "sessions" → "sessionId", "threads" → "threadId"
local key_field_overrides = {
  scopes = "name",
  variables = "name",
  sources = "path",
  breakpoints = "uri",
}

local function key_field_for(edge_name)
  if key_field_overrides[edge_name] then
    return key_field_overrides[edge_name]
  end
  local singular = edge_name:gsub("s$", "")
  return singular .. "Id"
end

--------------------------------------------------------------------------------
-- Parsing
--------------------------------------------------------------------------------

local function parse_value(str)
  if str == "true" then return true end
  if str == "false" then return false end
  local num = tonumber(str)
  if num then return num end
  local quoted = str:match('^"(.*)"$') or str:match("^'(.*)'$")
  return quoted or str
end

--- Parse a single URL segment: edge:key(filter)[index]
local function parse_segment(str)
  if not str or str == "" then return nil end

  local edge, rest = str:match("^([%w_]+)(.*)$")
  if not edge then return nil end

  local seg = { edge = edge }

  -- Key lookup: /sessions:xotat
  local key = rest:match("^:([^%(%[/]+)")
  if key then
    seg.key = parse_value(key)
    rest = rest:sub(#key + 2)
  end

  -- Filter: /threads(state=stopped)
  local filter_str = rest:match("^%(([^%)]+)%)")
  if filter_str then
    seg.filter = {}
    for field, value in filter_str:gmatch("([%w_]+)=([^,%)]+)") do
      seg.filter[field] = parse_value(value)
    end
    rest = rest:sub(#filter_str + 3)
  end

  -- Index: /sessions[0]
  local idx = rest:match("^%[(%d+)%]")
  if idx then
    seg.index = tonumber(idx)
  end

  return seg
end

--- Parse URL into structured query
---@param url string
---@return table? query { context?, segments[] }
function M.parse(url)
  if not url or url == "" then return nil end

  local query = { segments = {} }

  -- Handle contextual prefix: @frame/scopes
  if url:sub(1, 1) == "@" then
    local first_slash = url:find("/")
    if first_slash then
      query.context = url:sub(1, first_slash - 1)
      url = url:sub(first_slash)
    else
      query.context = url
      return query
    end
  end

  -- Handle special "debugger" URI (no colon)
  if url == "debugger" then
    query.uri = "debugger"
    return query
  end

  -- Handle URI prefix: frame:xotat:42/scopes or frame:xotat:42 (no path)
  -- Note: source and breakpoint URIs contain paths with /, so they're always full URIs
  if url:find(":") and not url:match("^/") then
    local uri_type = url:match("^([^:]+):")
    -- Types whose keys contain / (file paths) - treat entire string as URI
    if uri_type == "source" or uri_type == "sourcebinding" or uri_type == "breakpoint" or uri_type == "bpbinding" then
      query.uri = url
      return query
    end
    -- Other URIs may have path suffix: frame:xotat:42/scopes
    local uri_part, path_part = url:match("^([^/]+)(/.*)$")
    if uri_part and path_part then
      query.uri = uri_part
      url = path_part
    else
      -- URI only, no path
      query.uri = url
      return query
    end
  end

  -- Handle absolute path: /sessions/xotat/threads
  if url:sub(1, 1) == "/" then
    url = url:sub(2)
  end

  -- Parse segments
  if url ~= "" then
    for segment_str in url:gmatch("[^/]+") do
      local seg = parse_segment(segment_str)
      if seg then
        table.insert(query.segments, seg)
      end
    end
  end

  return query
end

--------------------------------------------------------------------------------
-- View Query Building
--------------------------------------------------------------------------------

--- Build edge config from a parsed segment
--- @param seg table Parsed segment { edge, key?, filter?, index? }
--- @param is_intermediate boolean Whether this is an intermediate segment
--- @return table edge_config Edge configuration for view query
local function build_edge_config(seg, is_intermediate)
  local config = {}

  -- All edges need eager = true to auto-expand when parent enters view
  config.eager = true

  -- Intermediate segments are also inline (hidden in results)
  if is_intermediate then
    config.inline = true
  end

  -- Key lookup becomes a filter on the key field
  if seg.key then
    local key_field = key_field_for(seg.edge)
    config.filters = config.filters or {}
    table.insert(config.filters, { field = key_field, value = seg.key })
  end

  -- Explicit property filters
  if seg.filter then
    config.filters = config.filters or {}
    for field, value in pairs(seg.filter) do
      table.insert(config.filters, { field = field, value = value })
    end
  end

  -- Index [N] becomes skip/take cursor
  if seg.index ~= nil then
    if seg.index > 0 then
      config.skip = seg.index
    end
    config.take = 1
  end

  return config
end

--- Build view query from parsed URL segments
--- Compiles URL path to neograph view query with inline/eager for intermediates
--- Root type is always visible (filtered out by wrapper if URL has segments)
--- Supports rollup resolution: "stack" on Thread → uses "stacks" edge with rollup config
--- @param segments table Array of parsed segments
--- @param root_type string Root entity type (default: "Debugger")
--- @param root_uri string? Optional root entity URI to filter view to specific entity
--- @return table? query View query definition
function M.build_view_query(segments, root_type, root_uri)
  if #segments == 0 then
    local query = { type = root_type or "Debugger" }
    if root_uri then query.filters = {{ field = "uri", value = root_uri }} end
    return query
  end

  -- Get edge type mapping
  local types = get_edge_info()

  -- Build the query starting from root type
  local query = { type = root_type or "Debugger" }
  if root_uri then query.filters = {{ field = "uri", value = root_uri }} end

  -- Build nested edge chain
  local current = query
  local current_type = root_type or "Debugger"

  for i, seg in ipairs(segments) do
    local is_intermediate = (i < #segments)
    local edge_config = build_edge_config(seg, is_intermediate)

    current.edges = current.edges or {}
    current.edges[seg.edge] = edge_config
    current = edge_config

    -- Update current type for next iteration
    current_type = types[seg.edge] or current_type
  end

  return query
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Resolve URL to entity/entities (immediate)
--- Uses watch() internally for consistent behavior with client-side indexing
---@param debugger table The debugger instance
---@param url string The URL to resolve
---@return table|table[]|nil result Entity, array of entities, or nil
function M.query(debugger, url)
  local watched = M.watch(debugger, url)
  if not watched then return nil end
  local result = watched:get()
  -- Dispose the watched wrapper to prevent use-after-free crashes
  if watched.dispose then watched:dispose() end
  return result
end

--- Check if URL path returns a single result
--- Returns true if:
--- 1. Final segment has index (e.g., /sessions[0]) - extracts from array
--- 2. Final segment has key filter (e.g., /sessions(uri="...")) - filters to one
--- 3. ALL segments are reference rollups (e.g., /parent/thread) - no collections
--- @param segments table Array of parsed segments
--- @return boolean True if result should be single entity (not array)
local function returns_single_result(segments)
  if #segments == 0 then return false end
  local final = segments[#segments]
  -- Index or key on final segment extracts single from flattened array
  if final.index ~= nil or final.key ~= nil then return true end
  -- Check if ALL segments are reference rollups (no collection traversals)
  local _, refs = get_edge_info()
  for _, seg in ipairs(segments) do
    -- Skip segments with index/key - they constrain to single
    if seg.index == nil and seg.key == nil then
      if not refs[seg.edge] then
        return false
      end
    end
  end
  return true
end

--- Watch URL reactively (returns signal)
--- Compiles URL to neograph view query for reactive resolution
---@param debugger table The debugger instance
---@param url string The URL to watch
---@param wrappers table The wrappers module
---@return table? signal Signal with :get(), :onChange()
function M.watch(debugger, url, wrappers)
  local parsed = M.parse(url)
  if not parsed then return nil end

  local graph = debugger._graph
  if not graph then return nil end

  -- Fallback if no wrappers provided
  if not wrappers then
    wrappers = require("neodap.identity.wrappers")
  end

  -- Contextual URLs (@frame, @session, etc): use expand() for reactivity
  if parsed.context then
    local scoped = require("neodap.scoped")
    return scoped.flatMap(debugger.ctx:expand(url), function(expanded)
      if not expanded then return wrappers.empty(false) end
      -- Recurse with concrete URL (no @markers)
      return M.watch(debugger, expanded, wrappers)
    end)
  end

  -- Non-contextual: resolve URI or use debugger root
  local root, root_type
  if parsed.uri then
    root = uri_module.resolve(debugger, parsed.uri)
    if root then root_type = root._type end
  else
    root = debugger
    root_type = "Debugger"
  end

  -- No segments = return static wrapper for root
  if #parsed.segments == 0 then
    return wrappers.static(root)
  end

  -- Has path segments - build view query
  if not root then return nil end

  local single_result = returns_single_result(parsed.segments)
  local final = parsed.segments[#parsed.segments]
  local key_lookup = final and final.key ~= nil

  local root_uri = parsed.uri and root.uri and root.uri:get() or nil
  local query = M.build_view_query(parsed.segments, root_type, root_uri)
  if not query then
    error("Failed to build view query for URL: " .. url)
  end

  -- Check if edge exists - return nil for invalid edges
  if query.edges then
    for edge_name, _ in pairs(query.edges) do
      local key = query.type .. ":" .. edge_name
      if not graph.edge_defs[key] then
        return nil
      end
    end
  end

  -- Create view from query - let errors propagate
  local view = graph:view(query, { limit = 1000 })

  return wrappers.watched(view, key_lookup, single_result)
end

return M
