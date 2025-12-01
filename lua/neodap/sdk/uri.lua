---@class UriModule
---@field parse fun(uri: string): ParsedUri?
---@field build fun(...: string): string
---@field resolve fun(debugger: Debugger, uri: string): Collection
---@field validate fun(uri: string): boolean, string?
---@field encode_segment fun(s: string): string
---@field decode_segment fun(s: string): string

---@class ParsedUri
---@field scheme "dap"|"file"
---@field segments Segment[]   -- All path segments (including root)

---@class Segment
---@field type string
---@field accessor "id"|"index"|nil  -- :id or [n] or nil (for "all" pattern)
---@field value string|number|nil    -- The ID string or index number (nil for "all")

local M = {}

-- =============================================================================
-- SCHEMA
-- =============================================================================

-- Schema defines how each entity type maps to collections and indexes
-- scopes: maps parent type -> index name for filtering
M.schema = {
  session = {
    collection = "sessions",
    id_index = "by_id",
  },
  source = {
    collection = "sources",
    id_index = "by_correlation_key",
  },
  breakpoint = {
    collection = "breakpoints",
    id_index = "by_id",
  },
  filter = {
    collection = "exception_filters",
    id_index = "by_id",
  },
  thread = {
    collection = "threads",
    id_index = "by_id",
    id_is_numeric = true,  -- Thread IDs are numbers
    index_index = "by_index",
    scopes = {
      session = "by_session_id",
    },
  },
  stack = {
    collection = "stacks",
    id_index = "by_sequence",
    id_is_numeric = true,  -- Stack sequences are numbers
    index_index = "by_index",  -- Reactive Signal-based index (0 = latest)
    children_edge = "frames",  -- Edge to child frames
    scopes = {
      session = "by_session_id",
      -- thread scope: when thread is a collection (e.g., thread[0]), use follow(stacks)
      thread = {
        index = "by_thread_id",
        key_fn = function(ctx) return ctx.session .. ":" .. ctx.thread end,
        parent_edge = "stacks",  -- Edge from parent (thread) to this entity (stack)
      },
    },
  },
  frame = {
    collection = "frames",
    id_index = "by_id",
    id_is_numeric = true,  -- Frame IDs are numbers
    index_index = "by_index",
    scopes = {
      session = "by_session_id",
      -- thread scope uses global_id = "session_id:thread_id"
      thread = { index = "by_thread_id", key_fn = function(ctx) return ctx.session .. ":" .. ctx.thread end },
      -- stack scope: when stack is a collection (e.g., stack[0]), use follow(frames)
      stack = {
        index = "by_stack_id",
        key_fn = function(ctx) return string.format("dap:session:%s/thread:%s/stack:%s", ctx.session, ctx.thread, ctx.stack) end,
        parent_edge = "frames",  -- Edge from parent (stack) to this entity (frame)
      },
    },
  },
  scope = {
    collection = "scopes",
    id_index = "by_name",
    index_index = "by_index",
    scopes = {
      session = "by_session_id",
      frame = "by_frame_id",
    },
  },
  variable = {
    collection = "variables",
    id_index = "by_evaluate_name",
    name_index = "by_name",  -- For filtering by variable name
    index_index = "by_index",
    scopes = {
      session = "by_session_id",
      stack = "by_stack_id",
      scope = "by_scope_name",
    },
  },
  binding = {
    collection = "bindings",
    id_index = "by_breakpoint_id",
    scopes = {
      session = "by_session_id",
    },
  },
  ["source-binding"] = {
    collection = "source_bindings",
    id_index = "by_source_correlation_key",
    scopes = {
      session = "by_session_id",
    },
  },
  ["filter-binding"] = {
    collection = "exception_filter_bindings",
    id_index = "by_filter",
    scopes = {
      session = "by_session_id",
    },
  },
  output = {
    collection = "outputs",
    id_index = "by_index",
    index_index = "by_index",
    scopes = {
      session = "by_session_id",
    },
  },
}

-- =============================================================================
-- ENCODING
-- =============================================================================

