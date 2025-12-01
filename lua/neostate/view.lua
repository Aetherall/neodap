-- =============================================================================
-- View: Lightweight query definition over EntityStore
-- =============================================================================
--
-- Views are reactive query definitions that delegate to EntityStore.
-- They don't store items - the store manages query caches.
--
-- Usage:
--   local stopped = store:view("thread"):where("by_state", "stopped")
--   for thread in stopped:iter() do ... end
--   stopped:on_added(function(t) ... end)
--   local any_stopped = stopped:some(function(t) return t.hit end)

local neostate = require("neostate")

---@class View
---@field _store EntityStore Reference to parent store
---@field _cache_key string Key into store._query_cache
---@field _debug_name string Debug name for logging
---@field _disposed boolean Disposal flag
local View = {}
View.__index = View

-- =============================================================================
-- Constructor
-- =============================================================================

---Create a new View
---@param store EntityStore The entity store
---@param entity_type string Entity type to query
---@param filters table[] Array of {index, key} filter tuples
---@param debug_name string? Optional debug name
---@return View
function View.new(store, entity_type, filters, debug_name)
  local self = setmetatable({}, View)

  -- Apply Disposable trait
  neostate.Disposable(self, nil, debug_name or "View")

  self._store = store
  self._entity_type = entity_type
  self._filters = filters or {}
  self._debug_name = debug_name or "View:" .. entity_type

  -- Track listener unsubscribe functions for cleanup
  self._listener_unsubs = {}

  -- Get or create cache for this query
  self._cache_key = store:_get_or_create_cache(entity_type, self._filters)

  -- Clean up listeners and release cache on disposal
  self:on_dispose(function()
    -- Unsubscribe all listeners registered by this view
    for _, unsub in ipairs(self._listener_unsubs) do
      pcall(unsub)
    end
    self._listener_unsubs = {}
    store:_release_cache(self._cache_key)
  end)

  return self
end

-- =============================================================================
-- Iteration
-- =============================================================================

---Iterate over entities in this view
---@return function Iterator yielding entities
function View:iter()
  local cache = self._store._query_cache[self._cache_key]
  if not cache then
    return function() return nil end
  end

  local store = self._store
  return coroutine.wrap(function()
    for uri in pairs(cache.uris) do
      local entity = store._entities[uri]
      if entity then
        coroutine.yield(entity)
      end
    end
  end)
end

---Count entities in this view
---@return number
function View:count()
  local cache = self._store._query_cache[self._cache_key]
  if not cache then return 0 end

  local n = 0
  for _ in pairs(cache.uris) do
    n = n + 1
  end
  return n
end

---Find first entity matching predicate
---@param predicate function(entity) -> boolean
---@return table? Entity or nil
function View:find(predicate)
  for entity in self:iter() do
    if predicate(entity) then
      return entity
    end
  end
  return nil
end

---Get first entity (convenience for single-item views)
---@return table? Entity or nil
function View:first()
  for entity in self:iter() do
    return entity
  end
  return nil
end

---Call method on all entities
---@param method string Method name
---@vararg any Arguments to pass
function View:call(method, ...)
  local args = { ... }
  for entity in self:iter() do
    if entity[method] then
      entity[method](entity, unpack(args))
    end
  end
end

-- =============================================================================
-- Reactive Subscriptions
-- =============================================================================

---Subscribe to entity additions
---@param fn function(entity) Callback
---@return function Unsubscribe function
function View:on_added(fn)
  local cache = self._store._query_cache[self._cache_key]
  if not cache then
    return function() end
  end

  table.insert(cache.listeners.add, fn)

  local unsub = function()
    for i, f in ipairs(cache.listeners.add) do
      if f == fn then
        table.remove(cache.listeners.add, i)
        break
      end
    end
  end

  -- Track for cleanup on view disposal
  table.insert(self._listener_unsubs, unsub)

  return unsub
end

---Subscribe to entity removals
---@param fn function(entity) Callback
---@return function Unsubscribe function
function View:on_removed(fn)
  local cache = self._store._query_cache[self._cache_key]
  if not cache then
    return function() end
  end

  table.insert(cache.listeners.remove, fn)

  local unsub = function()
    for i, f in ipairs(cache.listeners.remove) do
      if f == fn then
        table.remove(cache.listeners.remove, i)
        break
      end
    end
  end

  -- Track for cleanup on view disposal
  table.insert(self._listener_unsubs, unsub)

  return unsub
