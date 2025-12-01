---@diagnostic disable: invisible
-- =============================================================================
-- EntityStore: Unified Graph Store for Reactive Entities
-- =============================================================================
--
-- A graph-based store that manages entities and their relationships with:
-- - Flat entity storage with type indexing
-- - Explicit edge representation (outgoing + reverse)
-- - Reactive indexes (supports Signal values)
-- - Graph traversal (BFS, DFS, ancestors, descendants)
-- - Tree visualization support
-- - Cascade disposal via parent edges
--

local neostate = require("neostate")

-- =============================================================================
-- Path-Aware Traversal Helpers
-- =============================================================================

---Derive a key from an entity for path building
---@param entity table The entity object
---@param uri string The entity URI
---@return string The key segment
local function derive_key(entity, uri)
  if entity.key then return entity.key end
  return uri:match("^%w+:(.+)$") or uri
end

---Build a composite virtual URI from path keys and current key
---@param pathkeys string[] Ancestor keys
---@param current_key string Current entity key
---@return string Virtual URI
local function build_virtual_uri(pathkeys, current_key)
  if #pathkeys == 0 then return current_key end
  return table.concat(pathkeys, "/") .. "/" .. current_key
end

---Check if a URI is already in the path (cycle detection) - O(n)
---@param path string[] Array of ancestor URIs
---@param uri string URI to check
---@return boolean True if uri is in path
local function is_in_path(path, uri)
  for _, p in ipairs(path) do
    if p == uri then return true end
  end
  return false
end

-- =============================================================================
-- Path with Set (O(1) containment check)
-- =============================================================================
-- A path structure that maintains both array (for order) and set (for O(1) lookup)

---@class PathWithSet
---@field arr string[] Ordered array of URIs
---@field set table<string, boolean> Set for O(1) containment check

---Create an empty path with set
---@return PathWithSet
local function empty_path()
  return { arr = {}, set = {} }
end

