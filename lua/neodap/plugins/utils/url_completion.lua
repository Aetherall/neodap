-- URL completion utility for neodap
-- Provides schema-aware and graph-aware completions for URL queries
--
-- Completions are derived from:
-- 1. Schema: edges, rollups, properties per entity type
-- 2. Live graph: actual entity keys (session IDs, thread IDs, etc.)

local schema = require("neodap.schema")

local M = {}

--------------------------------------------------------------------------------
-- Schema Info (computed once)
--------------------------------------------------------------------------------

local type_info    -- type_name → { edges, rollups, properties }
local edge_to_type -- edge_name → target_type

local function ensure_schema_info()
  if type_info then return end
  type_info = {}
  edge_to_type = {}

  for _, t in ipairs(schema.schema.types) do
    local info = { edges = {}, rollups = {}, properties = {} }

    for _, e in ipairs(t.edges or {}) do
      info.edges[e.name] = { target = e.target, indexes = e.indexes }
      edge_to_type[e.name] = e.target
    end

    for _, r in ipairs(t.rollups or {}) do
      info.rollups[r.name] = r
      -- Rollups that reference edges inherit target type
      if r.edge then
        local edge_target = info.edges[r.edge] and info.edges[r.edge].target
        if edge_target then
          edge_to_type[r.name] = edge_target
        end
      end
    end

    for _, p in ipairs(t.properties or {}) do
      info.properties[p.name] = p.type
    end

    type_info[t.name] = info
  end
end

--------------------------------------------------------------------------------
-- Context Markers
--------------------------------------------------------------------------------

-- Map context markers to entity types
local context_types = {
  ["@session"] = "Session",
  ["@thread"] = "Thread",
  ["@stack"] = "Stack",
  ["@frame"] = "Frame",
  ["@scope"] = "Scope",
  ["@variable"] = "Variable",
  ["@source"] = "Source",
  ["@breakpoint"] = "Breakpoint",
}

-- Context markers for completion
local context_markers = {
  "@session",
  "@thread",
  "@stack",
  "@frame",
  "@scope",
}

--------------------------------------------------------------------------------
-- URL Parsing (simplified for completion)
--------------------------------------------------------------------------------