end

---Subscribe to existing + future entities
---@param fn function(entity) Callback (return cleanup function optional)
---@return function Unsubscribe function
function View:each(fn)
  -- Track cleanup callbacks per entity (by uri)
  local cleanups = {}

  -- Helper to call fn and store cleanup
  local function call_fn(entity)
    local ok, cleanup = pcall(fn, entity)
    if ok and type(cleanup) == "function" then
      cleanups[entity.uri] = cleanup
    end
  end

  -- Helper to run cleanup for an entity
  local function run_cleanup(entity)
    local cleanup = cleanups[entity.uri]
    if cleanup then
      cleanups[entity.uri] = nil
      pcall(cleanup)
    end
  end

  -- Call for existing entities
  for entity in self:iter() do
    call_fn(entity)
  end

  -- Subscribe to additions
  local unsub_added = self:on_added(call_fn)

  -- Subscribe to removals (to call cleanup)
  local unsub_removed = self:on_removed(run_cleanup)

  -- Return combined unsubscribe
  return function()
    unsub_added()
    unsub_removed()
    -- Run all remaining cleanups
    for uri, cleanup in pairs(cleanups) do
      pcall(cleanup)
    end
    cleanups = {}
  end
end

---Subscribe to future entities only
---@param fn function(entity) Callback
---@return function Unsubscribe function
function View:subscribe(fn)
  return self:on_added(fn)
end

-- =============================================================================
-- Chaining
-- =============================================================================

---Create derived view with additional filter
---@param index_name string Index name (without entity type prefix)
---@param key any Value to filter by
---@return View Derived view
function View:where(index_name, key)
  local full_index = self._entity_type .. ":" .. index_name
  local new_filters = {}

  -- Copy existing filters
  for _, f in ipairs(self._filters) do
    table.insert(new_filters, { index = f.index, key = f.key })
  end

  -- Add new filter
  table.insert(new_filters, { index = full_index, key = key })

  local derived = View.new(
    self._store,
    self._entity_type,
    new_filters,
    self._debug_name .. ":where:" .. index_name .. "=" .. tostring(key)
  )

  -- Parent lifecycle
  derived:set_parent(self)

  return derived
end