---Append to path, returning new path with both arr and set updated (immutable)
---@param path PathWithSet Path structure
---@param uri string URI to append
---@return PathWithSet New path structure
local function path_append(path, uri)
  local new_arr = {}
  for i, v in ipairs(path.arr) do
    new_arr[i] = v
  end
  new_arr[#new_arr + 1] = uri
  local new_set = {}
  for k in pairs(path.set) do new_set[k] = true end
  new_set[uri] = true
  return { arr = new_arr, set = new_set }
end

---Check if path contains a URI (O(1))
---@param path PathWithSet Path structure
---@param uri string URI to check
---@return boolean
local function path_contains(path, uri)
  return path.set[uri] == true
end

---Append a value to an array, returning a new array (immutable)
---@param arr any[] Source array
---@param value any Value to append
---@return any[] New array with value appended
local function append(arr, value)
  local result = {}
  for i, v in ipairs(arr) do
    result[i] = v
  end
  result[#result + 1] = value
  return result
end

---Create a wrapper object with _virtual metadata as its own Disposable
---The wrapper's lifecycle is managed by the Collection it's added to
---@param entity table The real entity
---@param virtual_data table The _virtual metadata
---@return table Wrapper Disposable with metatable proxy to entity
local function create_wrapper(entity, virtual_data)
  local wrapper = neostate.Disposable({ _virtual = virtual_data }, nil, "Wrapper:" .. virtual_data.uri)
  setmetatable(wrapper, { __index = entity })
  return wrapper
end

---Create filter/prune context from traversal item
---Handles both PathWithSet (BFS) and plain array (DFS) for item.path
---@param item table Traversal item with path info
---@param key string? Entity key for building virtual URI
---@return table Context for filter/prune functions
local function create_context(item, key)
  -- Handle both PathWithSet and plain array for path
  local path_arr = item.path.arr or item.path
  return {
    path = path_arr,
    pathkeys = item.pathkeys,
    depth = item.depth,
    parent = path_arr[#path_arr],
    uri = key and build_virtual_uri(item.pathkeys, key) or nil,
  }
end

---Compute filtered context for children based on whether current node passes filter
---@param item table Current traversal item
---@param passes boolean Whether current node passes filter
---@param uri string Current entity URI
---@param key string Current entity key
---@return table Child filtered context
local function compute_child_filtered(item, passes, uri, key)
  if passes then
    return {
      path = append(item.filtered_path, uri),
      pathkeys = append(item.filtered_pathkeys, key),
      depth = item.filtered_depth + 1,
      parent = uri,
    }
  else
    return {
      path = item.filtered_path,
      pathkeys = item.filtered_pathkeys,
      depth = item.filtered_depth,
      parent = item.filtered_parent,
    }
  end
end

---@class Edge
---@field type string Edge type (e.g., "parent", "source", "session")
---@field to string Target entity URI

---@class Index
---@field getter function(entity) -> value | Signal
---@field map table<any, table<string, boolean>> key -> set of URIs

---@class EntityStore
---@field _entities table<string, table> URI -> entity (must have .uri and ._type fields)
---@field _types table<string, table<string, boolean>> type -> set of URIs
---@field _edges table<string, Edge[]> from_uri -> outgoing edges
---@field _reverse table<string, Edge[]> to_uri -> incoming edges
---@field _indexes table<string, Index> "type:name" -> index
---@field _type_listeners table<string, function[]> type -> addition listeners
---@field _removal_listeners table<string, function[]> type -> removal listeners
---@field _entity_cleanups table<string, function[]> URI -> cleanup functions
local EntityStore = {}
EntityStore.__index = EntityStore

-- =============================================================================
-- Constructor
-- =============================================================================

---Create a new EntityStore
---@param debug_name string? Optional debug name
---@return EntityStore
function EntityStore.new(debug_name)
  local self = setmetatable({}, EntityStore)

  -- Apply Disposable trait
  neostate.Disposable(self, nil, debug_name or "EntityStore")

  -- Entity storage
  self._entities = {}
  self._types = {}

  -- Edge storage
  self._edges = {}
  self._reverse = {}

  -- Sibling linked list for O(1) traversal from any child
  -- Structure: _sibling_links[parent_uri][edge_type] = {
  --   head = first_child_uri,
  --   tail = last_child_uri,
  --   nodes = { [child_uri] = { prev = uri|nil, next = uri|nil } }
  -- }
  self._sibling_links = {}

  -- Index storage
  self._indexes = {}

  -- Listeners
  self._type_listeners = {}
  self._removal_listeners = {}
  self._global_add_listeners = {} -- listeners for all entity additions
  self._global_remove_listeners = {} -- listeners for all entity removals
  self._edge_add_listeners = {} -- edge_type -> listeners
  self._edge_remove_listeners = {} -- edge_type -> listeners

  -- Per-entity cleanups (for signal watchers, etc.)
  self._entity_cleanups = {}

  -- Query cache for Views (ref-counted, shared across views with same query)
  self._query_cache = {}

  return self
end

-- =============================================================================
-- Query Cache Management (for Views)
-- =============================================================================

---Generate canonical cache key from query parameters
---@param entity_type string
---@param filters table[] Array of {index, key} tuples
---@return string Cache key
function EntityStore:_make_cache_key(entity_type, filters)
  if not filters or #filters == 0 then
    return entity_type .. ":"
  end

  -- Sort filters by index name for canonical ordering
  local parts = {}
  for _, f in ipairs(filters) do
    table.insert(parts, f.index .. "=" .. tostring(f.key))
  end
  table.sort(parts)

  return entity_type .. ":" .. table.concat(parts, "|")
end

---Get or create a query cache entry
---@param entity_type string
---@param filters table[] Array of {index, key} tuples
---@return string Cache key
function EntityStore:_get_or_create_cache(entity_type, filters)
  local cache_key = self:_make_cache_key(entity_type, filters)

  local cache = self._query_cache[cache_key]
  if cache then
    cache.ref_count = cache.ref_count + 1
    return cache_key
  end

  -- Create new cache entry
  cache = {
    uris = {},
    ref_count = 1,
    listeners = { add = {}, remove = {} },
    query = {
      entity_type = entity_type,
      filters = filters or {},
    },
  }

  -- Populate cache from indexes
  self:_populate_cache(cache)

  self._query_cache[cache_key] = cache
  return cache_key
end

---Release a cache reference (decrement ref count, free if zero)
---@param cache_key string
function EntityStore:_release_cache(cache_key)
  local cache = self._query_cache[cache_key]
  if not cache then return end

  cache.ref_count = cache.ref_count - 1

  if cache.ref_count <= 0 then
    self._query_cache[cache_key] = nil
  end
end

---Populate cache with entities matching query
---@param cache table Cache entry
function EntityStore:_populate_cache(cache)
  local entity_type = cache.query.entity_type
  local filters = cache.query.filters

  if #filters == 0 then
    -- No filters - include all entities of type
    local type_set = self._types[entity_type] or {}
    for uri in pairs(type_set) do
      cache.uris[uri] = true
    end
    return
  end

  -- Find smallest filter set for efficiency
  local smallest_set, smallest_size = nil, math.huge
  for _, filter in ipairs(filters) do
    local index = self._indexes[filter.index]
    if index then
      local uri_set = index.map[filter.key] or {}
      local size = 0
      for _ in pairs(uri_set) do size = size + 1 end
      if size < smallest_size then
        smallest_size, smallest_set = size, uri_set
      end
    end
  end

  if not smallest_set then return end

  -- Iterate smallest set, check all filters
  for uri in pairs(smallest_set) do
    local entity = self._entities[uri]
    if entity and self:_entity_matches_query(entity, cache.query) then
      cache.uris[uri] = true
    end
  end
end

---Check if entity matches all query filters
---@param entity table
---@param query table Query definition with entity_type and filters
---@return boolean
function EntityStore:_entity_matches_query(entity, query)
  -- Check entity type
  if entity._type ~= query.entity_type then
    return false
  end

  -- Check all filters
  for _, filter in ipairs(query.filters) do
    local index = self._indexes[filter.index]
    if not index then return false end

    local val = index.getter(entity)
    -- Unwrap Signal values
    if type(val) == "table" and val.get then
      val = val:get()
    end

    if val ~= filter.key then
      return false
    end
  end

  return true
end

---Update all relevant caches when entity is added
---@param entity table
---@param entity_type string
function EntityStore:_update_caches_on_add(entity, entity_type)
  for _, cache in pairs(self._query_cache) do
    if cache.query.entity_type == entity_type then
      if self:_entity_matches_query(entity, cache.query) then
        cache.uris[entity.uri] = true
        for _, fn in ipairs(cache.listeners.add) do
          pcall(fn, entity)
        end
      end
    end
  end
end

---Update all relevant caches when entity is removed
---@param entity table
function EntityStore:_update_caches_on_remove(entity)
  for _, cache in pairs(self._query_cache) do
    if cache.uris[entity.uri] then
      cache.uris[entity.uri] = nil
      for _, fn in ipairs(cache.listeners.remove) do
        pcall(fn, entity)
      end
    end
  end
end

---Update caches when index value changes
---@param entity table
---@param index_name string
---@param old_key any
---@param new_key any
function EntityStore:_update_caches_on_index_change(entity, index_name, old_key, new_key)
  for _, cache in pairs(self._query_cache) do
    -- Check if this cache uses the changed index
    for _, filter in ipairs(cache.query.filters) do
      if filter.index == index_name then
        local was_in = cache.uris[entity.uri]
        local matches_now = self:_entity_matches_query(entity, cache.query)

        if was_in and not matches_now then
          -- Entity no longer matches - remove from cache
          cache.uris[entity.uri] = nil
          for _, fn in ipairs(cache.listeners.remove) do
            pcall(fn, entity)
          end
        elseif not was_in and matches_now then
          -- Entity now matches - add to cache
          cache.uris[entity.uri] = true
          for _, fn in ipairs(cache.listeners.add) do
            pcall(fn, entity)
          end
        end
        break -- Only need to check once per cache
      end
    end
  end
end

---Create a View for querying entities
---@param entity_type string Entity type to query
---@return View
function EntityStore:view(entity_type)
  local View = require("neostate.view")
  local view = View.new(self, entity_type, {}, self._debug_name .. ":view:" .. entity_type)
  view:set_parent(self)
  return view
end

-- =============================================================================
-- Entity Management
-- =============================================================================

---Add an entity to the store
---@param entity table The entity object (must have .uri field)
---@param entity_type string The entity type name
---@param edges Edge[]? Optional edges to create
---@return table The entity (for chaining)
function EntityStore:add(entity, entity_type, edges)
  local uri = entity.uri
  if not uri then
    error("[EntityStore] Entity must have a .uri field")
  end

  if self._entities[uri] then
    error("[EntityStore] Entity already exists: " .. uri)
  end

  -- Set type on entity so it's self-describing
  entity._type = entity_type

  -- Store entity directly
  self._entities[uri] = entity

  -- Add to type index
  if not self._types[entity_type] then
    self._types[entity_type] = {}
  end
  self._types[entity_type][uri] = true

  -- Initialize edge storage
  self._edges[uri] = {}
  self._reverse[uri] = {}
  self._entity_cleanups[uri] = {}

  -- Add edges
  if edges then
    for _, edge in ipairs(edges) do
      self:add_edge(uri, edge.type, edge.to)
    end
  end

  -- Index entity
  self:_index_entity(uri, entity, entity_type)

  -- Fire addition listeners
  self:_fire_addition(entity_type, entity)

  -- Update query caches (for Views)
  self:_update_caches_on_add(entity, entity_type)

  return entity
end

---Get an entity by URI
---@param uri string The entity URI
---@return table? The entity, or nil if not found
function EntityStore:get(uri)
  return self._entities[uri]
end

---Check if an entity exists
---@param uri string The entity URI
---@return boolean
function EntityStore:has(uri)
  return self._entities[uri] ~= nil
end

---Get entity type
---@param uri string The entity URI
---@return string? The entity type, or nil if not found
function EntityStore:type_of(uri)
  local entity = self._entities[uri]
  if entity then
    return entity._type
  end
  return nil
end

---Get all entities of a type (returns reactive Collection)
---@param entity_type string The entity type
---@return table Collection of entities
function EntityStore:of_type(entity_type)
  local collection = neostate.Collection(self._debug_name .. ":" .. entity_type)
  collection:set_parent(self)

  -- Populate with existing entities
  local type_set = self._types[entity_type] or {}
  for uri in pairs(type_set) do
    local entity = self._entities[uri]
    if entity then
      collection:adopt(entity)
    end
  end

  -- Subscribe to future additions
  local unsub_add = self:on_added(entity_type, function(entity)
    collection:adopt(entity)
  end)

  -- Subscribe to removals
  local unsub_remove = self:on_removed(entity_type, function(entity)
    collection:delete(function(e) return e.uri == entity.uri end)
  end)

  collection:on_dispose(unsub_add)
  collection:on_dispose(unsub_remove)

  return collection
end

---Count entities of a type
---@param entity_type string? Optional type filter
---@return number
function EntityStore:count(entity_type)
  if entity_type then
    local type_set = self._types[entity_type] or {}
    local count = 0
    for _ in pairs(type_set) do
      count = count + 1
    end
    return count
  else
    local count = 0
    for _ in pairs(self._entities) do
      count = count + 1
    end
    return count
  end
end

-- =============================================================================
-- Edge Management
-- =============================================================================

---Add an edge between entities
---@param from_uri string Source entity URI
---@param edge_type string Edge type
---@param to_uri string Target entity URI
function EntityStore:add_edge(from_uri, edge_type, to_uri)
  -- Validate source exists
  if not self._entities[from_uri] then
    error("[EntityStore] Source entity not found: " .. from_uri)
  end

  -- Create edge
  local edge = { type = edge_type, to = to_uri }
  table.insert(self._edges[from_uri], edge)

  -- Create reverse edge
  if not self._reverse[to_uri] then
    self._reverse[to_uri] = {}
  end
  table.insert(self._reverse[to_uri], { type = edge_type, from = from_uri })

  -- Update sibling linked list for O(1) traversal
  if not self._sibling_links[to_uri] then
    self._sibling_links[to_uri] = {}
  end
  if not self._sibling_links[to_uri][edge_type] then
    self._sibling_links[to_uri][edge_type] = { head = nil, tail = nil, nodes = {} }
  end
  local list = self._sibling_links[to_uri][edge_type]
  local node = { prev = list.tail, next = nil }
  list.nodes[from_uri] = node
  if list.tail then
    list.nodes[list.tail].next = from_uri
  end
  list.tail = from_uri
  if not list.head then
    list.head = from_uri
  end

  -- Fire edge add listeners
  self:_fire_edge_add(edge_type, from_uri, to_uri)
end

---Add an edge at the HEAD of the sibling list (newer items appear first)
---@param from_uri string Source entity URI
---@param edge_type string Edge type
---@param to_uri string Target entity URI
function EntityStore:prepend_edge(from_uri, edge_type, to_uri)
  -- Validate source exists
  if not self._entities[from_uri] then
    error("[EntityStore] Source entity not found: " .. from_uri)
  end

  -- Create edge (prepend to edges array)
  local edge = { type = edge_type, to = to_uri }
  table.insert(self._edges[from_uri], 1, edge)

  -- Create reverse edge (prepend)
  if not self._reverse[to_uri] then
    self._reverse[to_uri] = {}
  end
  table.insert(self._reverse[to_uri], 1, { type = edge_type, from = from_uri })

  -- Update sibling linked list - insert at HEAD
  if not self._sibling_links[to_uri] then
    self._sibling_links[to_uri] = {}
  end
  if not self._sibling_links[to_uri][edge_type] then
    self._sibling_links[to_uri][edge_type] = { head = nil, tail = nil, nodes = {} }
  end
  local list = self._sibling_links[to_uri][edge_type]
  local node = { prev = nil, next = list.head }
  list.nodes[from_uri] = node
  if list.head then
    list.nodes[list.head].prev = from_uri
  end
  list.head = from_uri
  if not list.tail then
    list.tail = from_uri
  end

  -- Fire edge add listeners
  self:_fire_edge_add(edge_type, from_uri, to_uri)
end

---Remove an edge
---@param from_uri string Source entity URI
---@param edge_type string Edge type
---@param to_uri string Target entity URI
function EntityStore:remove_edge(from_uri, edge_type, to_uri)
  local removed = false

  -- Remove from outgoing edges
  local outgoing = self._edges[from_uri]
  if outgoing then
    for i = #outgoing, 1, -1 do
      local e = outgoing[i]
      if e.type == edge_type and e.to == to_uri then
        table.remove(outgoing, i)
        removed = true
        break
      end
    end
  end

  -- Remove from reverse edges
  local incoming = self._reverse[to_uri]
  if incoming then
    for i = #incoming, 1, -1 do
      local e = incoming[i]
      if e.type == edge_type and e.from == from_uri then
        table.remove(incoming, i)
        break
      end
    end
  end

  -- Update sibling linked list (O(1) removal)
  local list = self._sibling_links[to_uri] and self._sibling_links[to_uri][edge_type]
  if list and list.nodes[from_uri] then
    local node = list.nodes[from_uri]
    -- Update prev's next pointer
    if node.prev then
      list.nodes[node.prev].next = node.next
    else
      list.head = node.next
    end
    -- Update next's prev pointer
    if node.next then
      list.nodes[node.next].prev = node.prev
    else
      list.tail = node.prev
    end
    list.nodes[from_uri] = nil
  end

  -- Fire edge remove listeners
  if removed then
    self:_fire_edge_remove(edge_type, from_uri, to_uri)
  end
end

---Get outgoing edges from an entity
---@param uri string Entity URI
---@param edge_type string? Optional edge type filter
---@return Edge[]
function EntityStore:edges_from(uri, edge_type)
  local edges = self._edges[uri] or {}
  if edge_type then
    local filtered = {}
    for _, e in ipairs(edges) do
      if e.type == edge_type then
        table.insert(filtered, e)
      end
    end
    return filtered
  end
  return edges
end

---Get incoming edges to an entity
---@param uri string Entity URI
---@param edge_type string? Optional edge type filter
---@return table[] Edges with .from and .type fields
function EntityStore:edges_to(uri, edge_type)
  local edges = self._reverse[uri] or {}
  if edge_type then
    local filtered = {}
    for _, e in ipairs(edges) do
      if e.type == edge_type then
        table.insert(filtered, e)
      end
    end
    return filtered
  end
  return edges
end

-- =============================================================================
-- Disposal
-- =============================================================================

---Dispose an entity and its children (cascade via parent edges)
---@param uri string Entity URI to dispose
function EntityStore:dispose_entity(uri)
  local entity = self._entities[uri]
  if not entity then return end

  local entity_type = entity._type

  -- Find children (entities with parent edge pointing to this)
  local children = {}
  local incoming = self._reverse[uri] or {}
  for _, edge in ipairs(incoming) do
    if edge.type == "parent" then
      table.insert(children, edge.from)
    end
  end

  -- Dispose children first (LIFO order for deterministic cleanup)
  for i = #children, 1, -1 do
    self:dispose_entity(children[i])
  end

  -- Run entity-specific cleanups
  local cleanups = self._entity_cleanups[uri] or {}
  for i = #cleanups, 1, -1 do
    pcall(cleanups[i])
  end
  self._entity_cleanups[uri] = nil

  -- Remove from indexes
  self:_unindex_entity(uri, entity, entity_type)

  -- Remove all edges from this entity
  local outgoing = self._edges[uri] or {}
  for _, edge in ipairs(outgoing) do
    -- Remove reverse edge
    local rev = self._reverse[edge.to]
    if rev then
      for i = #rev, 1, -1 do
        if rev[i].from == uri then
          table.remove(rev, i)
        end
      end
    end
  end
  self._edges[uri] = nil

  -- Remove all edges to this entity
  for _, edge in ipairs(incoming) do
    local out = self._edges[edge.from]
    if out then
      for i = #out, 1, -1 do
        if out[i].to == uri then
          table.remove(out, i)
        end
      end
    end
  end
  self._reverse[uri] = nil

  -- Remove from type set
  if entity_type and self._types[entity_type] then
    self._types[entity_type][uri] = nil
  end

  -- Update query caches (for Views) - before firing listeners
  self:_update_caches_on_remove(entity)

  -- Fire removal listeners
  if entity_type then
    self:_fire_removal(entity_type, entity)
  end

  -- Remove from entities
  self._entities[uri] = nil

  -- Dispose underlying entity if it has dispose method
  if entity.dispose and type(entity.dispose) == "function" then
    entity:dispose()
  end
end

-- =============================================================================
-- Index System
-- =============================================================================

---Add an index for a specific entity type
---@param index_name string Format: "type:name" (e.g., "session:by_id")
---@param getter function(entity) -> value | Signal
function EntityStore:add_index(index_name, getter)
  if self._indexes[index_name] then
    error("[EntityStore] Index already exists: " .. index_name)
  end

  self._indexes[index_name] = {
    getter = getter,
    map = {},
  }

  -- Parse type from index name
  local entity_type = index_name:match("^([^:]+):")

  -- Index existing entities of this type
  if entity_type then
    local type_set = self._types[entity_type] or {}
    for uri in pairs(type_set) do
      local entity = self._entities[uri]
      if entity then
        self:_track_entity_index(uri, entity, index_name)
      end
    end
  end
end

---Query index for all matching entities
---@param index_name string Index name
---@param key any Index key
---@return table[]? Array of entities, or nil
function EntityStore:get_by(index_name, key)
  local index = self._indexes[index_name]
  if not index then
    error("[EntityStore] Unknown index: " .. index_name)
  end

  local uri_set = index.map[key]
  if not uri_set then return nil end

  local results = {}
  for uri in pairs(uri_set) do
    local entity = self._entities[uri]
    if entity then
      table.insert(results, entity)
    end
  end

  return #results > 0 and results or nil
end

---Query index for single entity
---@param index_name string Index name
---@param key any Index key
---@return table? Single entity, or nil
function EntityStore:get_one(index_name, key)
  local results = self:get_by(index_name, key)
  if results and #results > 0 then
    return results[1]
  end
  return nil
end

---Create reactive filtered view by index
---@param index_name string Index name
---@param key any Index key
---@return table Reactive Collection
function EntityStore:where(index_name, key)
  local index = self._indexes[index_name]
  if not index then
    error("[EntityStore] Unknown index: " .. index_name)
  end

  -- Parse type from index name
  local entity_type = index_name:match("^([^:]+):")

  local collection = neostate.Collection(self._debug_name .. ":where:" .. index_name .. "=" .. tostring(key))
  collection:set_parent(self)

  -- Track signal subscriptions per entity
  local signal_subscriptions = {} -- uri -> unsubscribe function

  -- Helper to get current index value
  local function get_index_value(entity)
    local val = index.getter(entity)
    if type(val) == "table" and val.get then
      return val:get(), val  -- Return current value and Signal
    end
    return val, nil  -- Return value and nil (not a Signal)
  end

  -- Helper to check if entity matches
  local function matches(entity)
    local val = get_index_value(entity)
    return val == key
  end

  -- Watch a Signal for changes and update collection membership
  local function watch_signal(entity, signal)
    local uri = entity.uri
    -- Already watching this entity
    if signal_subscriptions[uri] then return end

    local unsub = signal:watch(function(new_val)
      if collection._disposed then return end
      if new_val == key then
        -- Entity now matches, add if not already in collection
        local found = false
        for item in collection:iter() do
          if item.uri == uri then
            found = true
            break
          end
        end
        if not found then
          collection:adopt(entity)
        end
      else
        -- Entity no longer matches, remove from collection
        collection:delete(function(e) return e.uri == uri end)
      end
    end)

    signal_subscriptions[uri] = unsub
  end

  -- Add entity and watch for Signal changes
  local function add_entity_with_watching(entity)
    local _, signal = get_index_value(entity)
    collection:adopt(entity)
    if signal then
      watch_signal(entity, signal)
    end
  end

  -- Populate with existing matches
  local uri_set = index.map[key] or {}
  for uri in pairs(uri_set) do
    local entity = self._entities[uri]
    if entity then
      add_entity_with_watching(entity)
    end
  end

  -- Subscribe to additions of this type
  if entity_type then
    local unsub_add = self:on_added(entity_type, function(entity)
      if matches(entity) then
        add_entity_with_watching(entity)
      end
    end)

    local unsub_remove = self:on_removed(entity_type, function(entity)
      collection:delete(function(e) return e.uri == entity.uri end)
      -- Cleanup signal subscription
      if signal_subscriptions[entity.uri] then
        signal_subscriptions[entity.uri]()
        signal_subscriptions[entity.uri] = nil
      end
    end)

    collection:on_dispose(unsub_add)
    collection:on_dispose(unsub_remove)
  end

  -- Cleanup all signal subscriptions on collection disposal
  collection:on_dispose(function()
    for _, unsub in pairs(signal_subscriptions) do
      pcall(unsub)
    end
  end)

  return collection
end

-- Internal: Index a single entity
function EntityStore:_index_entity(uri, entity, entity_type)
  for index_name, index in pairs(self._indexes) do
    -- Check if index applies to this entity type
    local idx_type = index_name:match("^([^:]+):")
    if idx_type == entity_type then
      self:_track_entity_index(uri, entity, index_name)
    end
  end
end

-- Internal: Track entity in a specific index (handles Signals)
function EntityStore:_track_entity_index(uri, entity, index_name)
  local index = self._indexes[index_name]
  local val = index.getter(entity)

  -- Check if value is a Signal (duck typing)
  if type(val) == "table" and val.get and val.watch then
    -- Initial value
    local current_key = val:get()
    self:_update_index_entry(uri, index_name, nil, current_key)

    -- Watch for changes
    local unsub = val:watch(function(new_key)
      local old_key = current_key
      current_key = new_key
      self:_update_index_entry(uri, index_name, old_key, new_key)
    end)

    -- Register cleanup
    self:_register_entity_cleanup(uri, unsub)
  else
    -- Static value
    self:_update_index_entry(uri, index_name, nil, val)
  end
end

-- Internal: Update index entry
function EntityStore:_update_index_entry(uri, index_name, old_key, new_key)
  local index = self._indexes[index_name]
  if not index then return end

  -- Remove from old key
  if old_key ~= nil then
    local old_set = index.map[old_key]
    if old_set then
      old_set[uri] = nil
      -- Clean up empty sets
      if not next(old_set) then
        index.map[old_key] = nil
      end
    end
  end

  -- Add to new key
  if new_key ~= nil then
    if not index.map[new_key] then
      index.map[new_key] = {}
    end
    index.map[new_key][uri] = true
  end

  -- Update query caches (for Views) when index value changes
  -- Skip initial add (old_key == nil) - _update_caches_on_add handles that
  local entity = self._entities[uri]
  if entity and old_key ~= nil then
    self:_update_caches_on_index_change(entity, index_name, old_key, new_key)
  end
end

-- Internal: Remove entity from all indexes
function EntityStore:_unindex_entity(uri, entity, entity_type)
  for index_name, index in pairs(self._indexes) do
    local idx_type = index_name:match("^([^:]+):")
    if idx_type == entity_type then
      -- Get current key
      local val = index.getter(entity)
      if type(val) == "table" and val.get then
        val = val:get()
      end
      -- Remove from index
      if val ~= nil and index.map[val] then
        index.map[val][uri] = nil
        if not next(index.map[val]) then
          index.map[val] = nil
        end
      end
    end
  end
end

-- Internal: Register cleanup for an entity
function EntityStore:_register_entity_cleanup(uri, cleanup_fn)
  if not self._entity_cleanups[uri] then
    self._entity_cleanups[uri] = {}
  end
  table.insert(self._entity_cleanups[uri], cleanup_fn)
end

-- =============================================================================
-- Event Listeners
-- =============================================================================

---Subscribe to entity additions of a type
---@param entity_type string Entity type
---@param fn function(entity) Callback receives the entity directly
---@return function Unsubscribe function
function EntityStore:on_added(entity_type, fn)
  if not self._type_listeners[entity_type] then
    self._type_listeners[entity_type] = {}
  end
  table.insert(self._type_listeners[entity_type], fn)

  return function()
    local listeners = self._type_listeners[entity_type]
    if listeners then
      for i, listener in ipairs(listeners) do
        if listener == fn then
          table.remove(listeners, i)
          break
        end
      end
    end
  end
end

---Subscribe to entity removals of a type
---@param entity_type string Entity type
---@param fn function(wrapper) Callback
---@return function Unsubscribe function
function EntityStore:on_removed(entity_type, fn)
  if not self._removal_listeners[entity_type] then
    self._removal_listeners[entity_type] = {}
  end
  table.insert(self._removal_listeners[entity_type], fn)

  return function()
    local listeners = self._removal_listeners[entity_type]
    if listeners then
      for i, listener in ipairs(listeners) do
        if listener == fn then
          table.remove(listeners, i)
          break
        end
      end
    end
  end
end

-- Internal: Fire addition listeners
function EntityStore:_fire_addition(entity_type, wrapper)
  local listeners = self._type_listeners[entity_type] or {}
  for _, fn in ipairs(listeners) do
    pcall(fn, wrapper)
  end
  -- Fire global listeners
  for _, fn in ipairs(self._global_add_listeners) do
    pcall(fn, wrapper)
  end
end

-- Internal: Fire removal listeners
function EntityStore:_fire_removal(entity_type, wrapper)
  local listeners = self._removal_listeners[entity_type] or {}
  for _, fn in ipairs(listeners) do
    pcall(fn, wrapper)
  end
  -- Fire global listeners
  for _, fn in ipairs(self._global_remove_listeners) do
    pcall(fn, wrapper)
  end
end

---Subscribe to edge additions of a specific type
---@param edge_type string Edge type
---@param fn function(from_uri, to_uri) Callback
---@return function Unsubscribe function
function EntityStore:on_edge_added(edge_type, fn)
  if not self._edge_add_listeners[edge_type] then
    self._edge_add_listeners[edge_type] = {}
  end
  table.insert(self._edge_add_listeners[edge_type], fn)

  return function()
    local listeners = self._edge_add_listeners[edge_type]
    if listeners then
      for i, listener in ipairs(listeners) do
        if listener == fn then
          table.remove(listeners, i)
          break
        end
      end
    end
  end
end

---Subscribe to edge removals of a specific type
---@param edge_type string Edge type
---@param fn function(from_uri, to_uri) Callback
---@return function Unsubscribe function
function EntityStore:on_edge_removed(edge_type, fn)
  if not self._edge_remove_listeners[edge_type] then
    self._edge_remove_listeners[edge_type] = {}
  end
  table.insert(self._edge_remove_listeners[edge_type], fn)

  return function()
    local listeners = self._edge_remove_listeners[edge_type]
    if listeners then
      for i, listener in ipairs(listeners) do
        if listener == fn then
          table.remove(listeners, i)
          break
        end
      end
    end
  end
end

-- Internal: Fire edge addition listeners
function EntityStore:_fire_edge_add(edge_type, from_uri, to_uri)
  local listeners = self._edge_add_listeners[edge_type] or {}
  for _, fn in ipairs(listeners) do
    pcall(fn, from_uri, to_uri)
  end
end

-- Internal: Fire edge removal listeners
function EntityStore:_fire_edge_remove(edge_type, from_uri, to_uri)
  local listeners = self._edge_remove_listeners[edge_type] or {}
  for _, fn in ipairs(listeners) do
    pcall(fn, from_uri, to_uri)
  end
end

-- =============================================================================
-- Sibling Helpers
-- =============================================================================

---Get the parent URI of an entity via a specific edge type
---@param uri string Entity URI
---@param edge_type string Edge type (e.g., "parent")
---@return string|nil Parent URI or nil if no parent
function EntityStore:get_parent(uri, edge_type)
  local edges = self._edges[uri] or {}
  for _, edge in ipairs(edges) do
    if edge.type == edge_type then
      return edge.to
    end
  end
  return nil
end

---Get siblings of an entity that appear BEFORE it in the children list
---@param uri string Entity URI
---@param edge_type string Edge type defining parent relationship
---@return string[] List of sibling URIs that come before uri
function EntityStore:siblings_before(uri, edge_type)
  local parent_uri = self:get_parent(uri, edge_type)
  if not parent_uri then return {} end

  -- Get all children of parent (entities with edge pointing to parent)
  local children = self:_get_neighbors(parent_uri, "in", { edge_type })

  -- Find uri's position and return all before it
  local result = {}
  for _, child_uri in ipairs(children) do
    if child_uri == uri then
      break
    end
    table.insert(result, child_uri)
  end
  return result
end

---Get siblings of an entity that appear AFTER it in the children list
---@param uri string Entity URI
---@param edge_type string Edge type defining parent relationship
---@return string[] List of sibling URIs that come after uri
function EntityStore:siblings_after(uri, edge_type)
  local parent_uri = self:get_parent(uri, edge_type)
  if not parent_uri then return {} end

  -- Get all children of parent (entities with edge pointing to parent)
  local children = self:_get_neighbors(parent_uri, "in", { edge_type })

  -- Find uri's position and return all after it
  local result = {}
  local found = false
  for _, child_uri in ipairs(children) do
    if found then
      table.insert(result, child_uri)
    elseif child_uri == uri then
      found = true
    end
  end
  return result
end

---Get the path from an entity to the root (following edge_type)
---@param uri string Starting entity URI
---@param edge_type string Edge type to follow upward
---@return string[] Path from uri to root (inclusive)
function EntityStore:path_to_root(uri, edge_type)
  local path = { uri }
  local current = uri
  while true do
    local parent = self:get_parent(current, edge_type)
    if not parent then break end
    table.insert(path, parent)
    current = parent
  end
  return path
end

-- =============================================================================
-- Graph Traversal
-- =============================================================================

---Internal: Unified reactive path-aware traversal
---Both BFS and DFS use this function - they are functionally equivalent
---@param start_uri string Starting entity URI
---@param opts table Traversal options
---@param method_name string Name for debug ("bfs" or "dfs")
---@return table Collection of reachable entities (wrappers with _virtual metadata)
function EntityStore:_traverse(start_uri, opts, method_name)
  opts = opts or {}
  local direction = opts.direction or "out"
  local edge_types = opts.edge_types
  local max_depth = opts.max_depth or math.huge
  local filter = opts.filter
  local filter_watch = opts.filter_watch
  local prune = opts.prune
  local prune_watch = opts.prune_watch
  local scanning_budget = opts.scanning_budget or math.huge
  local result_budget = opts.result_budget or math.huge
  local unique_budget = opts.unique_budget or math.huge
  local reverse = opts.reverse or false
  local order = opts.order or "pre"
  local start_at_child = opts.start_at_child  -- Include this child and siblings after it at depth 0
  local start_after_child = opts.start_after_child  -- Skip this child, include siblings after it at depth 0

  local collection = neostate.Collection(self._debug_name .. ":" .. method_name .. ":" .. start_uri)
  collection:set_parent(self)

  -- Path-aware tracking tables (keyed by virtual_uri - composite path)
  local tracked = {} -- virtual_uri -> TraversalNode
  local in_collection = {} -- virtual_uri -> true
  local pruned = {} -- virtual_uri -> true

  -- Reverse indexes for efficient lookups
  local uri_to_paths = {} -- entity_uri -> { virtual_uri -> true }
  local path_prefix_index = {} -- entity_uri -> { virtual_uri -> true }

  -- Prune signal watching (per entity, not per path)
  local prune_watched = {} -- entity_uri -> true
  local prune_subscriptions = {} -- entity_uri -> unsubscribe function

  -- Filter signal watching (per entity, not per path)
  local filter_watched = {} -- entity_uri -> true
  local filter_subscriptions = {} -- entity_uri -> unsubscribe function

  -- Budget counters
  local scan_count = 0
  local result_count = 0
  local unique_count = 0

  -- Cleanup handlers
  local cleanups = {}

  -- Helper: Check if budgets allow more scanning
  local function can_scan()
    return scan_count < scanning_budget
  end

  -- Helper: Check if budgets allow more results
  local function can_add_result()
    return result_count < result_budget and unique_count < unique_budget
  end

  -- Helper: Check if entity passes filter (with context)
  local function passes_filter_with_ctx(entity, item)
    if not filter then return true end
    local key = derive_key(entity, item.uri)
    local ctx = create_context(item, key)
    return filter(entity, ctx)
  end

  -- Helper: Check if traversal should be pruned (with context)
  local function should_prune_with_ctx(entity, item)
    if not prune then return false end
    local key = derive_key(entity, item.uri)
    local ctx = create_context(item, key)
    return prune(entity, ctx)
  end

  -- Helper: Register a path in the indexes
  -- node.path is PathWithSet, use node.path.arr for iteration
  local function register_path(node)
    -- uri_to_paths: paths ending at entity
    uri_to_paths[node.uri] = uri_to_paths[node.uri] or {}
    uri_to_paths[node.uri][node.virtual_uri] = true

    -- path_prefix_index: all paths containing entity
    local path_arr = node.path.arr
    for _, ancestor_uri in ipairs(path_arr) do
      path_prefix_index[ancestor_uri] = path_prefix_index[ancestor_uri] or {}
      path_prefix_index[ancestor_uri][node.virtual_uri] = true
    end
    -- Also index the entity itself
    path_prefix_index[node.uri] = path_prefix_index[node.uri] or {}
    path_prefix_index[node.uri][node.virtual_uri] = true
  end

  -- Helper: Unregister a path from the indexes
  -- node.path is PathWithSet, use node.path.arr for iteration
  local function unregister_path(node)
    -- uri_to_paths
    if uri_to_paths[node.uri] then
      uri_to_paths[node.uri][node.virtual_uri] = nil
      if not next(uri_to_paths[node.uri]) then
        uri_to_paths[node.uri] = nil
      end
    end

    -- path_prefix_index
    local path_arr = node.path.arr
    for _, ancestor_uri in ipairs(path_arr) do
      if path_prefix_index[ancestor_uri] then
        path_prefix_index[ancestor_uri][node.virtual_uri] = nil
        if not next(path_prefix_index[ancestor_uri]) then
          path_prefix_index[ancestor_uri] = nil
        end
      end
    end
    -- Also the entity itself
    if path_prefix_index[node.uri] then
      path_prefix_index[node.uri][node.virtual_uri] = nil
      if not next(path_prefix_index[node.uri]) then
        path_prefix_index[node.uri] = nil
      end
    end
  end

  -- Helper: Remove a path and its item from collection
  local function remove_path(virtual_uri)
    local node = tracked[virtual_uri]
    if not node then return end

    -- Remove from collection if present
    if in_collection[virtual_uri] then
      in_collection[virtual_uri] = nil
      result_count = result_count - 1
      unique_count = unique_count - 1
      collection:delete(function(w) return w._virtual and w._virtual.uri == virtual_uri end)
    end

    -- Unregister from indexes
    unregister_path(node)

    -- Remove from tracking
    pruned[virtual_uri] = nil
    tracked[virtual_uri] = nil
    scan_count = scan_count - 1
  end

  -- Helper: Remove all descendant paths of a given path
  local function remove_descendants_of_path(virtual_uri)
    local prefix = virtual_uri .. "/"
    local to_remove = {}

    -- Find all paths that start with this path (are descendants)
    for path_uri in pairs(tracked) do
      if path_uri ~= virtual_uri and vim.startswith(path_uri, prefix) then
        table.insert(to_remove, path_uri)
      end
    end

    -- Remove them
    for _, path_uri in ipairs(to_remove) do
      remove_path(path_uri)
    end
  end

  -- Forward declaration for expand_from_item
  local expand_from_item

  -- Helper: Watch prune signal for a path (once per virtual_uri)
  -- This is path-specific, so prune_watch receives context with virtual URI
  local function watch_prune_signal_for_path(entity_uri, entity, item, virtual_uri)
    if not prune_watch then return end
    if prune_watched[virtual_uri] then return end

    -- Pass item context to prune_watch so it can return path-specific signals
    local signal = prune_watch(entity, item)
    if not signal then return end

    prune_watched[virtual_uri] = true

    local unsub = signal:watch(function()
      if collection._disposed then return end

      -- Get the current node for this path
      local node = tracked[virtual_uri]
      if not node then return end

      -- Recreate item for context (node may have been updated)
      local current_item = {
        uri = node.uri,
        path = node.path,
        pathkeys = node.pathkeys,
        depth = node.depth,
        filtered_path = node.filtered_path,
        filtered_pathkeys = node.filtered_pathkeys,
        filtered_depth = node.filtered_depth,
        filtered_parent = node.filtered_parent,
      }
      local is_now_pruned = should_prune_with_ctx(entity, current_item)

      if is_now_pruned and not pruned[virtual_uri] then
        -- Entity became pruned at this path - remove descendants
        pruned[virtual_uri] = true
        remove_descendants_of_path(virtual_uri)
      elseif not is_now_pruned and pruned[virtual_uri] then
        -- Entity became unpruned at this path - expand children
        pruned[virtual_uri] = nil
        if node.depth < max_depth then
          local neighbors = self:_get_neighbors(entity_uri, direction, edge_types)
          local key = derive_key(entity, entity_uri)
          local child_filtered = compute_child_filtered(current_item, in_collection[virtual_uri], entity_uri, key)

          for _, neighbor_uri in ipairs(neighbors) do
            -- Check cycle: don't expand if neighbor is already in path (O(1) via path_set)
            if not path_contains(node.path, neighbor_uri) and entity_uri ~= neighbor_uri then
              local new_path = path_append(node.path, entity_uri)
              local new_pathkeys = append(node.pathkeys, key)
              local new_item = {
                uri = neighbor_uri,
                depth = node.depth + 1,
                path = new_path,
                pathkeys = new_pathkeys,
                filtered_path = child_filtered.path,
                filtered_pathkeys = child_filtered.pathkeys,
                filtered_depth = child_filtered.depth,
                filtered_parent = child_filtered.parent,
              }
              expand_from_item(new_item)
            end
          end
        end
      end
    end)

    prune_subscriptions[virtual_uri] = unsub
  end

  -- Helper: Watch filter signal for an entity (once per entity)
  -- Filter controls visibility only - children are still traversed regardless
  local function watch_filter_signal_for_entity(entity_uri, entity)
    if not filter_watch then return end
    if filter_watched[entity_uri] then return end

    local signal = filter_watch(entity)
    if not signal then return end

    filter_watched[entity_uri] = true

    local unsub = signal:watch(function()
      if collection._disposed then return end

      -- Check all paths at this entity
      local paths = uri_to_paths[entity_uri]
      if not paths then return end

      for virtual_uri in pairs(paths) do
        local node = tracked[virtual_uri]
        if node then
          -- Recreate item for context
          local item = {
            uri = node.uri,
            path = node.path,
            pathkeys = node.pathkeys,
            depth = node.depth,
            filtered_path = node.filtered_path,
            filtered_pathkeys = node.filtered_pathkeys,
            filtered_depth = node.filtered_depth,
            filtered_parent = node.filtered_parent,
          }
          local now_passes = passes_filter_with_ctx(entity, item)
          local was_in_collection = in_collection[virtual_uri]

          if now_passes and not was_in_collection then
            -- Entity now passes filter - add to collection
            if can_add_result() then
              local path_arr = node.path.arr
              local wrapper = create_wrapper(entity, {
                uri = virtual_uri,
                path = path_arr,
                pathkeys = node.pathkeys,
                depth = node.depth,
                parent = path_arr[#path_arr],
                filtered_path = node.filtered_path,
                filtered_pathkeys = node.filtered_pathkeys,
                filtered_depth = node.filtered_depth,
                filtered_parent = node.filtered_parent,
              })
              node.wrapper = wrapper
              in_collection[virtual_uri] = true
              result_count = result_count + 1
              unique_count = unique_count + 1
              collection:adopt(wrapper)
            end
          elseif not now_passes and was_in_collection then
            -- Entity now fails filter - remove from collection
            collection:delete(function(w)
              return w._virtual and w._virtual.uri == virtual_uri
            end)
            in_collection[virtual_uri] = nil
            node.wrapper = nil
          end
        end
      end
    end)

    filter_subscriptions[entity_uri] = unsub
  end

  -- Main BFS expansion from a traversal item
  expand_from_item = function(item)
    local uri = item.uri

    -- Get entity
    local entity = self._entities[uri]
    if not entity then return end

    -- Derive key and build virtual_uri
    local key = derive_key(entity, uri)
    local virtual_uri = build_virtual_uri(item.pathkeys, key)

    -- Skip if already tracked at this path
    if tracked[virtual_uri] then return end

    -- Cycle detection: is this entity already in our path? (O(1) via path_set)
    if path_contains(item.path, uri) then return end

    -- Depth check
    if item.depth > max_depth then return end

    -- Budget check
    if not can_scan() then return end

    -- Track this occurrence
    scan_count = scan_count + 1
    local node = {
      uri = uri,
      virtual_uri = virtual_uri,
      depth = item.depth,
      path = item.path,  -- PathWithSet
      pathkeys = item.pathkeys,
      filtered_path = item.filtered_path,
      filtered_pathkeys = item.filtered_pathkeys,
      filtered_depth = item.filtered_depth,
      filtered_parent = item.filtered_parent,
      wrapper = nil,
    }
    tracked[virtual_uri] = node
    register_path(node)

    -- Check filter
    local passes = passes_filter_with_ctx(entity, item)

    -- Compute filtered context for children
    local child_filtered = compute_child_filtered(item, passes, uri, key)

    -- Helper: Add current node to collection
    local function add_self()
      if passes and can_add_result() then
        local path_arr = item.path.arr
        local wrapper = create_wrapper(entity, {
          uri = virtual_uri,
          path = path_arr,
          pathkeys = item.pathkeys,
          depth = item.depth,
          parent = path_arr[#path_arr],
          -- filtered_* uses item (ancestors), not child_filtered (which includes self)
          filtered_path = item.filtered_path,
          filtered_pathkeys = item.filtered_pathkeys,
          filtered_depth = item.filtered_depth,
          filtered_parent = item.filtered_parent,
        })
        node.wrapper = wrapper
        in_collection[virtual_uri] = true
        result_count = result_count + 1
        unique_count = unique_count + 1
        collection:adopt(wrapper)
      end
    end

    -- Helper: Expand to neighbors (BFS uses queue, but we process inline for reactivity)
    local function expand_neighbors()
      -- Watch for filter state changes (filter controls visibility, not traversal)
      watch_filter_signal_for_entity(uri, entity)

      local is_pruned = should_prune_with_ctx(entity, item)

      -- Watch for prune state changes (pass item with virtual_uri for path-specific pruning)
      local prune_ctx = vim.tbl_extend("force", item, { uri = virtual_uri })
      watch_prune_signal_for_path(uri, entity, prune_ctx, virtual_uri)

      if is_pruned then
        pruned[virtual_uri] = true
        return {}
      end

      local children = {}
      if item.depth < max_depth and can_scan() then
        -- At depth 0 with start_at_child/start_after_child, use linked list for O(1) lookup
        local use_linked_list = item.depth == 0 and (start_at_child or start_after_child) and #edge_types == 1
        local iter_neighbors

        if use_linked_list then
          local edge_type = edge_types[1]
          local list = self._sibling_links[uri] and self._sibling_links[uri][edge_type]
          local target = start_at_child or start_after_child
          local include_target = start_at_child ~= nil

          iter_neighbors = {}
          if list and list.nodes and list.nodes[target] then
            -- Start from target (or after target), walk linked list
            local target_node = list.nodes[target]
            local current
            if include_target then
              current = target
            elseif reverse then
              current = target_node.prev
            else
              current = target_node.next
            end

            -- Limit walk to remaining scanning budget for O(window) performance
            local remaining_budget = scanning_budget - scan_count
            local walk_count = 0
            local visited = {}  -- Safety: prevent infinite loops
            while current and not visited[current] and walk_count < remaining_budget do
              visited[current] = true
              table.insert(iter_neighbors, current)
              walk_count = walk_count + 1
              local node = list.nodes[current]
              if node then
                -- Explicit if/else to avoid Lua's "and/or" gotcha with nil
                if reverse then
                  current = node.prev
                else
                  current = node.next
                end
              else
                current = nil
              end
            end
          end
        else
          -- Default: get all neighbors
          local neighbors = self:_get_neighbors(uri, direction, edge_types)
          iter_neighbors = reverse and vim.iter(neighbors):rev():totable() or neighbors
        end

        for _, neighbor_uri in ipairs(iter_neighbors) do
          -- Cycle check: don't expand if neighbor is already in path (O(1) via path_set)
          if not path_contains(item.path, neighbor_uri) and neighbor_uri ~= uri then
            local new_path = path_append(item.path, uri)
            local new_pathkeys = append(item.pathkeys, key)
            table.insert(children, {
              uri = neighbor_uri,
              depth = item.depth + 1,
              path = new_path,
              pathkeys = new_pathkeys,
              filtered_path = child_filtered.path,
              filtered_pathkeys = child_filtered.pathkeys,
              filtered_depth = child_filtered.depth,
              filtered_parent = child_filtered.parent,
            })
          end
        end
      end
      return children
    end

    -- Pre-order vs post-order
    if order == "post" then
      local children = expand_neighbors()
      for _, child_item in ipairs(children) do
        expand_from_item(child_item)
      end
      add_self()
    else
      add_self()
      local children = expand_neighbors()
      for _, child_item in ipairs(children) do
        expand_from_item(child_item)
      end
    end
  end

  -- Initial traversal from start_uri
  local start_item = {
    uri = start_uri,
    depth = 0,
    path = empty_path(),  -- PathWithSet for O(1) cycle detection
    pathkeys = {},
    filtered_path = {},
    filtered_pathkeys = {},
    filtered_depth = 0,
    filtered_parent = nil,
  }
  expand_from_item(start_item)

  -- Subscribe to entity additions
  local unsub_all_added = self:_on_any_added(function(entity)
    if collection._disposed then return end
    local uri = entity.uri

    -- Check if any tracked path's entity has this as a neighbor
    -- Find all paths where the terminal entity connects to this new entity
    for virtual_uri, node in pairs(tracked) do
      -- Skip if this path is pruned
      if pruned[virtual_uri] then goto continue end
      -- Skip if at max depth
      if node.depth >= max_depth then goto continue end

      -- Check if the terminal entity of this path connects to the new entity
      local neighbors = self:_get_neighbors(node.uri, direction, edge_types)
      for _, neighbor_uri in ipairs(neighbors) do
        if neighbor_uri == uri then
          -- Don't expand if it would create a cycle (O(1) via path_set)
          if not path_contains(node.path, uri) and uri ~= node.uri then
            local key = derive_key(self._entities[node.uri], node.uri)
            local new_path = path_append(node.path, node.uri)
            local new_pathkeys = append(node.pathkeys, key)

            -- Compute filtered context
            local item_for_filtered = {
              filtered_path = node.filtered_path,
              filtered_pathkeys = node.filtered_pathkeys,
              filtered_depth = node.filtered_depth,
              filtered_parent = node.filtered_parent,
            }
            local child_filtered = compute_child_filtered(item_for_filtered, in_collection[virtual_uri], node.uri, key)

            local new_item = {
              uri = uri,
              depth = node.depth + 1,
              path = new_path,
              pathkeys = new_pathkeys,
              filtered_path = child_filtered.path,
              filtered_pathkeys = child_filtered.pathkeys,
              filtered_depth = child_filtered.depth,
              filtered_parent = child_filtered.parent,
            }
            expand_from_item(new_item)
          end
          break
        end
      end

      ::continue::
    end
  end)
  table.insert(cleanups, unsub_all_added)

  -- Subscribe to entity removals
  local unsub_all_removed = self:_on_any_removed(function(entity)
    if collection._disposed then return end
    local uri = entity.uri

    -- Find all paths that end at this entity or contain it
    local paths_at_entity = uri_to_paths[uri]
    if paths_at_entity then
      -- Collect paths to remove (can't modify during iteration)
      local to_remove = {}
      for virtual_uri in pairs(paths_at_entity) do
        table.insert(to_remove, virtual_uri)
      end
      for _, virtual_uri in ipairs(to_remove) do
        remove_path(virtual_uri)
      end
    end

    -- Also remove any paths that pass through this entity
    local paths_containing = path_prefix_index[uri]
    if paths_containing then
      local to_remove = {}
      for virtual_uri in pairs(paths_containing) do
        table.insert(to_remove, virtual_uri)
      end
      for _, virtual_uri in ipairs(to_remove) do
        remove_path(virtual_uri)
      end
    end

    -- Cleanup prune subscription for this entity
    if prune_subscriptions[uri] then
      prune_subscriptions[uri]()
      prune_subscriptions[uri] = nil
      prune_watched[uri] = nil
    end

    -- Cleanup filter subscription for this entity
    if filter_subscriptions[uri] then
      filter_subscriptions[uri]()
      filter_subscriptions[uri] = nil
      filter_watched[uri] = nil
    end
  end)
  table.insert(cleanups, unsub_all_removed)

  -- Subscribe to edge additions for relevant edge types
  if edge_types then
    for _, edge_type in ipairs(edge_types) do
      local unsub_edge_add = self:on_edge_added(edge_type, function(from_uri, to_uri)
        if collection._disposed then return end

        -- Determine which entity is the source (tracked) and which is the target (to expand)
        local source_uri, target_uri
        if direction == "in" or direction == "both" then
          -- from_uri has edge pointing to to_uri
          -- If to_uri has tracked paths, from_uri might now be reachable
          if uri_to_paths[to_uri] then
            source_uri = to_uri
            target_uri = from_uri
          end
        end
        if direction == "out" or direction == "both" then
          -- from_uri points to to_uri
          -- If from_uri has tracked paths, to_uri might now be reachable
          if uri_to_paths[from_uri] then
            source_uri = from_uri
            target_uri = to_uri
          end
        end

        if not source_uri or not uri_to_paths[source_uri] then return end

        -- For each path ending at source_uri, potentially create new path to target_uri
        for virtual_uri in pairs(uri_to_paths[source_uri]) do
          local node = tracked[virtual_uri]
          if not node then goto continue end

          -- Skip if pruned
          if pruned[virtual_uri] then goto continue end

          -- Skip if at max depth
          if node.depth >= max_depth then goto continue end

          -- Cycle check (O(1) via path_set)
          if path_contains(node.path, target_uri) or target_uri == node.uri then goto continue end

          -- Build new item
          local key = derive_key(self._entities[node.uri], node.uri)
          local new_path = path_append(node.path, node.uri)
          local new_pathkeys = append(node.pathkeys, key)

          local item_for_filtered = {
            filtered_path = node.filtered_path,
            filtered_pathkeys = node.filtered_pathkeys,
            filtered_depth = node.filtered_depth,
            filtered_parent = node.filtered_parent,
          }
          local child_filtered = compute_child_filtered(item_for_filtered, in_collection[virtual_uri], node.uri, key)

          local new_item = {
            uri = target_uri,
            depth = node.depth + 1,
            path = new_path,
            pathkeys = new_pathkeys,
            filtered_path = child_filtered.path,
            filtered_pathkeys = child_filtered.pathkeys,
            filtered_depth = child_filtered.depth,
            filtered_parent = child_filtered.parent,
          }
          expand_from_item(new_item)

          ::continue::
        end
      end)
      table.insert(cleanups, unsub_edge_add)

      local unsub_edge_remove = self:on_edge_removed(edge_type, function(from_uri, to_uri)
        if collection._disposed then return end

        -- When an edge is removed, paths that depended on it may become invalid
        -- Find paths where from_uri -> to_uri was in the path
        local check_uri
        if direction == "in" or direction == "both" then
          check_uri = from_uri
        end
        if direction == "out" or direction == "both" then
          check_uri = to_uri
        end

        if not check_uri or check_uri == start_uri then return end

        -- Find all paths ending at check_uri
        local paths = uri_to_paths[check_uri]
        if not paths then return end

        for virtual_uri in pairs(paths) do
          local node = tracked[virtual_uri]
          if not node then goto continue end

          -- Check if this path still has a valid connection to its parent
          local path_arr = node.path.arr
          local parent_uri = path_arr[#path_arr]
          if parent_uri then
            local still_connected = false
            local parent_neighbors = self:_get_neighbors(parent_uri, direction, edge_types)
            for _, neighbor_uri in ipairs(parent_neighbors) do
              if neighbor_uri == check_uri then
                still_connected = true
                break
              end
            end

            if not still_connected then
              -- Remove this path and all its descendants
              remove_descendants_of_path(virtual_uri)
              remove_path(virtual_uri)
            end
          end

          ::continue::
        end
      end)
      table.insert(cleanups, unsub_edge_remove)
    end
  end

  -- Cleanup on collection disposal
  collection:on_dispose(function()
    for _, cleanup in ipairs(cleanups) do
      pcall(cleanup)
    end
    -- Cleanup prune subscriptions
    for _, unsub in pairs(prune_subscriptions) do
      pcall(unsub)
    end
    -- Cleanup filter subscriptions
    for _, unsub in pairs(filter_subscriptions) do
      pcall(unsub)
    end
  end)

  return collection
end

---BFS traversal from a starting entity (reactive, path-aware)
---Note: BFS and DFS are functionally equivalent in this implementation.
---Both use O(1) cycle detection and recursive expansion with path tracking.
---@param start_uri string Starting entity URI
---@param opts? { direction?: "out"|"in"|"both", edge_types?: string[], max_depth?: number, filter?: function(entity, ctx): boolean, prune?: function(entity, ctx): boolean, prune_watch?: function(entity): Signal?, filter_watch?: function(entity): Signal?, scanning_budget?: number, result_budget?: number, unique_budget?: number, reverse?: boolean, order?: "pre"|"post" }
---@return table Collection of reachable entities (wrappers with _virtual metadata)
function EntityStore:bfs(start_uri, opts)
  return self:_traverse(start_uri, opts, "bfs")
end

---DFS traversal from a starting entity (reactive, path-aware)
---Note: BFS and DFS are functionally equivalent in this implementation.
---Both use O(1) cycle detection and recursive expansion with path tracking.
---@param start_uri string Starting entity URI
---@param opts? { direction?: "out"|"in"|"both", edge_types?: string[], max_depth?: number, filter?: function(entity, ctx): boolean, prune?: function(entity, ctx): boolean, prune_watch?: function(entity): Signal?, filter_watch?: function(entity): Signal?, scanning_budget?: number, result_budget?: number, unique_budget?: number, reverse?: boolean, order?: "pre"|"post" }
---@return table Collection of reachable entities (wrappers with _virtual metadata)
function EntityStore:dfs(start_uri, opts)
  return self:_traverse(start_uri, opts, "dfs")
end

-- Internal: Subscribe to all entity additions (global)
function EntityStore:_on_any_added(fn)
  table.insert(self._global_add_listeners, fn)
  return function()
    for i, listener in ipairs(self._global_add_listeners) do
      if listener == fn then
        table.remove(self._global_add_listeners, i)
        break
      end
    end
  end
end

-- Internal: Subscribe to all entity removals (global)
function EntityStore:_on_any_removed(fn)
  table.insert(self._global_remove_listeners, fn)
  return function()
    for i, listener in ipairs(self._global_remove_listeners) do
      if listener == fn then
        table.remove(self._global_remove_listeners, i)
        break
      end
    end
  end
end

-- Internal: Get neighbor URIs
function EntityStore:_get_neighbors(uri, direction, edge_types)
  local neighbors = {}

  -- Outgoing edges
  if direction == "out" or direction == "both" then
    local edges = self._edges[uri] or {}
    for _, edge in ipairs(edges) do
      if not edge_types or vim.tbl_contains(edge_types, edge.type) then
        table.insert(neighbors, edge.to)
      end
    end
  end

  -- Incoming edges
  if direction == "in" or direction == "both" then
    local edges = self._reverse[uri] or {}
    for _, edge in ipairs(edges) do
      if not edge_types or vim.tbl_contains(edge_types, edge.type) then
        table.insert(neighbors, edge.from)
      end
    end
  end

  return neighbors
end

-- =============================================================================
-- Iteration
-- =============================================================================

---Iterate over all entities
---@return function Iterator yielding (uri, entity)
function EntityStore:iter()
  local entities = self._entities
  return coroutine.wrap(function()
    for uri, entity in pairs(entities) do
      coroutine.yield(uri, entity)
    end
  end)
end

---Iterate over entities of a type
---@param entity_type string Entity type
---@return function Iterator yielding (uri, entity)
function EntityStore:iter_type(entity_type)
  local type_set = self._types[entity_type] or {}
  local entities = self._entities
  return coroutine.wrap(function()
    for uri in pairs(type_set) do
      local entity = entities[uri]
      if entity then
        coroutine.yield(uri, entity)
      end
    end
  end)
end

return EntityStore