---Percent-encode special characters in a URI segment
---@param s string
---@return string
function M.encode_segment(s)
  return (s:gsub("[/:%%]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

---Percent-decode a URI segment
---@param s string
---@return string
function M.decode_segment(s)
  return (s:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

-- =============================================================================
-- PARSING
-- =============================================================================

---Parse a segment (type:id, type[n], or bare type)
---@param segment string
---@param is_last boolean Whether this is the last segment (bare type only allowed as last)
---@return Segment?
local function parse_segment(segment, is_last)
  -- Try type:id format
  local type_str, id = segment:match("^([^:%[]+):(.+)$")
  if type_str and id then
    return {
      type = type_str,
      accessor = "id",
      value = M.decode_segment(id),
    }
  end

  -- Try type[n] format
  local type_idx, index = segment:match("^([^:%[]+)%[(%d+)%]$")
  if type_idx and index then
    return {
      type = type_idx,
      accessor = "index",
      value = tonumber(index),
    }
  end

  -- Try bare type (only allowed as last segment) - means "all of this type"
  if is_last then
    local bare_type = segment:match("^([%w%-_]+)$")
    if bare_type then
      return {
        type = bare_type,
        accessor = nil,
        value = nil,
      }
    end
  end

  return nil
end

---Normalize shorthand URIs
---@param uri string
---@return string
function M.normalize(uri)
  -- @frame -> dap:@frame
  if uri:match("^@") then
    return "dap:" .. uri
  end
  return uri
end

---Parse a neodap URI into structured form
---@param uri string
---@return ParsedUri?
function M.parse(uri)
  -- Normalize shorthand first
  uri = M.normalize(uri)

  -- Handle file:// URIs
  if uri:match("^file://") then
    local path = uri:match("^file://(.+)$")
    if not path then
      return nil
    end
    return {
      scheme = "file",
      segments = {
        { type = "source", accessor = "id", value = path }
      },
    }
  end

  -- Handle raw absolute paths (e.g., /path/to/file.py) as local sources
  if uri:match("^/") then
    return {
      scheme = "file",
      segments = {
        { type = "source", accessor = "id", value = uri }
      },
    }
  end

  -- Handle dap: URIs
  if not uri:match("^dap:") then
    return nil
  end

  local path = uri:sub(5) -- Remove "dap:" prefix
  if not path or path == "" then
    return nil
  end

  -- Split into segments by /
  local parts = vim.split(path, "/", { plain = true })
  if #parts == 0 then
    return nil
  end

  -- Parse all segments
  local segments = {}
  for i, part in ipairs(parts) do
    local is_last = (i == #parts)
    local seg = parse_segment(part, is_last)
    if not seg then
      return nil
    end
    table.insert(segments, seg)
  end

  return {
    scheme = "dap",
    segments = segments,
  }
end

-- =============================================================================
-- BUILDING
-- =============================================================================

---Build a URI from type:id pairs
---Example: M.build("session", "fluffy-kitten", "frame", "42")
---Returns: "dap:session:fluffy-kitten/frame:42"
---@param ... string Type and ID pairs
---@return string
function M.build(...)
  local args = { ... }
  if #args < 2 or #args % 2 ~= 0 then
    error("build() requires pairs of (type, id) arguments")
  end

  local parts = {}
  for i = 1, #args, 2 do
    local type_str = args[i]
    local id = args[i + 1]
    table.insert(parts, type_str .. ":" .. M.encode_segment(tostring(id)))
  end

  return "dap:" .. table.concat(parts, "/")
end

---Build a URI segment with index accessor
---Example: M.build_indexed("session", "fluffy-kitten", "frame", 0)
---Returns: "dap:session:fluffy-kitten/frame[0]"
---@param ... string|number Type and value pairs (value can be string ID or number index)
---@return string
function M.build_indexed(...)
  local args = { ... }
  if #args < 2 or #args % 2 ~= 0 then
    error("build_indexed() requires pairs of (type, value) arguments")
  end

  local parts = {}
  for i = 1, #args, 2 do
    local type_str = args[i]
    local value = args[i + 1]
    if type(value) == "number" then
      table.insert(parts, type_str .. "[" .. value .. "]")
    else
      table.insert(parts, type_str .. ":" .. M.encode_segment(tostring(value)))
    end
  end

  return "dap:" .. table.concat(parts, "/")
end

---Build a file:// URI for a local source
---@param path string Absolute file path
---@return string
function M.build_file(path)
  return "file://" .. path
end

-- =============================================================================
-- VALIDATION
-- =============================================================================

---Validate a URI format
---@param uri string
---@return boolean valid
---@return string? error_message
function M.validate(uri)
  if uri:match("^file://") then
    local path = uri:match("^file://(.+)$")
    if not path or path == "" then
      return false, "Invalid file URI: missing path"
    end
    return true
  end

  if not uri:match("^dap:") then
    return false, "Invalid URI scheme: expected 'dap:' or 'file://'"
  end

  local parsed = M.parse(uri)
  if not parsed then
    return false, "Failed to parse URI"
  end

  return true
end

-- =============================================================================
-- RESOLUTION
-- =============================================================================

---Compute the scope key for a given entity type and context
---@param entity_type string
---@param ctx table<string, string|number>
---@return string? scope_key
local function compute_scope_key(entity_type, parent_type, parent_value)
  -- Special handling for composite keys
  if entity_type == "thread" and parent_type == "session" then
    -- Thread global_id is "session_id:thread_id"
    return nil -- Will be handled by by_session_id index
  end
  if entity_type == "stack" and parent_type == "thread" then
    -- Stack uses thread's global_id
    return nil -- Will be handled by by_thread_id index
  end
  return parent_value
end

---Resolve a URI to a collection (always returns collection, possibly filtered)
---@param debugger Debugger
---@param uri string
---@return table collection  -- Filtered collection
---@return string? error
function M.resolve(debugger, uri)
  local parsed = M.parse(uri)
  if not parsed then
    return nil, "Failed to parse URI: " .. uri
  end

  -- Track accumulated context for scoping
  local ctx = {}  -- { session = "xxx", thread = "1", ... }
  local result = nil

  for i, seg in ipairs(parsed.segments) do
    local def = M.schema[seg.type]
    if not def then
      return nil, "Unknown entity type: " .. seg.type
    end

    -- Get the base collection
    local coll = debugger[def.collection]
    if not coll then
      return nil, "Collection not found: " .. def.collection
    end

    -- Apply accumulated scope filters
    -- IMPORTANT: When using follow pattern, we need to apply follow FIRST (from the collection-type scope)
    -- then apply other scopes to the follow result. The order matters!
    if def.scopes then
      -- First pass: find if there's a follow scope (collection-type with parent_edge)
      local follow_scope_type = nil
      local follow_scope_def = nil
      for scope_type, scope_def in pairs(def.scopes) do
        local scope_value = ctx[scope_type]
        if scope_value then
          local is_collection = type(scope_value) == "table" and scope_value.iter and scope_value.on_added
          if is_collection and type(scope_def) == "table" and scope_def.parent_edge then
            follow_scope_type = scope_type
            follow_scope_def = scope_def
            break
          end
        end
      end

      -- If there's a follow scope, apply it first
      if follow_scope_type then
        local scope_value = ctx[follow_scope_type]
        coll = scope_value:follow(follow_scope_def.parent_edge, seg.type)
      end

      -- Second pass: apply non-follow scopes (skip the follow scope)
      for scope_type, scope_def in pairs(def.scopes) do
        if scope_type ~= follow_scope_type then  -- Skip the follow scope we already applied
          local scope_value = ctx[scope_type]
          if scope_value then
            local is_collection = type(scope_value) == "table" and scope_value.iter and scope_value.on_added

            if type(scope_def) == "string" then
              if is_collection then
                -- Collection-based scoping by membership (e.g., stack[0]/variable)
                -- Uses where_in to filter entities whose index matches any source ID
                coll = coll:where_in(scope_def, scope_value)
              else
                coll = coll:where(scope_def, scope_value)
              end
            elseif type(scope_def) == "table" then
              if is_collection then
                if scope_def.parent_edge then
                  -- Already handled in first pass via follow()
                else
                  -- Collection-based scoping by membership (no direct edge)
                  coll = coll:where_in(scope_def.index, scope_value)
                end
              else
                local key = scope_def.key_fn(ctx)
                coll = coll:where(scope_def.index, key)
              end
            end
          end
        end
      end
    end

    -- Apply this segment's filter (or return collection if no value)
    if seg.accessor == nil then
      -- Bare type (e.g., "dap:session") - return the scoped collection
      result = coll
    elseif seg.accessor == "id" then
      local index_name = def.id_index
      if not index_name then
        return nil, "Entity type has no id_index: " .. seg.type
      end
      -- Convert to number if schema indicates numeric ID
      local id_value = seg.value
      if def.id_is_numeric then
        id_value = tonumber(seg.value) or seg.value
      end
      result = coll:where(index_name, id_value)
      -- Add to context for subsequent segments
      ctx[seg.type] = seg.value
    else -- "index"
      local target_index = seg.value

      -- Use index-based filter (reactive via Signal watching)
      local index_name = def.index_index or "by_index"
      result = coll:where(index_name, target_index)

      -- Store the result collection in context for subsequent segments
      -- This enables stack[0]/frame[0] to scope frames by stacks in stack[0] (reactive via follow)
      ctx[seg.type] = result
    end
  end

  return result
end

---Resolve a URI and return the first matching entity (convenience method)
---@param debugger Debugger
---@param uri string
---@return any? entity
---@return string? error
function M.resolve_one(debugger, uri)
  local coll, err = M.resolve(debugger, uri)
  if err then
    return nil, err
  end
  if not coll then
    return nil, "Resolution returned nil"
  end
  -- Get first item from collection
  for item in coll:iter() do
    return item
  end
  return nil
end

-- =============================================================================
-- CONTEXTUAL URI EXPANSION
-- =============================================================================

---Build a context map from a resolved entity
---Walks up the entity hierarchy to extract IDs for session, thread, stack, frame
---Also captures indexes for relative navigation (e.g., @frame+1)
---@param entity table? The resolved entity (Frame, Stack, Thread, or Session)
---@return table<string, string|number> Context map with entity type -> ID and indexes
function M.build_context_map(entity)
  if not entity then return {} end

  local map = {}

  -- Walk up from the entity to build the map
  -- Frame -> Stack -> Thread -> Session
  local current = entity

  -- Frame has .stack
  if current.stack then
    map.frame = current.id
    -- Capture frame index for relative navigation (@frame+1, @frame-1)
    if current.index then
      map.frame_index = current.index:get()
    end
    current = current.stack
  end

  -- Stack has .thread (use sequence for stack ID, as schema uses by_sequence)
  if current.thread then
    map.stack = current.sequence
    map.stack_id = current.id  -- Full stack ID/URI for scoping
    -- Capture stack index for relative navigation (@stack+1, @stack-1)
    if current.index then
      map.stack_index = current.index:get()
    end
    current = current.thread
  end

  -- Thread has .session
  if current.session then
    map.thread = current.id
    current = current.session
  end

  -- Session has .id
  if current.id then
    map.session = current.id
  end

  return map
end

---Expand contextual @ markers in a URI pattern using a context map
---For simple @entity patterns, builds full scoped path (e.g., @stack -> session:.../thread:.../stack:...)
---Supports relative patterns like @frame+1, @frame-1 for stack navigation
---@param pattern string URI pattern with @ markers (e.g., "dap:@session/thread:1" or "@frame" or "@frame+1")
---@param context_map table<string, string|number> Map of entity type -> ID and indexes
---@return string? expanded_uri The expanded URI, or nil if expansion failed
function M.expand_contextual(pattern, context_map)
  -- Normalize shorthand first
  pattern = M.normalize(pattern)

  -- Check for relative patterns like @frame+1, @frame-1, @stack+1, @stack-1
  local entity_type, offset_str = pattern:match("^dap:@([%w%-]+)([%+%-]%d+)$")
  if entity_type and offset_str then
    local offset = tonumber(offset_str)
    return M._expand_relative(entity_type, offset, context_map)
  end

  -- For simple @entity patterns (like dap:@stack), build the full scoped path
  local simple_entity = pattern:match("^dap:@([%w%-]+)$")
  if simple_entity then
    return M._build_scoped_uri(simple_entity, context_map)
  end

  -- For @entity/suffix patterns (like dap:@stack/frame), build scoped path and append suffix
  -- Only match if suffix does NOT start with @ (those are handled by complex pattern substitution)
  local scoped_entity, suffix = pattern:match("^dap:@([%w%-]+)/([^@].*)$")
  if scoped_entity and suffix then
    local scoped_uri = M._build_scoped_uri(scoped_entity, context_map)
    if scoped_uri then
      return scoped_uri .. "/" .. suffix
    end
    return nil
  end

  -- For complex patterns, do simple substitution
  local has_unexpanded = false

  local result = pattern:gsub("@([%w%-]+)", function(et)
    local id = context_map[et]
    if id then
      return et .. ":" .. M.encode_segment(tostring(id))
    end
    has_unexpanded = true
    return "@" .. et
  end)

  if has_unexpanded then
    return nil
  end

  return result
end

---Expand relative index pattern (@frame+1, @frame-1, @stack+1, etc.)
---@param entity_type string  "frame" or "stack"
---@param offset number  The relative offset (+1, -1, etc.)
---@param context_map table<string, string|number>
---@return string? expanded_uri The expanded URI, or nil if expansion failed
function M._expand_relative(entity_type, offset, context_map)
  local index_key = entity_type .. "_index"
  local current_index = context_map[index_key]

  if current_index == nil then
    return nil  -- No index in context
  end

  local target_index = current_index + offset
  if target_index < 0 then
    return nil  -- Out of bounds (can't go above top of stack)
  end

  -- Build scoped URI with index accessor
  if entity_type == "frame" then
    -- Frames are scoped by stack: session/thread/stack/frame[N]
    local stack_uri = M._build_scoped_uri("stack", context_map)
    if not stack_uri then return nil end
    return stack_uri .. "/frame[" .. target_index .. "]"
  elseif entity_type == "stack" then
    -- Stacks are scoped by thread: session/thread/stack[N]
    local thread_uri = M._build_scoped_uri("thread", context_map)
    if not thread_uri then return nil end
    return thread_uri .. "/stack[" .. target_index .. "]"
  end

  return nil
end

---Build a fully scoped URI for an entity type from context
---@param entity_type string The target entity type
---@param context_map table<string, string|number> Context map
---@return string? uri The full URI or nil if missing context
function M._build_scoped_uri(entity_type, context_map)
  -- Define the hierarchy: each type needs its parent types
  local hierarchy = {
    session = { "session" },
    thread = { "session", "thread" },
    stack = { "session", "thread", "stack" },
    frame = { "session", "frame" },  -- Frames are unique per session (skip thread/stack)
  }

  local required = hierarchy[entity_type]
  if not required then
    return nil
  end

  local parts = {}
  for _, t in ipairs(required) do
    local id = context_map[t]
    if not id then
      return nil
    end
    table.insert(parts, t .. ":" .. M.encode_segment(tostring(id)))
  end

  return "dap:" .. table.concat(parts, "/")
end

---Check if a URI pattern contains contextual @ markers
---@param pattern string URI pattern to check
---@return boolean
function M.is_contextual(pattern)
  pattern = M.normalize(pattern)
  return pattern:match("@[%w%-]+") ~= nil
end

---Get the list of contextual markers in a URI pattern
---@param pattern string URI pattern to analyze
---@return string[] List of entity types referenced by @ markers
function M.get_contextual_markers(pattern)
  local markers = {}
  for marker in pattern:gmatch("@([%w%-]+)") do
    table.insert(markers, marker)
  end
  return markers
end

return M