---Create derived view filtered by membership in a source view
---Entities are included if their index value matches any source entity's .id
---@param index_name string Index name (without entity type prefix)
---@param source_view View|table Source view/collection providing valid IDs
---@return View Derived view (reactive to both parent and source changes)
function View:where_in(index_name, source_view)
  local full_index = self._entity_type .. ":" .. index_name
  local index = self._store._indexes[full_index]

  -- Build initial valid ID set from source
  local valid_ids = {}
  for entity in source_view:iter() do
    if entity.id then
      valid_ids[entity.id] = true
    end
  end

  -- Helper to get index value (unwrap Signal)
  local function get_index_value(entity)
    if not index then return nil end
    local val = index.getter(entity)
    if type(val) == "table" and val.get then
      val = val:get()
    end
    return val
  end

  -- Helper to check if entity matches
  local function matches(entity)
    local val = get_index_value(entity)
    return valid_ids[val] == true
  end

  -- Track current matching URIs and listeners
  local current_uris = {}
  local add_listeners = {}
  local remove_listeners = {}

  -- Populate initial matches
  for entity in self:iter() do
    if matches(entity) then
      current_uris[entity.uri] = true
    end
  end

  -- Create the derived view object (lightweight, doesn't use query cache)
  local derived = setmetatable({}, { __index = View })
  neostate.Disposable(derived, nil, self._debug_name .. ":where_in:" .. index_name)

  derived._store = self._store
  derived._entity_type = self._entity_type
  derived._filters = {} -- Empty filters (we manage membership via current_uris)
  derived._debug_name = self._debug_name .. ":where_in:" .. index_name
  derived._listener_unsubs = {}

  -- Override iter to filter by current valid IDs
  function derived:iter()
    local store = self._store
    return coroutine.wrap(function()
      for uri in pairs(current_uris) do
        local entity = store._entities[uri]
        if entity then
          coroutine.yield(entity)
        end
      end
    end)
  end

  -- Override count
  function derived:count()
    local n = 0
    for _ in pairs(current_uris) do n = n + 1 end
    return n
  end

  -- Override on_added
  function derived:on_added(fn)
    table.insert(add_listeners, fn)
    local unsub = function()
      for i, f in ipairs(add_listeners) do
        if f == fn then
          table.remove(add_listeners, i)
          break
        end
      end
    end
    table.insert(self._listener_unsubs, unsub)
    return unsub
  end

  -- Override on_removed
  function derived:on_removed(fn)
    table.insert(remove_listeners, fn)
    local unsub = function()
      for i, f in ipairs(remove_listeners) do
        if f == fn then
          table.remove(remove_listeners, i)
          break
        end
      end
    end
    table.insert(self._listener_unsubs, unsub)
    return unsub
  end

  -- Fire add event
  local function fire_add(entity)
    for _, fn in ipairs(add_listeners) do
      pcall(fn, entity)
    end
  end

  -- Fire remove event
  local function fire_remove(entity)
    for _, fn in ipairs(remove_listeners) do
      pcall(fn, entity)
    end
  end

  -- Subscribe to parent view additions
  local unsub_parent_add = self:on_added(function(entity)
    if matches(entity) and not current_uris[entity.uri] then
      current_uris[entity.uri] = true
      fire_add(entity)
    end
  end)

  -- Subscribe to parent view removals
  local unsub_parent_remove = self:on_removed(function(entity)
    if current_uris[entity.uri] then
      current_uris[entity.uri] = nil
      fire_remove(entity)
    end
  end)

  -- Subscribe to source view additions (new valid IDs)
  local unsub_source_add = source_view:on_added(function(source_entity)
    if source_entity.id and not valid_ids[source_entity.id] then
      valid_ids[source_entity.id] = true
      -- Check parent for entities that now match
      for parent_entity in self:iter() do
        if matches(parent_entity) and not current_uris[parent_entity.uri] then
          current_uris[parent_entity.uri] = true
          fire_add(parent_entity)
        end
      end
    end
  end)

  -- Subscribe to source view removals (IDs no longer valid)
  local unsub_source_remove = source_view:on_removed(function(source_entity)
    if source_entity.id and valid_ids[source_entity.id] then
      valid_ids[source_entity.id] = nil
      -- Remove entities that no longer match
      local to_remove = {}
      for uri in pairs(current_uris) do
        local entity = self._store._entities[uri]
        if entity and not matches(entity) then
          table.insert(to_remove, entity)
        end
      end
      for _, entity in ipairs(to_remove) do
        current_uris[entity.uri] = nil
        fire_remove(entity)
      end
    end
  end)

  -- Cleanup on disposal
  derived:on_dispose(function()
    for _, unsub in ipairs(derived._listener_unsubs) do
      pcall(unsub)
    end
    unsub_parent_add()
    unsub_parent_remove()
    unsub_source_add()
    unsub_source_remove()
  end)

  -- Parent lifecycle
  derived:set_parent(self)

  return derived
end

---Traverse edges from entities in this view to create a new view of target entities
---@param edge_name string Edge type to follow
---@param target_type string? Optional: filter to only this entity type
---@return View Derived view of target entities
function View:follow(edge_name, target_type)
  local store = self._store

  -- Track current target URIs (entities reachable via edges from source view)
  local target_uris = {}
  -- Track edge count per target (for proper removal when count reaches 0)
  local edge_counts = {}
  -- Track source -> targets mapping (so we can remove when source leaves, even if edges already gone)
  local source_targets = {} -- source_uri -> { target_uri -> true }
  -- Track listeners
  local add_listeners = {}
  local remove_listeners = {}

  -- Helper: add a target
  local function add_target(uri)
    if target_uris[uri] then return false end
    local entity = store._entities[uri]
    if not entity then return false end
    if target_type and entity._type ~= target_type then return false end
    target_uris[uri] = true
    return true
  end

  -- Helper: fire add event
  local function fire_add(entity)
    for _, fn in ipairs(add_listeners) do
      pcall(fn, entity)
    end
  end

  -- Helper: fire remove event
  local function fire_remove(entity)
    for _, fn in ipairs(remove_listeners) do
      pcall(fn, entity)
    end
  end

  -- Helper: process edges from a source entity
  local function add_edges_from_source(source_uri)
    local edges = store:edges_from(source_uri, edge_name)
    source_targets[source_uri] = source_targets[source_uri] or {}
    for _, edge in ipairs(edges) do
      local target_uri = edge.to
      source_targets[source_uri][target_uri] = true
      edge_counts[target_uri] = (edge_counts[target_uri] or 0) + 1
      if add_target(target_uri) then
        local entity = store._entities[target_uri]
        if entity then
          fire_add(entity)
        end
      end
    end
  end

  -- Helper: remove all targets from a source (uses local tracking, not store edges)
  local function remove_edges_from_source(source_uri)
    local targets = source_targets[source_uri]
    if not targets then return end
    for target_uri in pairs(targets) do
      if edge_counts[target_uri] then
        edge_counts[target_uri] = edge_counts[target_uri] - 1
        if edge_counts[target_uri] <= 0 then
          edge_counts[target_uri] = nil
          if target_uris[target_uri] then
            target_uris[target_uri] = nil
            local entity = store._entities[target_uri]
            if entity then
              fire_remove(entity)
            end
          end
        end
      end
    end
    source_targets[source_uri] = nil
  end

  -- Populate initial targets from current source view
  for source in self:iter() do
    add_edges_from_source(source.uri)
  end

  -- Create the derived view object
  local derived = setmetatable({}, { __index = View })
  neostate.Disposable(derived, nil, self._debug_name .. ":follow:" .. edge_name)

  derived._store = store
  derived._entity_type = target_type or "any"
  derived._filters = {}
  derived._debug_name = self._debug_name .. ":follow:" .. edge_name
  derived._listener_unsubs = {}

  -- Override iter
  function derived:iter()
    return coroutine.wrap(function()
      for uri in pairs(target_uris) do
        local entity = store._entities[uri]
        if entity then
          coroutine.yield(entity)
        end
      end
    end)
  end

  -- Override count
  function derived:count()
    local n = 0
    for _ in pairs(target_uris) do n = n + 1 end
    return n
  end

  -- Override on_added
  function derived:on_added(fn)
    table.insert(add_listeners, fn)
    local unsub = function()
      for i, f in ipairs(add_listeners) do
        if f == fn then
          table.remove(add_listeners, i)
          break
        end
      end
    end
    table.insert(self._listener_unsubs, unsub)
    return unsub
  end

  -- Override on_removed
  function derived:on_removed(fn)
    table.insert(remove_listeners, fn)
    local unsub = function()
      for i, f in ipairs(remove_listeners) do
        if f == fn then
          table.remove(remove_listeners, i)
          break
        end
      end
    end
    table.insert(self._listener_unsubs, unsub)
    return unsub
  end

  -- Override where to chain properly (filter within follow results)
  function derived:where(index_name, key)
    local full_index = self._entity_type .. ":" .. index_name
    local index = store._indexes[full_index]

    -- Track current filtered URIs
    local filtered_uris = {}
    local filtered_add_listeners = {}
    local filtered_remove_listeners = {}
    local signal_subs = {} -- uri -> unsub

    -- Helper: get index value (unwrap Signal)
    local function get_index_value(entity)
      if not index then return nil end
      local val = index.getter(entity)
      if type(val) == "table" and val.get then
        return val:get(), val
      end
      return val, nil
    end

    -- Helper: check if entity matches
    local function matches(entity)
      local val = get_index_value(entity)
      return val == key
    end

    -- Helper: fire events
    local function fire_filtered_add(entity)
      for _, fn in ipairs(filtered_add_listeners) do
        pcall(fn, entity)
      end
    end
    local function fire_filtered_remove(entity)
      for _, fn in ipairs(filtered_remove_listeners) do
        pcall(fn, entity)
      end
    end

    -- Helper: add entity if it matches
    local function add_if_matches(entity)
      if filtered_uris[entity.uri] then return end
      if not matches(entity) then return end

      filtered_uris[entity.uri] = true
      fire_filtered_add(entity)

      -- Watch Signal for changes
      local _, signal = get_index_value(entity)
      if signal and signal.watch then
        signal_subs[entity.uri] = signal:watch(function()
          if not matches(entity) then
            if filtered_uris[entity.uri] then
              filtered_uris[entity.uri] = nil
              fire_filtered_remove(entity)
            end
          else
            if not filtered_uris[entity.uri] then
              filtered_uris[entity.uri] = true
              fire_filtered_add(entity)
            end
          end
        end)
      end
    end

    -- Helper: remove entity
    local function remove_entity(entity)
      if not filtered_uris[entity.uri] then return end
      filtered_uris[entity.uri] = nil
      if signal_subs[entity.uri] then
        signal_subs[entity.uri]()
        signal_subs[entity.uri] = nil
      end
      fire_filtered_remove(entity)
    end

    -- Populate initial matches from parent (follow result)
    for entity in self:iter() do
      if matches(entity) then
        filtered_uris[entity.uri] = true
        -- Watch Signal
        local _, signal = get_index_value(entity)
        if signal and signal.watch then
          signal_subs[entity.uri] = signal:watch(function()
            if not matches(entity) then
              remove_entity(entity)
            end
          end)
        end
      end
    end

    -- Create filtered view
    local filtered = setmetatable({}, { __index = View })
    neostate.Disposable(filtered, nil, self._debug_name .. ":where:" .. index_name)

    filtered._store = store
    filtered._entity_type = self._entity_type
    filtered._filters = {}
    filtered._debug_name = self._debug_name .. ":where:" .. index_name
    filtered._listener_unsubs = {}

    function filtered:iter()
      return coroutine.wrap(function()
        for uri in pairs(filtered_uris) do
          local entity = store._entities[uri]
          if entity then
            coroutine.yield(entity)
          end
        end
      end)
    end

    function filtered:count()
      local n = 0
      for _ in pairs(filtered_uris) do n = n + 1 end
      return n
    end

    function filtered:on_added(fn)
      table.insert(filtered_add_listeners, fn)
      return function()
        for i, f in ipairs(filtered_add_listeners) do
          if f == fn then
            table.remove(filtered_add_listeners, i)
            break
          end
        end
      end
    end

    function filtered:on_removed(fn)
      table.insert(filtered_remove_listeners, fn)
      return function()
        for i, f in ipairs(filtered_remove_listeners) do
          if f == fn then
            table.remove(filtered_remove_listeners, i)
            break
          end
        end
      end
    end

    -- Recursive where() to properly chain custom event subscriptions
    -- Without this, subsequent where() calls would fall back to View.where()
    -- which uses the store's query cache and doesn't propagate follow removals
    function filtered:where(next_index_name, next_key)
      local next_full_index = self._entity_type .. ":" .. next_index_name
      local next_index = store._indexes[next_full_index]

      local next_filtered_uris = {}
      local next_add_listeners = {}
      local next_remove_listeners = {}
      local next_signal_subs = {}

      local function next_get_value(entity)
        if not next_index then return nil end
        local val = next_index.getter(entity)
        if type(val) == "table" and val.get then
          return val:get(), val
        end
        return val, nil
      end

      local function next_matches(entity)
        local val = next_get_value(entity)
        return val == next_key
      end

      local function fire_next_add(entity)
        for _, fn in ipairs(next_add_listeners) do
          pcall(fn, entity)
        end
      end

      local function fire_next_remove(entity)
        for _, fn in ipairs(next_remove_listeners) do
          pcall(fn, entity)
        end
      end

      local function next_add_if_matches(entity)
        if next_filtered_uris[entity.uri] then return end
        if not next_matches(entity) then return end

        next_filtered_uris[entity.uri] = true
        fire_next_add(entity)

        local _, signal = next_get_value(entity)
        if signal and signal.watch then
          next_signal_subs[entity.uri] = signal:watch(function()
            if not next_matches(entity) then
              if next_filtered_uris[entity.uri] then
                next_filtered_uris[entity.uri] = nil
                fire_next_remove(entity)
              end
            else
              if not next_filtered_uris[entity.uri] then
                next_filtered_uris[entity.uri] = true
                fire_next_add(entity)
              end
            end
          end)
        end
      end

      local function next_remove_entity(entity)
        if not next_filtered_uris[entity.uri] then return end
        next_filtered_uris[entity.uri] = nil
        if next_signal_subs[entity.uri] then
          next_signal_subs[entity.uri]()
          next_signal_subs[entity.uri] = nil
        end
        fire_next_remove(entity)
      end

      -- Populate from parent (current filtered view)
      for entity in self:iter() do
        if next_matches(entity) then
          next_filtered_uris[entity.uri] = true
          local _, signal = next_get_value(entity)
          if signal and signal.watch then
            next_signal_subs[entity.uri] = signal:watch(function()
              if not next_matches(entity) then
                next_remove_entity(entity)
              end
            end)
          end
        end
      end

      -- Create the next filtered view (recursively chainable)
      local next_filtered = setmetatable({}, { __index = View })
      neostate.Disposable(next_filtered, nil, self._debug_name .. ":where:" .. next_index_name)

      next_filtered._store = store
      next_filtered._entity_type = self._entity_type
      next_filtered._filters = {}
      next_filtered._debug_name = self._debug_name .. ":where:" .. next_index_name
      next_filtered._listener_unsubs = {}

      function next_filtered:iter()
        return coroutine.wrap(function()
          for uri in pairs(next_filtered_uris) do
            local entity = store._entities[uri]
            if entity then
              coroutine.yield(entity)
            end
          end
        end)
      end

      function next_filtered:count()
        local n = 0
        for _ in pairs(next_filtered_uris) do n = n + 1 end
        return n
      end

      function next_filtered:on_added(fn)
        table.insert(next_add_listeners, fn)
        return function()
          for i, f in ipairs(next_add_listeners) do
            if f == fn then
              table.remove(next_add_listeners, i)
              break
            end
          end
        end
      end

      function next_filtered:on_removed(fn)
        table.insert(next_remove_listeners, fn)
        return function()
          for i, f in ipairs(next_remove_listeners) do
            if f == fn then
              table.remove(next_remove_listeners, i)
              break
            end
          end
        end
      end

      -- Recursively define where() on next_filtered
      next_filtered.where = filtered.where

      -- Subscribe to this view's events
      local unsub_add = self:on_added(function(entity)
        next_add_if_matches(entity)
      end)

      local unsub_remove = self:on_removed(function(entity)
        next_remove_entity(entity)
      end)

      next_filtered:on_dispose(function()
        unsub_add()
        unsub_remove()
        for _, unsub in pairs(next_signal_subs) do
          pcall(unsub)
        end
      end)

      next_filtered:set_parent(self)
      return next_filtered
    end

    -- Subscribe to parent (follow result) additions
    local unsub_parent_add = self:on_added(function(entity)
      add_if_matches(entity)
    end)

    -- Subscribe to parent removals
    local unsub_parent_remove = self:on_removed(function(entity)
      remove_entity(entity)
    end)

    -- Cleanup
    filtered:on_dispose(function()
      unsub_parent_add()
      unsub_parent_remove()
      for _, unsub in pairs(signal_subs) do
        pcall(unsub)
      end
    end)

    filtered:set_parent(self)
    return filtered
  end

  -- Subscribe to source view additions
  local unsub_source_add = self:on_added(function(source)
    add_edges_from_source(source.uri)
  end)

  -- Subscribe to source view removals
  local unsub_source_remove = self:on_removed(function(source)
    remove_edges_from_source(source.uri)
  end)

  -- Subscribe to edge additions of this type
  local unsub_edge_add = store:on_edge_added(edge_name, function(from_uri, to_uri)
    -- Check if source is in our view (use source_targets as proxy)
    if source_targets[from_uri] then
      -- Track this new edge
      source_targets[from_uri][to_uri] = true
      edge_counts[to_uri] = (edge_counts[to_uri] or 0) + 1
      if add_target(to_uri) then
        local entity = store._entities[to_uri]
        if entity then
          fire_add(entity)
        end
      end
    end
  end)

  -- Subscribe to edge removals of this type
  local unsub_edge_remove = store:on_edge_removed(edge_name, function(from_uri, to_uri)
    -- Check if this edge was tracked
    if source_targets[from_uri] and source_targets[from_uri][to_uri] then
      source_targets[from_uri][to_uri] = nil
      if edge_counts[to_uri] then
        edge_counts[to_uri] = edge_counts[to_uri] - 1
        if edge_counts[to_uri] <= 0 then
          edge_counts[to_uri] = nil
          if target_uris[to_uri] then
            target_uris[to_uri] = nil
            local entity = store._entities[to_uri]
            if entity then
              fire_remove(entity)
            end
          end
        end
      end
    end
  end)

  -- Cleanup on disposal
  derived:on_dispose(function()
    for _, unsub in ipairs(derived._listener_unsubs) do
      pcall(unsub)
    end
    unsub_source_add()
    unsub_source_remove()
    unsub_edge_add()
    unsub_edge_remove()
  end)

  -- Parent lifecycle
  derived:set_parent(self)

  return derived
end

---Get single entity by index (first match)
---@param index_name string Index name
---@param key any Value to match
---@return table? Entity or nil
function View:get_one(index_name, key)
  local full_index = self._entity_type .. ":" .. index_name
  local index = self._store._indexes[full_index]
  if not index then return nil end

  local cache = self._store._query_cache[self._cache_key]
  if not cache then return nil end

  -- Find first entity that matches both view filters AND the index lookup
  local uri_set = index.map[key]
  if not uri_set then return nil end

  for uri in pairs(uri_set) do
    if cache.uris[uri] then
      return self._store._entities[uri]
    end
  end

  return nil
end

-- =============================================================================
-- Computed Signals
-- =============================================================================

---Create reactive signal that is true if any entity matches predicate
---@param predicate function(entity) -> boolean|Signal
---@return Signal<boolean>
function View:some(predicate)
  local result = neostate.Signal(false, self._debug_name .. ":some")

  -- Track signal subscriptions for cleanup
  local signal_subs = {}

  local function recompute()
    if result._disposed then return end

    for entity in self:iter() do
      local val = predicate(entity)
      -- Handle Signal values
      if type(val) == "table" and val.get then
        val = val:get()
      end
      if val then
        result:set(true)
        return
      end
    end
    result:set(false)
  end

  -- Watch signals returned by predicate
  local function watch_entity(entity)
    local uri = entity.uri
    if signal_subs[uri] then return end

    local signal = predicate(entity)
    if type(signal) == "table" and signal.watch then
      local unsub = signal:watch(recompute)
      signal_subs[uri] = unsub
    end
  end

  -- Initial computation and signal watching
  for entity in self:iter() do
    watch_entity(entity)
  end
  recompute()

  -- React to additions
  local unsub_add = self:on_added(function(entity)
    watch_entity(entity)
    recompute()
  end)

  -- React to removals
  local unsub_remove = self:on_removed(function(entity)
    local uri = entity.uri
    if signal_subs[uri] then
      signal_subs[uri]()
      signal_subs[uri] = nil
    end
    recompute()
  end)

  -- Cleanup
  result:on_dispose(unsub_add)
  result:on_dispose(unsub_remove)
  result:on_dispose(function()
    for _, unsub in pairs(signal_subs) do
      pcall(unsub)
    end
  end)

  -- Parent lifecycle
  result:set_parent(self)

  return result
end

---Create reactive signal that is true if all entities match predicate
---@param predicate function(entity) -> boolean|Signal
---@return Signal<boolean>
function View:every(predicate)
  local result = neostate.Signal(true, self._debug_name .. ":every")

  local signal_subs = {}

  local function recompute()
    if result._disposed then return end

    local has_items = false
    for entity in self:iter() do
      has_items = true
      local val = predicate(entity)
      if type(val) == "table" and val.get then
        val = val:get()
      end
      if not val then
        result:set(false)
        return
      end
    end
    -- Empty collection returns true for every()
    result:set(true)
  end

  local function watch_entity(entity)
    local uri = entity.uri
    if signal_subs[uri] then return end

    local signal = predicate(entity)
    if type(signal) == "table" and signal.watch then
      local unsub = signal:watch(recompute)
      signal_subs[uri] = unsub
    end
  end

  for entity in self:iter() do
    watch_entity(entity)
  end
  recompute()

  local unsub_add = self:on_added(function(entity)
    watch_entity(entity)
    recompute()
  end)

  local unsub_remove = self:on_removed(function(entity)
    local uri = entity.uri
    if signal_subs[uri] then
      signal_subs[uri]()
      signal_subs[uri] = nil
    end
    recompute()
  end)

  result:on_dispose(unsub_add)
  result:on_dispose(unsub_remove)
  result:on_dispose(function()
    for _, unsub in pairs(signal_subs) do
      pcall(unsub)
    end
  end)

  result:set_parent(self)

  return result
end

---Create reactive aggregate signal
---@param aggregator function(items[]) -> any Aggregation function
---@param signal_getter function(entity) -> Signal? Optional: returns Signal to watch
---@return Signal
function View:aggregate(aggregator, signal_getter)
  local result = neostate.Signal(nil, self._debug_name .. ":aggregate")

  local signal_subs = {}

  local function recompute()
    if result._disposed then return end

    local items = {}
    for entity in self:iter() do
      table.insert(items, entity)
    end
    result:set(aggregator(items))
  end

  local function watch_entity(entity)
    if not signal_getter then return end

    local uri = entity.uri
    if signal_subs[uri] then return end

    local signal = signal_getter(entity)
    if signal and type(signal) == "table" and signal.watch then
      local unsub = signal:watch(recompute)
      signal_subs[uri] = unsub
    end
  end

  for entity in self:iter() do
    watch_entity(entity)
  end
  recompute()

  local unsub_add = self:on_added(function(entity)
    watch_entity(entity)
    recompute()
  end)

  local unsub_remove = self:on_removed(function(entity)
    local uri = entity.uri
    if signal_subs[uri] then
      signal_subs[uri]()
      signal_subs[uri] = nil
    end
    recompute()
  end)

  result:on_dispose(unsub_add)
  result:on_dispose(unsub_remove)
  result:on_dispose(function()
    for _, unsub in pairs(signal_subs) do
      pcall(unsub)
    end
  end)

  result:set_parent(self)

  return result
end

---Get a reactive Signal that always holds the most recently added entity
---@return Signal Signal containing the latest entity (or nil if empty)
function View:latest()
  local result = neostate.Signal(nil, self._debug_name .. ":latest")

  -- Track all current entities in order of addition
  local ordered_entities = {}  -- uri -> order index
  local entity_list = {}       -- [order] -> entity
  local next_order = 1

  -- Initialize with current entities
  for entity in self:iter() do
    ordered_entities[entity.uri] = next_order
    entity_list[next_order] = entity
    next_order = next_order + 1
  end

  -- Find the last (most recently added) entity
  local function find_latest()
    local max_order = 0
    local latest = nil
    for _, entity in pairs(entity_list) do
      local order = ordered_entities[entity.uri]
      if order and order > max_order then
        max_order = order
        latest = entity
      end
    end
    return latest
  end

  result:set(find_latest())

  local unsub_add = self:on_added(function(entity)
    ordered_entities[entity.uri] = next_order
    entity_list[next_order] = entity
    next_order = next_order + 1
    result:set(entity)
  end)

  local unsub_remove = self:on_removed(function(entity)
    local order = ordered_entities[entity.uri]
    if order then
      entity_list[order] = nil
      ordered_entities[entity.uri] = nil
    end
    if result:get() == entity then
      result:set(find_latest())
    end
  end)

  result:on_dispose(unsub_add)
  result:on_dispose(unsub_remove)
  result:set_parent(self)

  return result
end

-- =============================================================================
-- Mutation Errors (Views are read-only)
-- =============================================================================

function View:add()
  error("[View] add() not supported. Views are read-only. Use EntityStore:add() directly.")
end

function View:adopt()
  error("[View] adopt() not supported. Views are read-only. Use EntityStore:add() directly.")
end

function View:delete()
  error("[View] delete() not supported. Views are read-only. Use EntityStore:dispose_entity() directly.")
end

function View:extract()
  error("[View] extract() not supported. Views are read-only.")
end

return View