--- Parse a partial URL to extract segments
---@param partial string Partial URL
---@return table parsed { context?, segments[], trailing_slash?, trailing_colon?, trailing_paren? }
local function parse_partial(partial)
  if not partial or partial == "" then
    return { segments = {} }
  end

  local result = { segments = {} }

  -- Check for context prefix
  if partial:sub(1, 1) == "@" then
    local slash_pos = partial:find("/")
    if slash_pos then
      result.context = partial:sub(1, slash_pos - 1)
      partial = partial:sub(slash_pos + 1)
    else
      -- Still typing context marker
      result.partial_context = partial
      return result
    end
  end

  -- Check trailing characters before parsing segments
  result.trailing_slash = partial:sub(-1) == "/"
  result.trailing_colon = partial:sub(-1) == ":"
  result.trailing_paren = partial:sub(-1) == "("

  -- Remove leading slash for absolute URLs
  if partial:sub(1, 1) == "/" then
    partial = partial:sub(2)
  end

  -- Split by / and parse each segment
  for segment_str in partial:gmatch("[^/]+") do
    local seg = {}

    -- Extract edge name (before : or ()
    local edge = segment_str:match("^([%w_]+)")
    if edge then
      seg.edge = edge

      -- Check for key: edge:key
      local key = segment_str:match("^[%w_]+:([^%(]+)")
      if key then
        seg.key = key
      end

      -- Check for filter: edge(prop=val)
      local filter = segment_str:match("%(([^%)]+)%)")
      if filter then
        seg.filter = filter
      end

      -- Check for index: edge[n]
      local index = segment_str:match("%[(%d+)%]")
      if index then
        seg.index = tonumber(index)
      end

      table.insert(result.segments, seg)
    end
  end

  return result
end

--- Determine entity type at current position in URL
---@param partial string Partial URL
---@return string type_name Current entity type
---@return string? last_edge Last edge name (for key completions)
local function current_type_from_url(partial)
  ensure_schema_info()

  local parsed = parse_partial(partial)
  local current = "Debugger"
  local last_edge = nil

  -- Handle context prefix
  if parsed.context then
    current = context_types[parsed.context] or "Debugger"
  end

  -- Walk segments to find final type
  for _, seg in ipairs(parsed.segments or {}) do
    last_edge = seg.edge
    local target = edge_to_type[seg.edge]
    if target then
      current = target
    end
  end

  return current, last_edge
end

--------------------------------------------------------------------------------
-- Completion Generators
--------------------------------------------------------------------------------

--- Get structure completions (edges + rollups) for a type
---@param type_name string Entity type name
---@return string[] completions Edge and rollup names
function M.structure_completions(type_name)
  ensure_schema_info()
  local info = type_info[type_name]
  if not info then return {} end

  local completions = {}
  local seen = {}

  -- Add edge names (plural: sessions, threads, etc.)
  for name, _ in pairs(info.edges) do
    if not seen[name] then
      table.insert(completions, name)
      seen[name] = true
    end
  end

  -- Add rollup names (singular/computed: firstSession, stoppedThreads, etc.)
  for name, _ in pairs(info.rollups) do
    if not seen[name] then
      table.insert(completions, name)
      seen[name] = true
    end
  end

  table.sort(completions)
  return completions
end

--- Get filter property completions for a type
---@param type_name string Entity type name
---@return string[] completions Property filter suggestions
function M.filter_completions(type_name)
  ensure_schema_info()
  local info = type_info[type_name]
  if not info then return {} end

  local completions = {}

  for name, ptype in pairs(info.properties) do
    -- Skip uri (internal)
    if name ~= "uri" then
      if ptype == "bool" then
        table.insert(completions, name .. "=true")
        table.insert(completions, name .. "=false")
      else
        table.insert(completions, name .. "=")
      end
    end
  end

  table.sort(completions)
  return completions
end

--- Get key completions from live graph
---@param debugger table Debugger instance
---@param source_type string Source entity type
---@param edge_name string Edge name to get keys for
---@return string[] completions Entity keys
function M.key_completions(debugger, source_type, edge_name)
  ensure_schema_info()

  local completions = {}

  -- Determine key field based on edge name
  -- Convention: sessions → sessionId, threads → threadId
  local key_field_overrides = {
    scopes = "name",
    variables = "name",
    sources = "path",
    breakpoints = "line",
  }

  local key_field = key_field_overrides[edge_name]
  if not key_field then
    local singular = edge_name:gsub("s$", "")
    key_field = singular .. "Id"
  end

  -- Get entities based on source type and edge
  local entities = {}

  if source_type == "Debugger" then
    if edge_name == "sessions" or edge_name == "rootSessions" then
      for session in debugger.sessions:iter() do
        table.insert(entities, session)
      end
    elseif edge_name == "sources" then
      for source in debugger.sources:iter() do
        table.insert(entities, source)
      end
    elseif edge_name == "breakpoints" then
      for bp in debugger.breakpoints:iter() do
        table.insert(entities, bp)
      end
    end
  elseif source_type == "Session" then
    local session = debugger.ctx.session:get()
    if session then
      if edge_name == "threads" then
        for thread in session.threads:iter() do
          table.insert(entities, thread)
        end
      elseif edge_name == "children" then
        for child in session.children:iter() do
          table.insert(entities, child)
        end
      end
    end
  elseif source_type == "Thread" then
    local thread = debugger.ctx.thread:get()
    if thread then
      if edge_name == "stacks" then
        for stack in thread.stacks:iter() do
          table.insert(entities, stack)
        end
      end
    end
  elseif source_type == "Stack" then
    local frame = debugger.ctx.frame:get()
    local stack = frame and frame.stack:get()
    if stack then
      if edge_name == "frames" then
        for frame in stack.frames:iter() do
          table.insert(entities, frame)
        end
      end
    end
  elseif source_type == "Frame" then
    local frame = debugger.ctx.frame:get()
    if frame then
      if edge_name == "scopes" then
        for scope in frame.scopes:iter() do
          table.insert(entities, scope)
        end
      end
    end
  end

  -- Extract key values
  for _, entity in ipairs(entities) do
    local signal = entity[key_field]
    if signal and signal.get then
      local value = signal:get()
      if value ~= nil then
        table.insert(completions, tostring(value))
      end
    end
  end

  return completions
end

--------------------------------------------------------------------------------
-- Main Completion Function
--------------------------------------------------------------------------------

--- Complete a partial URL
---@param debugger table Debugger instance
---@param partial string Partial URL being typed
---@return string[] completions Completion candidates
function M.complete(debugger, partial)
  ensure_schema_info()

  partial = partial or ""

  -- Handle empty input: offer context markers and root edges
  if partial == "" then
    local completions = {}
    for _, marker in ipairs(context_markers) do
      table.insert(completions, marker)
    end
    for _, edge in ipairs(M.structure_completions("Debugger")) do
      table.insert(completions, edge)
    end
    return completions
  end

  local parsed = parse_partial(partial)

  -- Completing context marker: @ses...
  if parsed.partial_context then
    return vim.tbl_filter(function(m)
      return m:match("^" .. vim.pesc(parsed.partial_context))
    end, context_markers)
  end

  -- Determine current position
  local current_type, last_edge = current_type_from_url(partial)

  -- After slash: complete with edges/rollups of current type
  if parsed.trailing_slash then
    return M.structure_completions(current_type)
  end

  -- After colon: complete with entity keys from graph
  if parsed.trailing_colon and last_edge then
    -- Need to get the SOURCE type (before traversing last edge)
    local source_type = "Debugger"
    if parsed.context then
      source_type = context_types[parsed.context] or "Debugger"
    end
    -- Walk all but last segment
    for i = 1, #parsed.segments - 1 do
      local target = edge_to_type[parsed.segments[i].edge]
      if target then source_type = target end
    end
    return M.key_completions(debugger, source_type, last_edge)
  end

  -- After open paren: complete with filter properties
  if parsed.trailing_paren and last_edge then
    local target = edge_to_type[last_edge]
    if target then
      return M.filter_completions(target)
    end
  end

  -- Default: partial edge/rollup name completion
  -- Find what's being typed after the last /
  local typing = partial:match("/([^/]*)$") or partial:match("^@[^/]+/(.*)$") or partial

  -- Get source type for completions
  local source_type = "Debugger"
  if parsed.context then
    source_type = context_types[parsed.context] or "Debugger"
  end
  for i = 1, math.max(0, #parsed.segments - 1) do
    local target = edge_to_type[parsed.segments[i].edge]
    if target then source_type = target end
  end

  local candidates = M.structure_completions(source_type)
  return vim.tbl_filter(function(c)
    return c:match("^" .. vim.pesc(typing))
  end, candidates)
end

--------------------------------------------------------------------------------
-- Command Completion Helper
--------------------------------------------------------------------------------

--- Create a completion function for use with nvim_create_user_command
---@param debugger table Debugger instance
---@param cmd_name string Command name to strip from cmdline
---@return function completion_fn
function M.create_completer(debugger, cmd_name)
  return function(arglead, cmdline, _cursorpos)
    -- Extract the URL portion from the command line
    local pattern = cmd_name .. "%s+(.*)$"
    local partial = cmdline:match(pattern) or ""
    return M.complete(debugger, partial)
  end
end

return M
